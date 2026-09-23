import AppKit
import Combine
import Foundation

enum ScreenEdge: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var opposite: ScreenEdge {
        self == .left ? .right : .left
    }

    var label: String {
        rawValue.capitalized
    }
}

/// One ring on the rail.
enum Provider: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case cursor
    /// Cursor's Grok Bot. Its usage comes from the Cursor sign-in, but it is its own
    /// allowance, so it gets its own ring under Cursor's.
    case grokBot
    /// Google Antigravity's CLI, `agy`.
    case antigravity

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .grokBot: "Grok Bot"
        case .antigravity: "Antigravity"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow.rays"
        case .grokBot: "face.smiling"
        case .antigravity: "arrow.up.circle"
        }
    }

    /// A CLI provider stays on the rail so its "not found" or "sign in" message can be
    /// read. Grok Bot has no CLI of its own and is not part of every Cursor plan, so it
    /// earns its ring with a successful read.
    var needsProof: Bool {
        self == .grokBot
    }
}

/// One subscription in a provider's pop-out: the provider, plus the config directory
/// that holds a second sign-in for it (`CLAUDE_CONFIG_DIR=~/.claude-dev claude`).
struct MonitorSource: Hashable, Identifiable, Sendable {
    let provider: Provider
    /// nil is the CLI's own default location. Never spell the default out: for
    /// Claude Code an explicit `~/.claude` is a different sign-in than unset.
    let configDirectory: String?

    init(provider: Provider, configDirectory: String? = nil) {
        self.provider = provider
        self.configDirectory = configDirectory
    }

    static let claude = MonitorSource(provider: .claude)
    static let codex = MonitorSource(provider: .codex)
    static let cursor = MonitorSource(provider: .cursor)
    static let grokBot = MonitorSource(provider: .grokBot)
    static let antigravity = MonitorSource(provider: .antigravity)
    /// One default subscription per CLI, in rail order. Grok Bot is not here: it is
    /// found through Cursor, never on its own.
    static let defaults: [MonitorSource] = [.claude, .codex, .cursor, .antigravity]

    var id: String {
        configDirectory.map { "\(provider.rawValue):\($0)" } ?? provider.rawValue
    }

    /// The reverse of `id`, for a favourite read back from defaults.
    init?(id: String) {
        let parts = id.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let provider = Provider(rawValue: String(first)) else { return nil }
        self.provider = provider
        self.configDirectory = parts.count > 1 ? String(parts[1]) : nil
    }

    /// The folder's own name, minus the noise: "dev" for `~/.claude-dev`, "cc-work" for
    /// `~/.cc-work`. nil for the default subscription.
    var accountLabel: String? {
        guard let configDirectory else { return nil }
        let folder = URL(fileURLWithPath: configDirectory).lastPathComponent
        let name = String(folder.drop { $0 == "." })
        // Grok Bot is a Cursor sign-in, so `~/.cursor-agent2` is "agent2" for both.
        let prefix = (provider == .grokBot ? Provider.cursor : provider).rawValue
        guard name.lowercased().hasPrefix(prefix.lowercased()) else { return name.isEmpty ? folder : name }
        let rest = name.dropFirst(prefix.count).drop { "-_. ".contains($0) }
        return rest.isEmpty ? name : String(rest)
    }

    var name: String {
        accountLabel.map { "\(provider.name) (\($0))" } ?? provider.name
    }
}

enum UsageLoadState: Equatable, Sendable {
    case idle
    case refreshing
    case loaded
    case unavailable(String)
    case failed(String)
}

struct UsageLimit: Equatable, Identifiable, Sendable {
    let label: String
    let remainingFraction: Double
    let resetAt: Date?
    let resetDescription: String?
    let valueText: String?
    let showsMeter: Bool
    let contributesToSummary: Bool
    /// When true, the HUD offers a control that spends one available reset.
    let canRedeem: Bool

    var id: String { label }

    init(
        label: String,
        remainingFraction: Double,
        resetAt: Date? = nil,
        resetDescription: String? = nil,
        valueText: String? = nil,
        showsMeter: Bool = true,
        contributesToSummary: Bool = true,
        canRedeem: Bool = false
    ) {
        self.label = label
        self.remainingFraction = min(max(remainingFraction, 0), 1)
        self.resetAt = resetAt
        self.resetDescription = resetDescription
        self.valueText = valueText
        self.showsMeter = showsMeter
        self.contributesToSummary = contributesToSummary
        self.canRedeem = canRedeem
    }

    var remainingPercent: Int {
        Int((remainingFraction * 100).rounded())
    }

