import Foundation
@testable import uNotch

/// Deterministic stand-in for the CLI reader: reports which providers are "installed"
/// and returns an unavailable snapshot for every fetch.
struct StubFetcher: UsageFetching {
    var installed: [MonitorSource]

    init(installed: [MonitorSource] = MonitorSource.allCases) {
        self.installed = installed
    }

    func fetchUsage(for source: MonitorSource) async -> UsageSnapshot {
        .unavailable(source: source, message: "stub")
    }

    func installedSources() -> [MonitorSource] {
        installed
    }
}
