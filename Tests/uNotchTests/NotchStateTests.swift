import XCTest
@testable import uNotch

@MainActor
final class NotchStateTests: XCTestCase {
    func testPointerEntryDoesNotIntroduceAnIntermediatePresentation() {
        let state = NotchState(monitor: UsageMonitor())
        XCTAssertEqual(state.presentation, .idle)

        state.isPointerInside = true
        XCTAssertEqual(state.presentation, .idle)

        state.isExpanded = true
        XCTAssertEqual(state.presentation, .expanded)
    }

    func testProviderSelectionDoesNotInventNewUsage() {
        let monitor = UsageMonitor()
        monitor.select(.claude)
        XCTAssertEqual(monitor.snapshot.source, .claude)
        XCTAssertNil(monitor.snapshot.remainingFraction)
    }

    func testRemainingFractionIsClamped() {
        XCTAssertEqual(UsageLimit(label: "High", remainingFraction: 1.4).remainingFraction, 1)
        XCTAssertEqual(UsageLimit(label: "Low", remainingFraction: -0.4).remainingFraction, 0)
    }

    func testCodexRateLimitParserChoosesWeeklyWindow() throws {
        let data = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":59,"windowDurationMins":10080,"resetsAt":1800100000}},"rateLimitsByLimitId":null}}"#.utf8)
        let snapshot = try UsageCLIParser.codex(data)
        XCTAssertEqual(snapshot.limits.map(\.label), ["5-hour limit", "Weekly limit"])
        XCTAssertEqual(snapshot.limits[1].remainingFraction, 0.41, accuracy: 0.000_001)
    }

    func testClaudeUsageParserReadsAllModelsWeeklyLimit() throws {
        let result = "Current session: 34% used · resets today\nCurrent week (all models): 36% used · resets Sep 9 at 11am (UTC)\nCurrent week (Fable): 69% used"
        let encoded = try JSONSerialization.data(withJSONObject: ["result": result])
        let snapshot = try UsageCLIParser.claude(encoded)
        XCTAssertEqual(snapshot.limits.map(\.label), ["5-hour limit", "Weekly limit"])
        XCTAssertEqual(snapshot.limits[0].remainingFraction, 0.66, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.limits[1].remainingFraction, 0.64, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.limits[1].resetDescription, "Resets Sep 9 at 11am (UTC)")
    }

    func testCursorUsageParserReadsIncludedMonthlyUsage() throws {
        let output = Data("Usage • Ultra     Resets Sep 19\nMonthly plan and on-demand usage\nIncluded        7% used".utf8)
        let snapshot = try UsageCLIParser.cursor(output)
        XCTAssertEqual(snapshot.limits.first?.label, "Monthly included")
        XCTAssertEqual(
            try XCTUnwrap(snapshot.limits.first?.remainingFraction),
            0.93,
            accuracy: 0.000_001
        )
        XCTAssertEqual(snapshot.limits.first?.resetDescription, "Resets Sep 19")
    }

    func testProviderHoverZonesMapFromTopToBottom() {
        XCTAssertEqual(ProviderHoverGeometry.source(distanceFromTop: 20, railHeight: 210), .claude)
        XCTAssertEqual(ProviderHoverGeometry.source(distanceFromTop: 105, railHeight: 210), .codex)
        XCTAssertEqual(ProviderHoverGeometry.source(distanceFromTop: 200, railHeight: 210), .cursor)
    }

    func testRailFooterIsReservedForSettingsGear() {
        let rail = HUDMetrics.railHeight(providerCount: 3)
        let footer = HUDMetrics.railFooterHeight
        XCTAssertEqual(ProviderHoverGeometry.source(distanceFromTop: rail - footer - 1, railHeight: rail, footerHeight: footer), .cursor)
        XCTAssertNil(ProviderHoverGeometry.source(distanceFromTop: rail - footer + 1, railHeight: rail, footerHeight: footer))
        XCTAssertNil(ProviderHoverGeometry.source(distanceFromTop: rail - 5, railHeight: rail, footerHeight: footer))
    }

    func testRailShrinksToTheInstalledProviders() {
        XCTAssertEqual(HUDMetrics.railHeight(providerCount: 3), 252)
        XCTAssertEqual(HUDMetrics.railHeight(providerCount: 2), 186)
        XCTAssertEqual(HUDMetrics.railHeight(providerCount: 1), 120)
        // The panel never drops below the settings callout, which must still fit.
        XCTAssertEqual(HUDMetrics.expandedSize(providerCount: 3).height, 252)
        XCTAssertEqual(HUDMetrics.expandedSize(providerCount: 2).height, HUDMetrics.settingsCalloutHeight)
        XCTAssertEqual(HUDMetrics.expandedSize(providerCount: 1).height, HUDMetrics.settingsCalloutHeight)
    }