    var resetText: String? {
        if let resetDescription { return resetDescription }
        if let resetAt {
            return "Resets \(resetAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return nil
    }
}

struct UsageSnapshot: Equatable, Sendable {
    var source: MonitorSource
    var limits: [UsageLimit]
    var updatedAt: Date?
    var state: UsageLoadState

    init(
        source: MonitorSource = .codex,
        limits: [UsageLimit] = [],
        updatedAt: Date? = nil,
        state: UsageLoadState = .idle
    ) {
        self.source = source
        self.limits = limits
        self.updatedAt = updatedAt
        self.state = state
    }

    static func unavailable(source: MonitorSource, message: String) -> UsageSnapshot {
        UsageSnapshot(source: source, state: .unavailable(message))
    }

    static func failed(source: MonitorSource, message: String) -> UsageSnapshot {
        UsageSnapshot(source: source, state: .failed(message))
    }

    var remainingPercent: Int? {
        summaryLimit?.remainingPercent
    }

    var remainingFraction: Double? {
        summaryLimit?.remainingFraction
    }

    private var summaryLimit: UsageLimit? {
        let contributing = limits.filter(\.contributesToSummary)
        return contributing.min { $0.remainingFraction < $1.remainingFraction }
            ?? limits.first
    }

    var statusMessage: String? {
        switch state {
        case .unavailable(let message), .failed(let message): message
        default: nil
        }
    }
}

@MainActor
final class UsageMonitor: ObservableObject {
    /// Providers on the rail: the ones whose CLI is installed, plus Grok Bot once a read
    /// has proven it. The rail is sized from this list. If nothing is installed, every
    /// CLI provider stays visible so the "not found" messages explain what to install.
    @Published private(set) var providers: [Provider] = MonitorSource.defaults.map(\.provider)
    @Published private(set) var selectedProvider: Provider = .codex
    /// Every subscription found for those providers, signed in or not. All of them are
    /// read on each cycle so a sign-in that comes back shows up within a minute.
    private(set) var sources: [MonitorSource] = MonitorSource.defaults

    @Published private var snapshots: [MonitorSource: UsageSnapshot]
    /// The subscription being looked at in each provider's pop-out, while the HUD is
    /// open. Hovering a cell sets it; collapsing the HUD clears it.
    @Published private var lookedAt: [Provider: MonitorSource] = [:]
    /// The subscription each provider opens on and its ring reports: the one the user
    /// clicked to make the default. Kept across launches.
    @Published private(set) var favorites: [Provider: MonitorSource]
    /// Low subscriptions the user has already opened the HUD to see. A subscription
    /// leaves this set when it climbs back above 10%, so the next drop can alert again.
    @Published private var seenLow: Set<MonitorSource> = []
    /// True while a reset is being spent for the selected subscription.
    @Published private(set) var isRedeemingReset = false
    /// Short note after a reset attempt that did not clear usage, cleared on the next
    /// successful refresh or another redeem.
    @Published private(set) var resetStatusMessage: String?
    /// True while the HUD is open. Lows that appear then are already in view, so they
    /// do not light the idle cue after it closes.
    var isLooking = false {
        didSet { reconcileLowUsage() }
    }

    /// The idle cue stays red until the HUD is opened, once any signed-in subscription
    /// has a meter at or below 10%.
    var hasUnseenLowUsage: Bool {
        !currentLowSources.subtracting(seenLow).isEmpty
    }
    /// Subscriptions whose last conclusive read proved a sign-in. A failed read proves
    /// nothing either way, so it leaves this alone.
    private var signedIn: Set<MonitorSource> = []
    private let fetcher: any UsageFetching
    private let defaults: UserDefaults
    private var timer: Timer?
    private var refreshTasks: [MonitorSource: Task<Void, Never>] = [:]
    private var redeemTask: Task<Void, Never>?

    private static let favoritesDefaultsKey = "uNotch.favoriteSubscriptions"

    init(fetcher: any UsageFetching = CLIUsageFetcher(), defaults: UserDefaults = .standard) {
        self.fetcher = fetcher
        self.defaults = defaults
        snapshots = Dictionary(uniqueKeysWithValues: MonitorSource.defaults.map {
            ($0, UsageSnapshot(source: $0))
        })
        let stored = defaults.dictionary(forKey: Self.favoritesDefaultsKey) as? [String: String] ?? [:]
        favorites = stored.reduce(into: [:]) { result, entry in
            guard let provider = Provider(rawValue: entry.key),
                  let source = MonitorSource(id: entry.value), source.provider == provider else { return }
            result[provider] = source
        }
    }

    deinit {
        timer?.invalidate()
        refreshTasks.values.forEach { $0.cancel() }
        redeemTask?.cancel()
    }

