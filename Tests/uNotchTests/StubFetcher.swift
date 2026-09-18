import Foundation
@testable import uNotch

/// Defaults for tests that favourite a subscription. One fixed suite, emptied on the way
/// in and out: a fresh suite per test would leave a plist behind for each, since
/// `removePersistentDomain` empties a suite but keeps its file.
enum TestDefaults {
    static let suite = "uNotch.tests"

    static func fresh() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    static func clear() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
}

/// Deterministic stand-in for the CLI reader: reports which subscriptions are "installed"
/// and returns a canned snapshot for each, or an unavailable one when none is given.
struct StubFetcher: UsageFetching {
    var installed: [MonitorSource]
    var snapshots: [MonitorSource: UsageSnapshot]

    init(
        installed: [MonitorSource] = MonitorSource.defaults,
        snapshots: [MonitorSource: UsageSnapshot] = [:]
    ) {
        self.installed = installed
        self.snapshots = snapshots
    }

    /// A signed-in subscription with one limit at the given remaining fraction.
    static func loaded(_ source: MonitorSource, remaining: Double) -> UsageSnapshot {
        UsageSnapshot(
            source: source,
            limits: [UsageLimit(label: "5-hour limit", remainingFraction: remaining)],
            updatedAt: Date(),
            state: .loaded
        )
    }

    func fetchUsage(for source: MonitorSource) async -> UsageSnapshot {
        snapshots[source] ?? .unavailable(source: source, message: "stub")
    }

    func installedSources() -> [MonitorSource] {
        installed
    }
}