    func testHoverRowsFollowTheInstalledProviders() {
        let sources: [MonitorSource] = [.claude, .cursor]
        let rail = HUDMetrics.railHeight(providerCount: sources.count)
        let footer = HUDMetrics.railFooterHeight
        XCTAssertEqual(ProviderHoverGeometry.source(distanceFromTop: 10, railHeight: rail, footerHeight: footer, sources: sources), .claude)
        XCTAssertEqual(ProviderHoverGeometry.source(distanceFromTop: rail - footer - 5, railHeight: rail, footerHeight: footer, sources: sources), .cursor)
        XCTAssertNil(ProviderHoverGeometry.source(distanceFromTop: 10, railHeight: rail, footerHeight: footer, sources: []))
    }

    func testMonitorShowsOnlyInstalledProvidersAndReselects() {
        let monitor = UsageMonitor(fetcher: StubFetcher(installed: [.claude, .cursor]))
        XCTAssertEqual(monitor.snapshot.source, .codex)

        monitor.detectInstalledSources()
        XCTAssertEqual(monitor.sources, [.claude, .cursor])
        XCTAssertEqual(monitor.snapshot.source, .claude, "a provider that is not installed cannot stay selected")

        monitor.cycleSource()
        XCTAssertEqual(monitor.snapshot.source, .cursor)
    }

    func testNothingInstalledKeepsEveryProviderVisible() {
        let monitor = UsageMonitor(fetcher: StubFetcher(installed: []))
        monitor.detectInstalledSources()
        XCTAssertEqual(monitor.sources, MonitorSource.allCases)
    }

    func testCollapsingClosesSettingsAndHoverZone() {
        let state = NotchState(monitor: UsageMonitor())
        state.isExpanded = true
        state.isPointerNearBottom = true
        state.toggleSettings()
        XCTAssertTrue(state.isSettingsOpen)

        state.isExpanded = false
        XCTAssertFalse(state.isSettingsOpen)
        XCTAssertFalse(state.isPointerNearBottom)
        XCTAssertEqual(state.presentation, .idle)
    }

    func testReleaseVersionComparisonIgnoresTagPrefix() {
        XCTAssertTrue(ReleaseVersion.isNewer("v1.1.0", than: "1.0.0"))
        XCTAssertTrue(ReleaseVersion.isNewer("1.0.1", than: "v1.0.0"))
        XCTAssertTrue(ReleaseVersion.isNewer("2.0", than: "1.9.9"))
        XCTAssertFalse(ReleaseVersion.isNewer("v1.0.0", than: "1.0.0"))
        XCTAssertFalse(ReleaseVersion.isNewer("0.9.9", than: "1.0.0"))
        XCTAssertFalse(ReleaseVersion.isNewer("v1.1.0", than: "dev"))
    }

    func testGitHubReleasePayloadParsesTagAndAssets() throws {
        let payload = Data(#"{"tag_name":"v1.1.0","assets":[{"name":"SHA256SUMS","browser_download_url":"https://example.com/SHA256SUMS"},{"name":"uNotch-1.1.0-arm64.dmg","browser_download_url":"https://example.com/uNotch-1.1.0-arm64.dmg"}]}"#.utf8)
        let release = try ReleaseVersion.parseGitHub(payload)
        XCTAssertEqual(release.version, "v1.1.0")
        XCTAssertEqual(release.assets.map(\.name), ["SHA256SUMS", "uNotch-1.1.0-arm64.dmg"])
        XCTAssertThrowsError(try ReleaseVersion.parseGitHub(Data("{}".utf8)))
    }

    func testUnsignedBundleIsRefusedByInstaller() {
        // A directory that is not a signed bundle must never be accepted as an update target.
        XCTAssertNil(CodeIdentity.teamIdentifier(of: FileManager.default.temporaryDirectory))
    }

    func testCLIErrorOutputIsNotSurfaced() throws {
        XCTAssertThrowsError(
            try ProcessRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", "echo private-provider-detail >&2; exit 1"],
                timeout: 1
            )
        ) { error in
            XCTAssertEqual(error as? CLIUsageError, CLIUsageError("CLI usage read failed"))
        }
    }
}