    /// Usage for the subscription selected in the pop-out of the selected provider.
    var snapshot: UsageSnapshot {
        snapshot(for: selectedSource(for: selectedProvider))
    }

    func snapshot(for source: MonitorSource) -> UsageSnapshot {
        snapshots[source] ?? UsageSnapshot(source: source)
    }

    /// The subscriptions the pop-out offers for a provider: only the signed-in ones.
    /// Until one is proven, the provider's own default stands in so its status message
    /// can explain what to do.
    func subscriptions(for provider: Provider) -> [MonitorSource] {
        let all = sources.filter { $0.provider == provider }
        let shown = all.filter(signedIn.contains)
        if !shown.isEmpty { return shown }
        return [all.first ?? MonitorSource(provider: provider)]
    }

    /// What the provider shows: the subscription being looked at while the HUD is open,
    /// otherwise the favourite, otherwise the CLI's own default sign-in.
    func selectedSource(for provider: Provider) -> MonitorSource {
        let visible = subscriptions(for: provider)
        if let looked = lookedAt[provider], visible.contains(looked) { return looked }
        if let favorite = favorites[provider], visible.contains(favorite) { return favorite }
        return visible[0]
    }

    func isFavorite(_ source: MonitorSource) -> Bool {
        favorites[source.provider] == source
    }

    /// Makes a subscription the one its provider opens on; a second click on the
    /// favourite clears it, and the provider goes back to its default sign-in.
    func toggleFavorite(_ source: MonitorSource) {
        if favorites[source.provider] == source {
            favorites[source.provider] = nil
        } else {
            favorites[source.provider] = source
        }
        let stored = favorites.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value.id }
        defaults.set(stored, forKey: Self.favoritesDefaultsKey)
    }

    /// Forgets what was being looked at, so every ring reports its favourite again.
    func clearLookedAt() {
        if !lookedAt.isEmpty { lookedAt = [:] }
    }

