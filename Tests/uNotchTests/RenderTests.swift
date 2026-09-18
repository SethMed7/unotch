import AppKit
import SwiftUI
import XCTest
@testable import uNotch

@MainActor
final class RenderTests: XCTestCase {
    func testExpandedHUDRendersAtExpectedSize() throws {
        let size = HUDMetrics.expandedSize(providerCount: 3)
        let image = try render(installed: MonitorSource.defaults, settingsOpen: false)
        XCTAssertEqual(image.width, Int(size.width) * 2)
        XCTAssertEqual(image.height, Int(size.height) * 2)
        try writeSnapshotIfRequested(image, variable: "UNOTCH_SNAPSHOT")
    }

    func testSettingsSectionRendersAtExpectedSize() throws {
        let size = HUDMetrics.expandedSize(providerCount: 3)
        let image = try render(installed: MonitorSource.defaults, settingsOpen: true)
        XCTAssertEqual(image.width, Int(size.width) * 2)
        XCTAssertEqual(image.height, Int(size.height) * 2)
        try writeSnapshotIfRequested(image, variable: "UNOTCH_SETTINGS_SNAPSHOT")
    }

    func testSingleProviderRendersInTheShorterPanel() throws {
        let size = HUDMetrics.expandedSize(providerCount: 1)
        let image = try render(installed: [.claude], settingsOpen: false)
        XCTAssertEqual(image.height, Int(size.height) * 2)
        try writeSnapshotIfRequested(image, variable: "UNOTCH_SINGLE_SNAPSHOT")
    }

    func testSecondSubscriptionKeepsTheRailAndPanelSize() async throws {
        let monitor = try await monitorWithClaudeSubscriptions(["/Users/someone/.claude-dev"])
        monitor.select(subscription: monitor.subscriptions(for: .claude)[1])

        let size = HUDMetrics.expandedSize(providerCount: 3)
        let image = try render(monitor: monitor, settingsOpen: false)
        XCTAssertEqual(image.width, Int(size.width) * 2)
        XCTAssertEqual(image.height, Int(size.height) * 2)
        try writeSnapshotIfRequested(image, variable: "UNOTCH_MULTI_SNAPSHOT")
    }

    /// Five subscriptions share one strip row; the callout is the same height it is
    /// for two, and nothing runs past the panel.
    func testFiveSubscriptionsShareOneStripRow() async throws {
        // Favouriting writes to defaults; keep it out of the test host's own domain.
        defer { TestDefaults.clear() }
        let monitor = try await monitorWithClaudeSubscriptions([
            "/Users/someone/.claude-dev", "/Users/someone/.cc-work",
            "/Users/someone/claude_personal", "/Users/someone/.config/anthropic-team"
        ], defaults: TestDefaults.fresh())
        XCTAssertEqual(monitor.subscriptions(for: .claude).count, 5)
        monitor.toggleFavorite(monitor.subscriptions(for: .claude)[1])
        monitor.select(subscription: monitor.subscriptions(for: .claude)[2])

        let size = HUDMetrics.expandedSize(providerCount: 3)
        let image = try render(monitor: monitor, settingsOpen: false)
        XCTAssertEqual(image.width, Int(size.width) * 2)
        XCTAssertEqual(image.height, Int(size.height) * 2)
        try writeSnapshotIfRequested(image, variable: "UNOTCH_FIVE_SNAPSHOT")
    }

    func testGrokBotRingMakesAFourRingRail() async throws {
        let grok = UsageSnapshot(
            source: .grokBot,
            limits: [UsageLimit(label: "Grok Bot", remainingFraction: 0.92, resetAt: Date().addingTimeInterval(3600))],
            updatedAt: Date(),
            state: .loaded
        )
        let monitor = UsageMonitor(fetcher: StubFetcher(
            installed: [.claude, .codex, .cursor, .grokBot],
            snapshots: [
                .claude: StubFetcher.loaded(.claude, remaining: 0.66),
                .codex: StubFetcher.loaded(.codex, remaining: 0.30),
                .cursor: StubFetcher.loaded(.cursor, remaining: 0.95),
                .grokBot: grok
            ]
        ))
        monitor.refreshAll()
        for _ in 0..<200 where monitor.providers.count < 4 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(monitor.providers, [.claude, .codex, .cursor, .grokBot])
        monitor.select(.grokBot)

        let size = HUDMetrics.expandedSize(providerCount: 4)
        let image = try render(monitor: monitor, settingsOpen: false)
        XCTAssertEqual(image.width, Int(size.width) * 2)
        XCTAssertEqual(image.height, Int(size.height) * 2)
        try writeSnapshotIfRequested(image, variable: "UNOTCH_FOUR_SNAPSHOT")
    }

    /// Claude with its default sign-in plus one extra per folder, every one signed in
    /// with the three Claude limits, beside a plain Codex and Cursor.
    private func monitorWithClaudeSubscriptions(
        _ folders: [String],
        defaults: UserDefaults = .standard
    ) async throws -> UsageMonitor {
        let extras = folders.map { MonitorSource(provider: .claude, configDirectory: $0) }
        let limits = ["5-hour limit", "Weekly limit", "Fable"].map {
            UsageLimit(label: $0, remainingFraction: 0.4, resetDescription: "Resets Sep 23 at 11am")
        }
        var snapshots: [MonitorSource: UsageSnapshot] = [.claude: StubFetcher.loaded(.claude, remaining: 0.86)]
        for extra in extras {
            snapshots[extra] = UsageSnapshot(source: extra, limits: limits, updatedAt: Date(), state: .loaded)
        }
        let monitor = UsageMonitor(
            fetcher: StubFetcher(installed: [.claude] + extras + [.codex, .cursor], snapshots: snapshots),
            defaults: defaults
        )
        monitor.refreshAll()
        for _ in 0..<200 where monitor.subscriptions(for: .claude).count < extras.count + 1 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        return monitor
    }

    private func render(installed: [MonitorSource], settingsOpen: Bool) throws -> CGImage {
        let monitor = UsageMonitor(fetcher: StubFetcher(installed: installed))
        monitor.detectInstalledSources()
        return try render(monitor: monitor, settingsOpen: settingsOpen)
    }

    private func render(monitor: UsageMonitor, settingsOpen: Bool) throws -> CGImage {
        let state = NotchState(monitor: monitor)
        state.edge = .left
        state.isExpanded = true
        state.isSettingsOpen = settingsOpen

        let size = HUDMetrics.expandedSize(providerCount: monitor.providers.count)
        let renderer = ImageRenderer(
            content: NotchRootView(state: state)
                .frame(width: size.width, height: size.height)
                .background(Color(red: 0.03, green: 0.08, blue: 0.10))
        )
        renderer.scale = 2
        return try XCTUnwrap(renderer.cgImage)
    }

    private func writeSnapshotIfRequested(_ image: CGImage, variable: String) throws {
        guard let outputPath = ProcessInfo.processInfo.environment[variable] else { return }
        let representation = NSBitmapImageRep(cgImage: image)
        try representation.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: outputPath))
    }
}
