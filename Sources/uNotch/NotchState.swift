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

enum MonitorSource: String, CaseIterable, Identifiable {
    case claude
    case codex
    case cursor

    var id: String { rawValue }

    var name: String {
        rawValue.capitalized
    }

    var modelName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor Agent"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow.rays"
        }
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

    var id: String { label }

    init(
        label: String,
        remainingFraction: Double,
        resetAt: Date? = nil,
        resetDescription: String? = nil
    ) {
        self.label = label
        self.remainingFraction = min(max(remainingFraction, 0), 1)
        self.resetAt = resetAt
        self.resetDescription = resetDescription
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
        limits.min { $0.remainingFraction < $1.remainingFraction }
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
    @Published private(set) var snapshot: UsageSnapshot
    /// Providers shown in the HUD: the ones whose CLI is installed. The rail is sized
    /// from this list. If nothing is installed, every provider stays visible so the
    /// "not found" messages explain what to install.
    @Published private(set) var sources: [MonitorSource] = MonitorSource.allCases

    private var snapshots: [MonitorSource: UsageSnapshot]
    private let fetcher: any UsageFetching
    private var timer: Timer?
    private var refreshTasks: [MonitorSource: Task<Void, Never>] = [:]

    init(fetcher: any UsageFetching = CLIUsageFetcher()) {
        self.fetcher = fetcher
        snapshots = Dictionary(uniqueKeysWithValues: MonitorSource.allCases.map {
            ($0, UsageSnapshot(source: $0))
        })
        snapshot = UsageSnapshot(source: .codex)
    }

    deinit {
        timer?.invalidate()
        refreshTasks.values.forEach { $0.cancel() }
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

    /// Re-reads which CLIs exist. Runs on every refresh cycle so installing or
    /// removing a CLI shows up within a minute without relaunching.
    func detectInstalledSources() {
        let installed = fetcher.installedSources()
        let next = installed.isEmpty ? MonitorSource.allCases : installed
        if next != sources { sources = next }
        if !sources.contains(snapshot.source), let first = sources.first {
            select(first)
        }
    }

    func select(_ source: MonitorSource) {
        guard let storedSnapshot = snapshots[source] else { return }
        snapshot = storedSnapshot
    }

    func refresh() {
        requestRefresh(for: snapshot.source, force: true)
    }

    func refresh(_ source: MonitorSource) {
        select(source)
        requestRefresh(for: source, force: false)
    }

    func cycleSource() {
        guard let index = sources.firstIndex(of: snapshot.source) else { return }
        select(sources[(index + 1) % sources.count])
    }

    func remainingFraction(for source: MonitorSource) -> Double? {
        snapshots[source]?.remainingFraction
    }

    private func requestAllRefresh(force: Bool) {
        detectInstalledSources()
        sources.forEach { requestRefresh(for: $0, force: force) }
    }

    private func requestRefresh(for source: MonitorSource, force: Bool) {
        guard refreshTasks[source] == nil else { return }
        if !force,
           let updatedAt = snapshots[source]?.updatedAt,
           Date().timeIntervalSince(updatedAt) < freshnessInterval(for: source) {
            return
        }

        var pending = snapshots[source] ?? UsageSnapshot(source: source)
        pending.state = .refreshing
        snapshots[source] = pending
        if snapshot.source == source { snapshot = pending }

        refreshTasks[source] = Task { [weak self, fetcher] in
            let freshSnapshot = await fetcher.fetchUsage(for: source)
            guard !Task.isCancelled, let self else { return }
            self.snapshots[source] = freshSnapshot
            if self.snapshot.source == source {
                self.snapshot = freshSnapshot
            }
            self.refreshTasks[source] = nil
        }
    }

    private func freshnessInterval(for source: MonitorSource) -> TimeInterval {
        switch source {
        case .codex: 45
        case .claude: 60
        case .cursor: 300
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