    func start() {
        guard timer == nil else { return }
        requestAllRefresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.requestAllRefresh(force: false)
            }
        }
        timer?.tolerance = 8
    }

    func refreshAll() {
        requestAllRefresh(force: true)
    }

    /// Re-reads which CLIs and sign-ins exist. Runs on every refresh cycle so installing
    /// or removing one shows up within a minute without relaunching.
    func detectInstalledSources() {
        let installed = fetcher.installedSources()
        let next = installed.isEmpty ? MonitorSource.defaults : installed
        if next != sources { sources = next }
        updateProviders()
    }

    /// One ring per provider with a source worth showing, in source order.
    private func updateProviders() {
        var nextProviders: [Provider] = []
        for source in sources where !nextProviders.contains(source.provider) {
            if source.provider.needsProof && !signedIn.contains(source) { continue }
            nextProviders.append(source.provider)
        }
        // Antigravity is only a usage readout; it always sits at the bottom of the rail.
        if let index = nextProviders.firstIndex(of: .antigravity) {
            nextProviders.append(nextProviders.remove(at: index))
        }
        if nextProviders != providers { providers = nextProviders }
        if !providers.contains(selectedProvider), let first = providers.first {
            selectedProvider = first
        }
    }

    func select(_ provider: Provider) {
        guard selectedProvider != provider else { return }
        selectedProvider = provider
        resetStatusMessage = nil
    }

    func select(subscription source: MonitorSource) {
        lookedAt[source.provider] = source
        select(source.provider)
    }

    func refresh() {
        resetStatusMessage = nil
        requestRefresh(for: selectedProvider, force: true)
    }

    func refresh(_ provider: Provider) {
        select(provider)
        requestRefresh(for: provider, force: false)
    }

    /// True when the selected subscription has a reset it can spend: a banked Codex
    /// credit, or a Claude limit reset the account holds.
    var canRedeemAvailableReset: Bool {
        snapshot.limits.contains(where: \.canRedeem)
    }

    /// Spends one available reset for the selected subscription, then re-reads usage.
    func redeemAvailableReset() {
        let source = selectedSource(for: selectedProvider)
        guard canRedeemAvailableReset,
              !isRedeemingReset,
              redeemTask == nil else { return }

        isRedeemingReset = true
        resetStatusMessage = nil
        redeemTask = Task { [weak self, fetcher] in
            let result = await fetcher.redeemReset(for: source)
            guard !Task.isCancelled, let self else { return }
            self.isRedeemingReset = false
            self.redeemTask = nil
            if let message = result.statusMessage {
                self.resetStatusMessage = message
            }
            // Always re-read after a conclusive reply so the count and meters match
            // the account, including "nothing to reset" / "no credit".
            if result != .unsupported {
                self.requestRefresh(for: source, force: true)
            }
        }
    }

    func cycleProvider() {
        guard let index = providers.firstIndex(of: selectedProvider) else { return }
        select(providers[(index + 1) % providers.count])
    }

    /// The rail ring follows the subscription selected in that provider's pop-out.
    func remainingFraction(for provider: Provider) -> Double? {
        snapshot(for: selectedSource(for: provider)).remainingFraction
    }

    private func requestAllRefresh(force: Bool) {
        detectInstalledSources()
        sources.forEach { requestRefresh(for: $0, force: force) }
    }

    /// Hidden subscriptions are read too; that is the only way one comes back.
    private func requestRefresh(for provider: Provider, force: Bool) {
        sources.filter { $0.provider == provider }.forEach { requestRefresh(for: $0, force: force) }
    }

    private func requestRefresh(for source: MonitorSource, force: Bool) {
        guard refreshTasks[source] == nil else { return }
        if !force,
           let updatedAt = snapshots[source]?.updatedAt,
           Date().timeIntervalSince(updatedAt) < freshnessInterval(for: source) {
            return
        }

        var pending = snapshot(for: source)
        pending.state = .refreshing
        snapshots[source] = pending

        refreshTasks[source] = Task { [weak self, fetcher] in
            let freshSnapshot = await fetcher.fetchUsage(for: source)
            guard !Task.isCancelled, let self else { return }
            switch freshSnapshot.state {
            case .loaded: self.signedIn.insert(source)
            case .unavailable: self.signedIn.remove(source)
            default: break
            }
            self.snapshots[source] = freshSnapshot
            self.refreshTasks[source] = nil
            self.reconcileLowUsage()
            if source.provider.needsProof { self.updateProviders() }
        }
    }

    private var currentLowSources: Set<MonitorSource> {
        Set(sources.filter { signedIn.contains($0) && isLow(snapshot(for: $0)) })
    }

    private func isLow(_ snapshot: UsageSnapshot) -> Bool {
        snapshot.limits.contains { $0.showsMeter && HUDMetrics.isLowRemaining($0.remainingFraction) }
    }

    /// A low subscription is seen once the HUD is opened. It stays seen through later
    /// refreshes, including a failed read, and is forgotten only when a loaded read
    /// shows it back above 10%. That is what makes the cue fire once.
    private func reconcileLowUsage() {
        let recovered = seenLow.filter { source in
            let snapshot = snapshot(for: source)
            return snapshot.state == .loaded && !isLow(snapshot)
        }
        var next = seenLow.subtracting(recovered)
        if isLooking { next.formUnion(currentLowSources) }
        if next != seenLow { seenLow = next }
    }

    private func freshnessInterval(for source: MonitorSource) -> TimeInterval {
        switch source.provider {
        case .codex: 45
        case .claude: 60
        case .cursor: 60
        case .grokBot: 60
        case .antigravity: 60
        }
    }
}

@MainActor
final class NotchState: ObservableObject {
    enum Presentation: Equatable {
        case idle
        case expanded
    }

    @Published var edge: ScreenEdge {
        didSet { UserDefaults.standard.set(edge.rawValue, forKey: Self.edgeDefaultsKey) }
    }
    @Published var isPointerInside = false
    @Published var isExpanded = false {
        didSet {
            monitor.isLooking = isExpanded
            guard !isExpanded else { return }
            // Collapsing always returns the HUD to usage; settings never persist, and
            // neither does a subscription that was only being looked at.
            isSettingsOpen = false
            monitor.clearLookedAt()
        }
    }

    /// The settings section replaces the usage callout while open.
    @Published var isSettingsOpen = false

    let monitor: UsageMonitor
    let updater: AppUpdater
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?

    private static let edgeDefaultsKey = "uNotch.screenEdge"

    init(monitor: UsageMonitor, updater: AppUpdater? = nil) {
        self.monitor = monitor
        self.updater = updater ?? AppUpdater()
        self.edge = ScreenEdge(
            rawValue: UserDefaults.standard.string(forKey: Self.edgeDefaultsKey) ?? "left"
        ) ?? .left
    }

    var presentation: Presentation {
        if isExpanded { return .expanded }
        return .idle
    }

    func collapse() {
        isExpanded = false
    }

    func toggleEdge() {
        edge = edge.opposite
    }

    func toggleSettings() {
        isSettingsOpen.toggle()
    }

    func openSettings() {
        if !isSettingsOpen { isSettingsOpen = true }
    }

    func dragChanged(_ translation: CGSize) {
        onDragChanged?(translation)
    }

    func dragEnded() {
        onDragEnded?()
    }
}
