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

    var id: String { rawValue }

    var name: String {
        rawValue.capitalized
    }

    var symbol: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow.rays"
        }
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
    /// One default subscription per provider, in rail order.
    static let defaults: [MonitorSource] = [.claude, .codex, .cursor]

    var id: String {
        configDirectory.map { "\(provider.rawValue):\($0)" } ?? provider.rawValue
    }

    /// "dev" for `~/.claude-dev`; nil for the default subscription.
    var accountLabel: String? {
        guard let configDirectory else { return nil }
        let folder = URL(fileURLWithPath: configDirectory).lastPathComponent
        let prefix = ".\(provider.rawValue)-"
        return folder.hasPrefix(prefix) ? String(folder.dropFirst(prefix.count)) : folder
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

    var id: String { label }

    init(
        label: String,
        remainingFraction: Double,
        resetAt: Date? = nil,
        resetDescription: String? = nil,
        valueText: String? = nil,
        showsMeter: Bool = true,
        contributesToSummary: Bool = true
    ) {
        self.label = label
        self.remainingFraction = min(max(remainingFraction, 0), 1)
        self.resetAt = resetAt
        self.resetDescription = resetDescription
        self.valueText = valueText
        self.showsMeter = showsMeter
        self.contributesToSummary = contributesToSummary
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
    /// Providers on the rail: the ones whose CLI is installed. The rail is sized from
    /// this list. If nothing is installed, every provider stays visible so the
    /// "not found" messages explain what to install.
    @Published private(set) var providers: [Provider] = Provider.allCases
    @Published private(set) var selectedProvider: Provider = .codex
    /// Every subscription found for those providers, signed in or not. All of them are
    /// read on each cycle so a sign-in that comes back shows up within a minute.
    private(set) var sources: [MonitorSource] = MonitorSource.defaults

    @Published private var snapshots: [MonitorSource: UsageSnapshot]
    @Published private var selectedSources: [Provider: MonitorSource] = [:]
    /// Subscriptions whose last conclusive read proved a sign-in. A failed read proves
    /// nothing either way, so it leaves this alone.
    private var signedIn: Set<MonitorSource> = []
    private let fetcher: any UsageFetching
    private var timer: Timer?
    private var refreshTasks: [MonitorSource: Task<Void, Never>] = [:]

    init(fetcher: any UsageFetching = CLIUsageFetcher()) {
        self.fetcher = fetcher
        snapshots = Dictionary(uniqueKeysWithValues: MonitorSource.defaults.map {
            ($0, UsageSnapshot(source: $0))
        })
    }

    deinit {
        timer?.invalidate()
        refreshTasks.values.forEach { $0.cancel() }
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

    func selectedSource(for provider: Provider) -> MonitorSource {
        let visible = subscriptions(for: provider)
        if let chosen = selectedSources[provider], visible.contains(chosen) { return chosen }
        return visible[0]
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

        var nextProviders: [Provider] = []
        for source in next where !nextProviders.contains(source.provider) {
            nextProviders.append(source.provider)
        }
        if nextProviders != providers { providers = nextProviders }
        if !providers.contains(selectedProvider), let first = providers.first {
            selectedProvider = first
        }
    }

    func select(_ provider: Provider) {
        if selectedProvider != provider { selectedProvider = provider }
    }

    func select(subscription source: MonitorSource) {
        selectedSources[source.provider] = source
        select(source.provider)
    }

    func refresh() {
        requestRefresh(for: selectedProvider, force: true)
    }

    func refresh(_ provider: Provider) {
        select(provider)
        requestRefresh(for: provider, force: false)
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
        }
    }

    private func freshnessInterval(for source: MonitorSource) -> TimeInterval {
        switch source.provider {
        case .codex: 45
        case .claude: 60
        case .cursor: 60
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
            guard !isExpanded else { return }
            // Collapsing always returns the HUD to usage; settings never persist.
            isSettingsOpen = false
            isPointerNearBottom = false
        }
    }

    /// The settings section replaces the usage callout while open.
    @Published var isSettingsOpen = false
    /// True while the pointer is within the bottom hover zone of the expanded HUD.
    @Published var isPointerNearBottom = false

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

    func dragChanged(_ translation: CGSize) {
        onDragChanged?(translation)
    }

    func dragEnded() {
        onDragEnded?()
    }
}
