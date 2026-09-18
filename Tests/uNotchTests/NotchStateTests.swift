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

    func testCodexParserShowsBankedResetsWhenAvailable() throws {
        let data = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":62,"windowDurationMins":10080,"resetsAt":1800000000},"secondary":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":{"availableCount":1}}}"#.utf8)
        let snapshot = try UsageCLIParser.codex(data)
        XCTAssertEqual(snapshot.limits.map(\.label), ["Weekly limit", "Resets available"])
        XCTAssertEqual(snapshot.limits[1].valueText, "1 available")
        XCTAssertFalse(snapshot.limits[1].showsMeter)
        XCTAssertFalse(snapshot.limits[1].contributesToSummary)
        XCTAssertEqual(snapshot.remainingPercent, 38)
    }

    func testCodexParserHidesBankedResetsWhenNoneRemain() throws {
        let data = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":10080,"resetsAt":1800000000},"secondary":null},"rateLimitResetCredits":{"availableCount":0}}}"#.utf8)
        let snapshot = try UsageCLIParser.codex(data)
        XCTAssertEqual(snapshot.limits.map(\.label), ["Weekly limit"])
    }

    func testClaudeUsageParserReadsAllModelsWeeklyLimit() throws {
        let result = "Current session: 34% used · resets today\nCurrent week (all models): 36% used · resets Sep 9 at 11am (UTC)\nCurrent week (Fable): 69% used"
        let encoded = try JSONSerialization.data(withJSONObject: ["result": result])
        let snapshot = try UsageCLIParser.claude(encoded)
        XCTAssertEqual(snapshot.limits.map(\.label), ["5-hour limit", "Weekly limit", "Fable"])
        XCTAssertEqual(snapshot.limits[0].remainingFraction, 0.66, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.limits[1].remainingFraction, 0.64, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.limits[1].resetDescription, "Resets Sep 9 at 11am (UTC)")
        XCTAssertFalse(snapshot.limits[1].contributesToSummary)
        XCTAssertEqual(snapshot.limits[2].remainingFraction, 0.31, accuracy: 0.000_001)
        XCTAssertFalse(snapshot.limits[2].contributesToSummary)
        XCTAssertEqual(snapshot.remainingPercent, 66)
    }

    func testClaudeRailFollowsFiveHourWindowWhenFableIsEmpty() throws {
        let result = "Current session: 2% used · resets today\nCurrent week (all models): 56% used · resets Sep 16 at 11am (UTC)\nCurrent week (Fable): 100% used · resets Sep 16 at 10:59am (UTC)"
        let encoded = try JSONSerialization.data(withJSONObject: ["result": result])
        let snapshot = try UsageCLIParser.claude(encoded)
        XCTAssertEqual(snapshot.limits[2].remainingPercent, 0)
        XCTAssertEqual(snapshot.remainingPercent, 98)
    }

    func testCursorUsageParserReadsIncludedMonthlyUsage() throws {
        let output = Data("Usage • Ultra     Resets Sep 19\nMonthly plan and on-demand usage\nIncluded        7% used".utf8)
        let snapshot = try UsageCLIParser.cursor(output)
        XCTAssertEqual(snapshot.limits.map(\.label), ["Monthly included"])
        XCTAssertEqual(
            try XCTUnwrap(snapshot.limits.first?.remainingFraction),
            0.93,
            accuracy: 0.000_001
        )
        XCTAssertEqual(snapshot.limits.first?.resetDescription, "Resets Sep 19")
    }

    func testCursorUsageParserReadsAutoAndAPIPools() throws {
        let output = Data("""
        Usage  Ultra\t\tResets Sep 19
        Monthly plan and on-demand usage
        Included\t 16% used
          Auto \t 5% used
          API\t\t 79% used
        On-Demand\t Disabled
        """.utf8)
        let snapshot = try UsageCLIParser.cursor(output)
        XCTAssertEqual(snapshot.limits.map(\.label), ["Cursor Models", "Other Models"])
        XCTAssertEqual(snapshot.limits[0].remainingFraction, 0.95, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.limits[1].remainingFraction, 0.21, accuracy: 0.000_001)
        XCTAssertFalse(snapshot.limits[1].contributesToSummary)
        XCTAssertEqual(snapshot.limits[0].resetDescription, "Resets Sep 19")
        XCTAssertEqual(snapshot.remainingPercent, 95)
    }

    func testCursorDashboardParserReadsModelPoolsAndGrokBot() throws {
        let period = Data(#"{"billingCycleEnd":"1789819317000","planUsage":{"autoPercentUsed":5.0,"apiPercentUsed":78.0,"totalPercentUsed":16.0}}"#.utf8)
        let sand = Data(#"{"usagePercent":8.0,"hasNonZeroIncludedLimit":true,"nextResetTimestampUtc":"2026-09-18T19:21:59.215Z"}"#.utf8)
        let snapshot = try UsageCLIParser.cursorDashboard(period: period, sand: sand)
        XCTAssertEqual(snapshot.limits.map(\.label), ["Cursor Models", "Other Models", "Grok Bot"])
        XCTAssertEqual(snapshot.limits[0].remainingFraction, 0.95, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.limits[1].remainingFraction, 0.22, accuracy: 0.000_001)
        XCTAssertFalse(snapshot.limits[1].contributesToSummary)
        XCTAssertEqual(snapshot.limits[2].remainingFraction, 0.92, accuracy: 0.000_001)
        XCTAssertFalse(snapshot.limits[2].contributesToSummary)
        XCTAssertNotNil(snapshot.limits[2].resetAt)
        XCTAssertEqual(snapshot.remainingPercent, 95)
    }

    func testCursorDashboardParserSkipsPooledGrokBot() throws {
        let period = Data(#"{"planUsage":{"autoPercentUsed":5,"apiPercentUsed":10}}"#.utf8)
        let sand = Data(#"{"usagePercent":8.0,"hasNonZeroIncludedLimit":true,"usesPooledEnterpriseAllowance":true}"#.utf8)
        let snapshot = try UsageCLIParser.cursorDashboard(period: period, sand: sand)
        XCTAssertEqual(snapshot.limits.map(\.label), ["Cursor Models", "Other Models"])
    }

    func testProviderHoverZonesMapFromTopToBottom() {
        XCTAssertEqual(ProviderHoverGeometry.provider(distanceFromTop: 20, railHeight: 210), .claude)
        XCTAssertEqual(ProviderHoverGeometry.provider(distanceFromTop: 105, railHeight: 210), .codex)
        XCTAssertEqual(ProviderHoverGeometry.provider(distanceFromTop: 200, railHeight: 210), .cursor)
    }

    func testRailFooterIsReservedForSettingsGear() {
        let rail = HUDMetrics.railHeight(providerCount: 3)
        let footer = HUDMetrics.railFooterHeight
        XCTAssertEqual(ProviderHoverGeometry.provider(distanceFromTop: rail - footer - 1, railHeight: rail, footerHeight: footer), .cursor)
        XCTAssertNil(ProviderHoverGeometry.provider(distanceFromTop: rail - footer + 1, railHeight: rail, footerHeight: footer))
        XCTAssertNil(ProviderHoverGeometry.provider(distanceFromTop: rail - 5, railHeight: rail, footerHeight: footer))
    }

    func testRailShrinksToTheInstalledProviders() {
        XCTAssertEqual(HUDMetrics.railHeight(providerCount: 3), 252)
        XCTAssertEqual(HUDMetrics.railHeight(providerCount: 2), 186)
        XCTAssertEqual(HUDMetrics.railHeight(providerCount: 1), 120)
        // The panel never drops below the tallest usage callout, which must still fit.
        XCTAssertEqual(HUDMetrics.expandedSize(providerCount: 3).height, 252)
        XCTAssertEqual(HUDMetrics.expandedSize(providerCount: 2).height, HUDMetrics.usageCalloutTripleHeight)
        XCTAssertEqual(HUDMetrics.expandedSize(providerCount: 1).height, HUDMetrics.usageCalloutTripleHeight)
    }

    func testHoverRowsFollowTheInstalledProviders() {
        let providers: [Provider] = [.claude, .cursor]
        let rail = HUDMetrics.railHeight(providerCount: providers.count)
        let footer = HUDMetrics.railFooterHeight
        XCTAssertEqual(ProviderHoverGeometry.provider(distanceFromTop: 10, railHeight: rail, footerHeight: footer, providers: providers), .claude)
        XCTAssertEqual(ProviderHoverGeometry.provider(distanceFromTop: rail - footer - 5, railHeight: rail, footerHeight: footer, providers: providers), .cursor)
        XCTAssertNil(ProviderHoverGeometry.provider(distanceFromTop: 10, railHeight: rail, footerHeight: footer, providers: []))
    }

    func testMonitorShowsOnlyInstalledProvidersAndReselects() {
        let monitor = UsageMonitor(fetcher: StubFetcher(installed: [.claude, .cursor]))
        XCTAssertEqual(monitor.snapshot.source, .codex)

        monitor.detectInstalledSources()
        XCTAssertEqual(monitor.providers, [.claude, .cursor])
        XCTAssertEqual(monitor.snapshot.source, .claude, "a provider that is not installed cannot stay selected")

        monitor.cycleProvider()
        XCTAssertEqual(monitor.snapshot.source, .cursor)
    }

    func testNothingInstalledKeepsEveryProviderVisible() {
        let monitor = UsageMonitor(fetcher: StubFetcher(installed: []))
        monitor.detectInstalledSources()
        XCTAssertEqual(monitor.sources, MonitorSource.defaults)
        XCTAssertEqual(monitor.providers, Provider.allCases)
    }

    func testExtraClaudeSignInsAreFoundByTheirConfigFile() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("unotch-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        for folder in [".claude", ".claude-dev", ".claude-worktrees", ".claude-work"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(folder),
                withIntermediateDirectories: true
            )
        }
        // The default sign-in keeps `.claude.json` beside `~/.claude`, never inside it.
        for file in [".claude.json", ".claude-dev/.claude.json", ".claude-work/.claude.json"] {
            try Data("{}".utf8).write(to: home.appendingPathComponent(file))
        }

        XCTAssertEqual(
            CLIUsageFetcher.claudeConfigDirectories(home: home),
            [".claude-dev", ".claude-work"].map { home.appendingPathComponent($0).path }
        )
    }

    func testSecondSubscriptionIsNamedAfterItsConfigDirectory() {
        let dev = MonitorSource(provider: .claude, configDirectory: "/Users/someone/.claude-dev")
        XCTAssertEqual(dev.accountLabel, "dev")
        XCTAssertEqual(dev.name, "Claude (dev)")
        XCTAssertNotEqual(dev, .claude)
        XCTAssertNotEqual(dev.id, MonitorSource.claude.id)
        XCTAssertNil(MonitorSource.claude.accountLabel)
        XCTAssertEqual(MonitorSource.claude.name, "Claude")
    }

    func testSecondSubscriptionSharesItsProvidersRing() async {
        let dev = MonitorSource(provider: .claude, configDirectory: "/Users/someone/.claude-dev")
        let monitor = UsageMonitor(fetcher: StubFetcher(
            installed: [.claude, dev, .codex],
            snapshots: [
                .claude: StubFetcher.loaded(.claude, remaining: 0.86),
                dev: StubFetcher.loaded(dev, remaining: 0.40)
            ]
        ))
        monitor.detectInstalledSources()
        XCTAssertEqual(monitor.providers, [.claude, .codex], "the rail holds one ring per provider")
        XCTAssertEqual(monitor.subscriptions(for: .claude), [.claude], "nothing is offered before it is proven signed in")

        monitor.refreshAll()
        await settle { monitor.subscriptions(for: .claude).count == 2 }
        XCTAssertEqual(monitor.subscriptions(for: .claude), [.claude, dev])
        XCTAssertEqual(monitor.providers, [.claude, .codex])

        monitor.select(.claude)
        XCTAssertEqual(monitor.snapshot.source, .claude)
        XCTAssertEqual(try XCTUnwrap(monitor.remainingFraction(for: .claude)), 0.86, accuracy: 0.000_001)

        monitor.select(subscription: dev)
        XCTAssertEqual(monitor.snapshot.source, dev)
        XCTAssertEqual(try XCTUnwrap(monitor.remainingFraction(for: .claude)), 0.40, accuracy: 0.000_001, "the ring follows the pop-out's selection")

        monitor.cycleProvider()
        monitor.cycleProvider()
        XCTAssertEqual(monitor.snapshot.source, dev, "each provider remembers its subscription")
    }

    func testSignedOutSubscriptionIsNotOffered() async {
        let dev = MonitorSource(provider: .claude, configDirectory: "/Users/someone/.claude-dev")
        let monitor = UsageMonitor(fetcher: StubFetcher(
            installed: [.claude, dev],
            snapshots: [
                .claude: StubFetcher.loaded(.claude, remaining: 0.86),
                dev: .unavailable(source: dev, message: "Sign in with Claude Code")
            ]
        ))
        monitor.select(subscription: dev)
        monitor.refreshAll()
        await settle { monitor.snapshot(for: dev).state == .unavailable("Sign in with Claude Code") }

        XCTAssertEqual(monitor.subscriptions(for: .claude), [.claude])
        XCTAssertEqual(monitor.snapshot.source, .claude, "a hidden subscription cannot stay selected")
    }

    func testProviderWithNoSignInStillExplainsItself() async {
        let monitor = UsageMonitor(fetcher: StubFetcher(
            installed: [.claude],
            snapshots: [.claude: .unavailable(source: .claude, message: "Sign in with Claude Code")]
        ))
        monitor.refreshAll()
        await settle { monitor.snapshot.statusMessage != nil }
        XCTAssertEqual(monitor.providers, [.claude])
        XCTAssertEqual(monitor.snapshot.statusMessage, "Sign in with Claude Code")
    }

    func testFailedReadDoesNotHideASignedInSubscription() async {
        let dev = MonitorSource(provider: .claude, configDirectory: "/Users/someone/.claude-dev")
        final class Flaky: UsageFetching, @unchecked Sendable {
            var fails = false
            let dev: MonitorSource
            init(dev: MonitorSource) { self.dev = dev }
            func installedSources() -> [MonitorSource] { [.claude, dev] }
            func fetchUsage(for source: MonitorSource) async -> UsageSnapshot {
                fails && source == dev
                    ? .failed(source: source, message: "CLI usage read timed out")
                    : StubFetcher.loaded(source, remaining: 0.5)
            }
        }
        let fetcher = Flaky(dev: dev)
        let monitor = UsageMonitor(fetcher: fetcher)
        monitor.refreshAll()
        await settle { monitor.subscriptions(for: .claude).count == 2 }

        fetcher.fails = true
        monitor.refreshAll()
        await settle { monitor.snapshot(for: dev).statusMessage != nil }
        XCTAssertEqual(monitor.subscriptions(for: .claude), [.claude, dev], "a timeout is not proof of a sign-out")
    }

    /// Lets the monitor's fetch tasks land on the main actor.
    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testOnlyASecondSubscriptionInstalledIsSelectedOnDetection() {
        let dev = MonitorSource(provider: .claude, configDirectory: "/Users/someone/.claude-dev")
        let monitor = UsageMonitor(fetcher: StubFetcher(installed: [dev]))
        monitor.detectInstalledSources()
        XCTAssertEqual(monitor.snapshot.source, dev)
    }

    func testClaudeParserKeepsTheSubscriptionItWasReadFor() throws {
        let dev = MonitorSource(provider: .claude, configDirectory: "/Users/someone/.claude-dev")
        let encoded = try JSONSerialization.data(withJSONObject: ["result": "Current session: 10% used"])
        XCTAssertEqual(try UsageCLIParser.claude(encoded, source: dev).source, dev)
        XCTAssertEqual(try UsageCLIParser.claude(encoded).source, .claude)
    }

    func testClaudeSignedOutIsOnlyReportedWhenTheCLISaysSo() {
        XCTAssertTrue(UsageCLIParser.claudeIsSignedOut(Data(#"{"loggedIn":false,"authMethod":"none"}"#.utf8)))
        XCTAssertFalse(UsageCLIParser.claudeIsSignedOut(Data(#"{"loggedIn":true,"authMethod":"claude.ai"}"#.utf8)))
        XCTAssertFalse(UsageCLIParser.claudeIsSignedOut(Data("not json".utf8)))
    }

    func testFailingExitCanStillReturnOutput() throws {
        let output = try ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", #"echo '{"loggedIn":false}'; exit 1"#],
            timeout: 2,
            requiresCleanExit: false
        )
        XCTAssertTrue(UsageCLIParser.claudeIsSignedOut(output))
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
