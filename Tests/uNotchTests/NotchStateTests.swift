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
        XCTAssertEqual(snapshot.limits.map(\.label), ["Weekly limit", "Resets available"])
        XCTAssertEqual(snapshot.limits[1].valueText, "0 resets")
        XCTAssertFalse(snapshot.limits[1].showsMeter)
    }

    func testClaudeUsageParserReadsAllModelsWeeklyLimit() throws {
        let result = "Current session: 34% used · resets today\nCurrent week (all models): 36% used · resets Sep 9 at 11am (UTC)\nCurrent week (Fable): 69% used"
        let encoded = try JSONSerialization.data(withJSONObject: ["result": result])
        let snapshot = try UsageCLIParser.claude(encoded)
        XCTAssertEqual(snapshot.limits.map(\.label), ["5-hour limit", "Weekly limit", "Fable"])
        XCTAssertEqual(snapshot.limits[0].remainingFraction, 0.66, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.limits[1].remainingFraction, 0.64, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.limits[1].resetDescription, "Resets Sep 9 at 11am (UTC)")
        XCTAssertTrue(snapshot.limits[1].contributesToSummary)
        XCTAssertEqual(snapshot.limits[2].remainingFraction, 0.31, accuracy: 0.000_001)
        XCTAssertFalse(snapshot.limits[2].contributesToSummary)
        XCTAssertEqual(snapshot.remainingPercent, 64, "the ring follows weekly when it is lower than the 5-hour window")
    }

    func testClaudeRailFollowsFiveHourWindowWhenFableIsEmpty() throws {
        let result = "Current session: 2% used · resets today\nCurrent week (all models): 56% used · resets Sep 16 at 11am (UTC)\nCurrent week (Fable): 100% used · resets Sep 16 at 10:59am (UTC)"
        let encoded = try JSONSerialization.data(withJSONObject: ["result": result])
        let snapshot = try UsageCLIParser.claude(encoded)
        XCTAssertEqual(snapshot.limits[2].remainingPercent, 0)
        XCTAssertEqual(snapshot.remainingPercent, 44, "an empty Fable week does not drive the ring; the weekly limit does")
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

    func testCursorDashboardParserReadsModelPoolsOnly() throws {
        let period = Data(#"{"billingCycleEnd":"1789819317000","planUsage":{"autoPercentUsed":5.0,"apiPercentUsed":78.0,"totalPercentUsed":16.0}}"#.utf8)
        let snapshot = try UsageCLIParser.cursorDashboard(period: period)
        XCTAssertEqual(snapshot.limits.map(\.label), ["Cursor Models", "Other Models"], "Grok Bot has its own ring now")
        XCTAssertEqual(snapshot.limits[0].remainingFraction, 0.95, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.limits[1].remainingFraction, 0.22, accuracy: 0.000_001)
        XCTAssertFalse(snapshot.limits[1].contributesToSummary)
        XCTAssertEqual(snapshot.remainingPercent, 95)
        XCTAssertEqual(snapshot.source, .cursor)
    }

    func testCursorDashboardKeepsTheSubscriptionItWasReadFor() throws {
        let agent2 = MonitorSource(provider: .cursor, configDirectory: "/Users/someone/.cursor-agent2")
        let period = Data(#"{"billingCycleEnd":"1789819317000","planUsage":{"autoPercentUsed":1.0,"apiPercentUsed":0}}"#.utf8)
        XCTAssertEqual(try UsageCLIParser.cursorDashboard(period: period, source: agent2).source, agent2)
        XCTAssertEqual(agent2.accountLabel, "agent2")
        XCTAssertEqual(
            CLIUsageFetcher.cursorKeychainName(forConfigDirectory: agent2.configDirectory ?? "")?.service,
            "cursor-agent2-access-token"
        )
        XCTAssertNil(CLIUsageFetcher.cursorKeychainName(forConfigDirectory: "/Users/someone/.cursor"))
    }

    func testCursorFileStoreIsASecondSubscriptionOnlyWhenItIsSomeoneElse() {
        func token(for subject: String) -> String {
            func part(_ json: String) -> String {
                Data(json.utf8).base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
            }
            return "\(part(#"{"alg":"none"}"#)).\(part(#"{"sub":"\#(subject)"}"#)).sig"
        }

        let first = token(for: "auth0|first")
        let second = token(for: "auth0|second")
        XCTAssertEqual(CLIUsageFetcher.cursorTokenSubject(second), "auth0|second")

        XCTAssertEqual(
            CLIUsageFetcher.cursorSessionToken(
                keychainToken: first,
                directoryToken: nil,
                defaultFileToken: second,
                authId: "auth0|second"
            ),
            second,
            "the file store is the second login when its subject is that folder's auth id"
        )
        XCTAssertNil(
            CLIUsageFetcher.cursorSessionToken(
                keychainToken: first,
                directoryToken: nil,
                defaultFileToken: second,
                authId: "auth0|someone-else"
            ),
            "a file-store token is not claimed by a folder signed in as a different person"
        )
        XCTAssertNil(
            CLIUsageFetcher.cursorSessionToken(
                keychainToken: first,
                directoryToken: nil,
                defaultFileToken: first,
                authId: "auth0|first"
            ),
            "the keychain login is not also a second subscription"
        )
        XCTAssertEqual(
            CLIUsageFetcher.cursorSessionToken(
                keychainToken: first,
                directoryToken: second,
                defaultFileToken: first,
                authId: "auth0|second"
            ),
            second,
            "a token kept inside the folder wins over the shared file store"
        )
        XCTAssertNil(
            CLIUsageFetcher.cursorSessionToken(
                keychainToken: first,
                directoryToken: first,
                defaultFileToken: second,
                authId: "auth0|second"
            ),
            "a folder that stored the keychain login is not offered the other file-store token"
        )
    }

    func testExtraCursorSignInsAreConfigDirsOtherThanTheDefault() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("unotch-home-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: home) }
        let files = [
            ".cursor/cli-config.json",
            ".cursor-agent2/cli-config.json",
            ".config/cursor-work/cli-config.json",
            "notes/cli-config.json",
            "Documents/cursor/cli-config.json"
        ]
        for file in files {
            let url = home.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: url)
        }

        XCTAssertEqual(
            CLIUsageFetcher.configDirectories(for: .cursor, home: home),
            [".cursor-agent2", "notes", ".config/cursor-work"].map { home.appendingPathComponent($0).path }
        )
    }

    func testGrokBotParserReadsItsOwnAllowance() throws {
        let sand = Data(#"{"usagePercent":8.0,"hasNonZeroIncludedLimit":true,"nextResetTimestampUtc":"2026-09-18T19:21:59.215Z"}"#.utf8)
        let snapshot = try UsageCLIParser.grokBot(sand)
        XCTAssertEqual(snapshot.source, .grokBot)
        XCTAssertEqual(snapshot.state, .loaded)
        XCTAssertEqual(snapshot.limits.map(\.label), ["Grok Bot"])
        XCTAssertEqual(snapshot.limits[0].remainingFraction, 0.92, accuracy: 0.000_001)
        XCTAssertTrue(snapshot.limits[0].contributesToSummary, "alone in its snapshot, it drives its own ring")
        XCTAssertNotNil(snapshot.limits[0].resetAt)
        XCTAssertEqual(snapshot.remainingPercent, 92)
    }

    func testGrokBotParserReportsAPlanWithoutItAsUnavailable() throws {
        let pooled = Data(#"{"usagePercent":8.0,"hasNonZeroIncludedLimit":true,"usesPooledEnterpriseAllowance":true}"#.utf8)
        XCTAssertEqual(try UsageCLIParser.grokBot(pooled).state, .unavailable("Not included in this Cursor plan"))
        let none = Data(#"{"usagePercent":0,"hasNonZeroIncludedLimit":false}"#.utf8)
        XCTAssertEqual(try UsageCLIParser.grokBot(none).state, .unavailable("Not included in this Cursor plan"))
        XCTAssertThrowsError(try UsageCLIParser.grokBot(Data("not json".utf8)), "garbage is a failed read, not proof of anything")
    }

    func testProviderHoverZonesMapFromTopToBottom() {
        let providers: [Provider] = [.claude, .codex, .cursor]
        XCTAssertEqual(ProviderHoverGeometry.provider(distanceFromTop: 20, railHeight: 210, providers: providers), .claude)
        XCTAssertEqual(ProviderHoverGeometry.provider(distanceFromTop: 105, railHeight: 210, providers: providers), .codex)
        XCTAssertEqual(ProviderHoverGeometry.provider(distanceFromTop: 200, railHeight: 210, providers: providers), .cursor)
    }

    func testRailFooterIsReservedForSettingsGear() {
        let providers: [Provider] = [.claude, .codex, .cursor]
        let rail = HUDMetrics.railHeight(providerCount: 3)
        let footer = HUDMetrics.railFooterHeight
        XCTAssertEqual(ProviderHoverGeometry.provider(distanceFromTop: rail - footer - 1, railHeight: rail, footerHeight: footer, providers: providers), .cursor)
        XCTAssertNil(ProviderHoverGeometry.provider(distanceFromTop: rail - footer + 1, railHeight: rail, footerHeight: footer, providers: providers))
        XCTAssertNil(ProviderHoverGeometry.provider(distanceFromTop: rail - 5, railHeight: rail, footerHeight: footer, providers: providers))
    }

    func testCalloutPointerAimsAtTheSelectedRing() {
        XCTAssertEqual(HUDMetrics.ringCenterY(index: 0), 32)
        XCTAssertEqual(HUDMetrics.ringCenterY(index: 1), 98)
        XCTAssertEqual(HUDMetrics.ringCenterY(index: 2), 164)
        XCTAssertEqual(HUDMetrics.ringCenterY(index: 3), 230)
        XCTAssertEqual(HUDMetrics.gearCenterY(providerCount: 4), 297)
        XCTAssertEqual(HUDMetrics.gearCenterY(providerCount: 3), 231)

        let panel4 = HUDMetrics.expandedSize(providerCount: 4).height
        // The top ring: callout at the top, pointer level with the title row.
        var placed = HUDMetrics.calloutPlacement(anchorY: 32, calloutHeight: 260, panelHeight: panel4)
        XCTAssertEqual(placed.offset, 0)
        XCTAssertEqual(placed.pointerY, 32)
        // A lower ring: the callout drops so its title row is level with the ring.
        placed = HUDMetrics.calloutPlacement(anchorY: 164, calloutHeight: 212, panelHeight: panel4)
        XCTAssertEqual(placed.offset, 106, "318 - 212 holds it inside the panel")
        XCTAssertEqual(placed.offset + placed.pointerY, 164, "the pointer still lands on the ring")
        // The bottom ring with a short callout: held inside the panel, pointer follows the ring.
        placed = HUDMetrics.calloutPlacement(anchorY: 230, calloutHeight: 132, panelHeight: panel4)
        XCTAssertEqual(placed.offset, 186)
        XCTAssertEqual(placed.offset + placed.pointerY, 230)
        // The gear: the pointer stops short of the corner rather than leaving the edge.
        placed = HUDMetrics.calloutPlacement(anchorY: 297, calloutHeight: 188, panelHeight: panel4)
        XCTAssertEqual(placed.offset, 130)
        XCTAssertEqual(placed.pointerY, 188 - Brand.Radius.callout - HUDMetrics.calloutPointerHalfHeight)
        // A one-ring rail: the callout is taller than the rail and simply stays at the top.
        placed = HUDMetrics.calloutPlacement(anchorY: 32, calloutHeight: 132, panelHeight: HUDMetrics.expandedSize(providerCount: 1).height)
        XCTAssertEqual(placed.offset, 0)
        XCTAssertEqual(placed.pointerY, 32)
    }

    /// Hovering the gear opens settings. The callout has to cover the gear and the
    /// whole footer, or the pointer would have to climb the rail — and crossing a
    /// ring would close settings before you arrived.
    func testSettingsCalloutCoversTheGearSoYouCanReachIt() {
        for count in 1...4 {
            let rail = HUDMetrics.railHeight(providerCount: count)
            let panel = HUDMetrics.expandedSize(providerCount: count).height
            let gear = HUDMetrics.gearCenterY(providerCount: count)
            let footerTop = rail - HUDMetrics.railFooterHeight
            let placed = HUDMetrics.calloutPlacement(
                anchorY: gear,
                calloutHeight: HUDMetrics.settingsCalloutHeight,
                panelHeight: panel
            )
            let top = placed.offset
            let bottom = placed.offset + HUDMetrics.settingsCalloutHeight
            let pointer = top + placed.pointerY
            XCTAssertLessThanOrEqual(top, footerTop, "\(count) rings: callout must reach the footer")
            XCTAssertGreaterThanOrEqual(bottom, gear, "\(count) rings: callout must cover the gear")
            XCTAssertGreaterThanOrEqual(bottom, rail, "\(count) rings: callout must meet the rail's bottom so the gap to the gear is inside it")
            XCTAssertEqual(pointer, gear, accuracy: Brand.Radius.callout + HUDMetrics.calloutPointerHalfHeight, "\(count) rings: pointer aims at the gear, or as close as the corner allows")
        }
    }

    func testHoveredRingTurnsRedUnderTenPercent() {
        XCTAssertFalse(HUDMetrics.isLowRemaining(nil))
        XCTAssertFalse(HUDMetrics.isLowRemaining(1))
        XCTAssertTrue(HUDMetrics.isLowRemaining(0.10), "10% itself is low")
        XCTAssertTrue(HUDMetrics.isLowRemaining(0.095), "9.5% rounds to 10% on the ring")
        XCTAssertTrue(HUDMetrics.isLowRemaining(0.094))
        XCTAssertFalse(HUDMetrics.isLowRemaining(0.105), "10.5% rounds to 11%")
        XCTAssertTrue(HUDMetrics.isLowRemaining(0))
        XCTAssertEqual(HUDMetrics.ringAccent(remaining: 0.08, selected: false), Brand.alert, "a low ring is red even before it is hovered")
        XCTAssertEqual(HUDMetrics.ringAccent(remaining: 0.08, selected: true), Brand.alert)
        XCTAssertEqual(HUDMetrics.ringAccent(remaining: 0.40, selected: true), Brand.mint)
        XCTAssertEqual(HUDMetrics.ringAccent(remaining: 0.40, selected: false), Brand.paper.opacity(0.58))
        XCTAssertEqual(HUDMetrics.ringFill(remaining: 0), 1, "0% still draws a full red ring")
        XCTAssertEqual(HUDMetrics.ringFill(remaining: 0.08), 1)
        XCTAssertEqual(HUDMetrics.ringFill(remaining: 0.40), 0.40)
    }

    func testOpenSettingsIsIdempotent() {
        let state = NotchState(monitor: UsageMonitor())
        XCTAssertFalse(state.isSettingsOpen)
        state.openSettings()
        XCTAssertTrue(state.isSettingsOpen)
        state.openSettings()
        XCTAssertTrue(state.isSettingsOpen)
    }

    func testFourRingsFitWhenGrokBotJoins() {
        XCTAssertEqual(HUDMetrics.railHeight(providerCount: 4), 318)
        XCTAssertEqual(HUDMetrics.expandedSize(providerCount: 4).height, 318)
        let providers: [Provider] = [.claude, .codex, .cursor, .grokBot]
        let rail = HUDMetrics.railHeight(providerCount: 4)
        let footer = HUDMetrics.railFooterHeight
        XCTAssertEqual(ProviderHoverGeometry.provider(distanceFromTop: rail - footer - 1, railHeight: rail, footerHeight: footer, providers: providers), .grokBot)
    }

    func testRailShrinksToTheInstalledProviders() {
        XCTAssertEqual(HUDMetrics.railHeight(providerCount: 3), 252)
        XCTAssertEqual(HUDMetrics.railHeight(providerCount: 2), 186)
        XCTAssertEqual(HUDMetrics.railHeight(providerCount: 1), 120)
        // The panel never drops below the tallest usage callout, which must still fit.
        XCTAssertEqual(HUDMetrics.expandedSize(providerCount: 3).height, HUDMetrics.usageCalloutMaxHeight)
        XCTAssertEqual(HUDMetrics.expandedSize(providerCount: 2).height, HUDMetrics.usageCalloutMaxHeight)
        XCTAssertEqual(HUDMetrics.expandedSize(providerCount: 1).height, HUDMetrics.usageCalloutMaxHeight)
    }

    func testSubscriptionStripAddsOneRowToTheCallout() {
        XCTAssertEqual(HUDMetrics.usageCalloutHeight(forLimitCount: 3), HUDMetrics.usageCalloutTripleHeight)
        XCTAssertEqual(HUDMetrics.usageCalloutHeight(forLimitCount: 3, subscriptionCount: 1), HUDMetrics.usageCalloutTripleHeight)
        // The strip is one row whether two subscriptions share it or five.
        XCTAssertEqual(HUDMetrics.usageCalloutHeight(forLimitCount: 3, subscriptionCount: 2), 260)
        XCTAssertEqual(HUDMetrics.usageCalloutHeight(forLimitCount: 3, subscriptionCount: 5), 260)
        XCTAssertEqual(HUDMetrics.usageCalloutHeight(forLimitCount: 1, subscriptionCount: 5), 180)
        XCTAssertEqual(HUDMetrics.usageCalloutMaxHeight, 260)
        XCTAssertGreaterThan(HUDMetrics.usageCalloutMaxHeight, HUDMetrics.railHeight(providerCount: 3))
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

    func testNothingInstalledKeepsEveryCLIProviderVisible() {
        let monitor = UsageMonitor(fetcher: StubFetcher(installed: []))
        monitor.detectInstalledSources()
        XCTAssertEqual(monitor.sources, MonitorSource.defaults)
        XCTAssertEqual(monitor.providers, [.claude, .codex, .cursor], "Grok Bot has no CLI to point at")
    }

    func testGrokBotEarnsItsRingWithARead() async {
        let grok = UsageSnapshot(
            source: .grokBot,
            limits: [UsageLimit(label: "Grok Bot", remainingFraction: 0.92)],
            updatedAt: Date(),
            state: .loaded
        )
        let monitor = UsageMonitor(fetcher: StubFetcher(
            installed: [.cursor, .grokBot],
            snapshots: [.cursor: StubFetcher.loaded(.cursor, remaining: 0.95), .grokBot: grok]
        ))
        monitor.detectInstalledSources()
        XCTAssertEqual(monitor.providers, [.cursor], "no ring until the plan is known to include it")

        monitor.refreshAll()
        await settle { monitor.providers.count == 2 }
        XCTAssertEqual(monitor.providers, [.cursor, .grokBot])
        XCTAssertEqual(try XCTUnwrap(monitor.remainingFraction(for: .grokBot)), 0.92, accuracy: 0.000_001)
    }

    func testGrokBotStaysOffTheRailWhenThePlanLacksIt() async {
        let monitor = UsageMonitor(fetcher: StubFetcher(
            installed: [.cursor, .grokBot],
            snapshots: [
                .cursor: StubFetcher.loaded(.cursor, remaining: 0.95),
                .grokBot: .unavailable(source: .grokBot, message: "Not included in this Cursor plan")
            ]
        ))
        monitor.refreshAll()
        await settle { monitor.snapshot(for: .grokBot).statusMessage != nil }
        XCTAssertEqual(monitor.providers, [.cursor])
    }

    func testEachCursorSignInBringsItsOwnGrokBot() async {
        let work = MonitorSource(provider: .cursor, configDirectory: "/Users/someone/.cursor-work")
        let grokWork = MonitorSource(provider: .grokBot, configDirectory: work.configDirectory)
        let monitor = UsageMonitor(fetcher: StubFetcher(
            installed: [.cursor, work, .grokBot, grokWork],
            snapshots: [
                .cursor: StubFetcher.loaded(.cursor, remaining: 0.99),
                work: StubFetcher.loaded(work, remaining: 1),
                .grokBot: StubFetcher.loaded(.grokBot, remaining: 0.87),
                grokWork: StubFetcher.loaded(grokWork, remaining: 1)
            ]
        ))
        monitor.refreshAll()
        await settle { monitor.subscriptions(for: .grokBot).count == 2 }
        XCTAssertEqual(monitor.providers, [.cursor, .grokBot], "still one Grok Bot ring")
        XCTAssertEqual(monitor.subscriptions(for: .grokBot), [.grokBot, grokWork])
        XCTAssertEqual(grokWork.accountLabel, "work")
        XCTAssertEqual(try XCTUnwrap(monitor.remainingFraction(for: .grokBot)), 0.87, accuracy: 0.000_001)

        monitor.select(subscription: grokWork)
        XCTAssertEqual(try XCTUnwrap(monitor.remainingFraction(for: .grokBot)), 1, accuracy: 0.000_001)
    }

    func testLowUsageTurnsTheCueRedUntilTheHUDIsOpened() async {
        let monitor = UsageMonitor(fetcher: StubFetcher(
            installed: [.codex],
            snapshots: [.codex: StubFetcher.loaded(.codex, remaining: 0.08)]
        ))
        XCTAssertFalse(monitor.hasUnseenLowUsage)
        monitor.refreshAll()
        await settle { monitor.hasUnseenLowUsage }
        XCTAssertTrue(monitor.hasUnseenLowUsage)

        monitor.isLooking = true
        XCTAssertFalse(monitor.hasUnseenLowUsage, "opening the HUD is checking it")
        monitor.isLooking = false
        XCTAssertFalse(monitor.hasUnseenLowUsage, "it stays quiet after it has been seen")
    }

    func testSeenLowUsageDoesNotAlertAgainUntilItRecovers() async {
        let script = ScriptedFetcher(snapshot: StubFetcher.loaded(.codex, remaining: 0.08))
        let monitor = UsageMonitor(fetcher: script)
        monitor.refreshAll()
        await settle { monitor.hasUnseenLowUsage }
        monitor.isLooking = true
        monitor.isLooking = false
        XCTAssertFalse(monitor.hasUnseenLowUsage)

        script.snapshot = .failed(source: .codex, message: "CLI usage read failed")
        monitor.refreshAll()
        await settle { monitor.snapshot(for: .codex).state == .failed("CLI usage read failed") }
        XCTAssertFalse(monitor.hasUnseenLowUsage, "a failed reread does not turn the cue red again")

        script.snapshot = StubFetcher.loaded(.codex, remaining: 0.08)
        monitor.refreshAll()
        await settle { monitor.snapshot(for: .codex).state == .loaded }
        XCTAssertFalse(monitor.hasUnseenLowUsage, "still low, already seen")

        script.snapshot = StubFetcher.loaded(.codex, remaining: 0.40)
        monitor.refreshAll()
        await settle { monitor.snapshot(for: .codex).remainingFraction == 0.40 }
        script.snapshot = StubFetcher.loaded(.codex, remaining: 0.05)
        monitor.refreshAll()
        await settle { monitor.hasUnseenLowUsage }
        XCTAssertTrue(monitor.hasUnseenLowUsage, "dropping under 10% again is a new alert")
    }

    func testFavoriteIsWhatTheProviderOpensOn() async throws {
        let defaults = TestDefaults.fresh()
        defer { TestDefaults.clear() }
        let dev = MonitorSource(provider: .claude, configDirectory: "/Users/someone/.claude-dev")
        let fetcher = StubFetcher(
            installed: [.claude, dev],
            snapshots: [
                .claude: StubFetcher.loaded(.claude, remaining: 0.86),
                dev: StubFetcher.loaded(dev, remaining: 0.40)
            ]
        )
        let monitor = UsageMonitor(fetcher: fetcher, defaults: defaults)
        monitor.refreshAll()
        await settle { monitor.subscriptions(for: .claude).count == 2 }
        XCTAssertEqual(monitor.selectedSource(for: .claude), .claude, "without a favourite, the CLI's own sign-in opens")

        monitor.toggleFavorite(dev)
        XCTAssertTrue(monitor.isFavorite(dev))
        XCTAssertEqual(monitor.selectedSource(for: .claude), dev)
        XCTAssertEqual(try XCTUnwrap(monitor.remainingFraction(for: .claude)), 0.40, accuracy: 0.000_001, "the ring reports the favourite")

        monitor.select(subscription: .claude)
        XCTAssertEqual(monitor.selectedSource(for: .claude), .claude, "looking at another one wins while the HUD is open")
        monitor.clearLookedAt()
        XCTAssertEqual(monitor.selectedSource(for: .claude), dev, "and the favourite is back once it closes")

        let relaunched = UsageMonitor(fetcher: fetcher, defaults: defaults)
        XCTAssertTrue(relaunched.isFavorite(dev), "favourites survive a relaunch")

        monitor.toggleFavorite(dev)
        XCTAssertFalse(monitor.isFavorite(dev))
        XCTAssertEqual(monitor.selectedSource(for: .claude), .claude)
        XCTAssertNil(defaults.dictionary(forKey: "uNotch.favoriteSubscriptions")?["claude"])
    }

    func testSubscriptionIDRoundTrips() {
        let dev = MonitorSource(provider: .claude, configDirectory: "/Users/someone/.claude-dev")
        XCTAssertEqual(MonitorSource(id: dev.id), dev)
        XCTAssertEqual(MonitorSource(id: MonitorSource.codex.id), .codex)
        XCTAssertEqual(MonitorSource(id: "cursor:/Users/x/with:colon")?.configDirectory, "/Users/x/with:colon")
        XCTAssertNil(MonitorSource(id: "gemini"))
    }

    func testExtraClaudeSignInsAreFoundByTheirConfigFileNotTheirName() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("unotch-home-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: home) }
        let folders = [
            ".claude", ".claude-dev", ".claude-worktrees", ".cc-work", "claude_personal",
            ".config/anthropic-team", ".config/git", "Documents/claude-notes", "projects/app"
        ]
        for folder in folders {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(folder),
                withIntermediateDirectories: true
            )
        }
        // The default sign-in keeps `.claude.json` beside `~/.claude`, never inside it.
        let configs = [
            ".claude.json", ".claude-dev/.claude.json", ".cc-work/.claude.json",
            "claude_personal/.claude.json", ".config/anthropic-team/.claude.json",
            "Documents/claude-notes/.claude.json", "projects/app/.claude.json"
        ]
        for file in configs {
            try Data("{}".utf8).write(to: home.appendingPathComponent(file))
        }
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent(".work-link"),
            withDestinationURL: home.appendingPathComponent(".cc-work")
        )

        XCTAssertEqual(
            CLIUsageFetcher.configDirectories(for: .claude, home: home),
            [".cc-work", ".claude-dev", "claude_personal", ".config/anthropic-team"]
                .map { home.appendingPathComponent($0).path },
            "any name counts, a symlink is not a second sign-in, and nothing deeper or privacy-protected is touched"
        )
    }

    func testExtraCodexSignInsNeedMoreThanAnAuthFile() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("unotch-home-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: home) }
        let files = [
            ".codex/auth.json", ".codex/config.toml",               // the default, not an extra
            ".codex-work/auth.json", ".codex-work/config.toml",
            "openai_team/auth.json", "openai_team/installation_id",
            ".config/cx/auth.json", ".config/cx/version.json",
            ".other-tool/auth.json", ".other-tool/sessions/x", ".other-tool/history.jsonl", // generic names prove nothing
            ".composer/auth.json", ".composer/config.json",         // someone else's auth.json
            ".codex-empty/installation_id",                         // used, never signed in
            "Documents/codex/auth.json", "Documents/codex/config.toml"
        ]
        for file in files {
            let url = home.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: url)
        }

        XCTAssertEqual(
            CLIUsageFetcher.configDirectories(for: .codex, home: home),
            [".codex-work", "openai_team", ".config/cx"].map { home.appendingPathComponent($0).path }
        )
        XCTAssertEqual(CLIUsageFetcher.configDirectories(for: .cursor, home: home), [])
        XCTAssertEqual(MonitorSource(provider: .codex, configDirectory: home.appendingPathComponent(".codex-work").path).name, "Codex (work)")
    }

    func testCodexParserKeepsTheSubscriptionItWasReadFor() throws {
        let work = MonitorSource(provider: .codex, configDirectory: "/Users/someone/.codex-work")
        let data = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800000000},"secondary":null}}}"#.utf8)
        XCTAssertEqual(try UsageCLIParser.codex(data, source: work).source, work)
        XCTAssertEqual(try UsageCLIParser.codex(data).source, .codex)
    }

    func testExitStatusAnswersYesNoCLIs() throws {
        XCTAssertEqual(try ProcessRunner.exitStatus(executable: "/bin/sh", arguments: ["-c", "echo 'Not logged in' >&2; exit 1"], timeout: 2), 1)
        XCTAssertEqual(try ProcessRunner.exitStatus(executable: "/bin/sh", arguments: ["-c", "exit 0"], timeout: 2), 0)
    }

    func testSecondSubscriptionIsNamedAfterItsConfigDirectory() {
        let dev = MonitorSource(provider: .claude, configDirectory: "/Users/someone/.claude-dev")
        XCTAssertEqual(dev.accountLabel, "dev")
        XCTAssertEqual(dev.name, "Claude (dev)")
        XCTAssertNotEqual(dev, .claude)
        XCTAssertNotEqual(dev.id, MonitorSource.claude.id)
        XCTAssertNil(MonitorSource.claude.accountLabel)
        XCTAssertEqual(MonitorSource.claude.name, "Claude")

        let labels = [
            "/Users/someone/.cc-work": "cc-work",
            "/Users/someone/claude_personal": "personal",
            "/Users/someone/.config/anthropic-team": "anthropic-team",
            "/Users/someone/.Claude2": "2",
            "/Users/someone/.claude": "claude"
        ]
        for (folder, label) in labels {
            XCTAssertEqual(MonitorSource(provider: .claude, configDirectory: folder).accountLabel, label)
        }
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

    func testCollapsingClosesSettingsAndForgetsWhatWasLookedAt() async {
        let dev = MonitorSource(provider: .claude, configDirectory: "/Users/someone/.claude-dev")
        let monitor = UsageMonitor(fetcher: StubFetcher(
            installed: [.claude, dev],
            snapshots: [
                .claude: StubFetcher.loaded(.claude, remaining: 0.86),
                dev: StubFetcher.loaded(dev, remaining: 0.40)
            ]
        ))
        monitor.refreshAll()
        await settle { monitor.subscriptions(for: .claude).count == 2 }

        let state = NotchState(monitor: monitor)
        state.isExpanded = true
        state.toggleSettings()
        XCTAssertTrue(state.isSettingsOpen)
        monitor.select(subscription: dev)
        XCTAssertEqual(monitor.selectedSource(for: .claude), dev)

        state.isExpanded = false
        XCTAssertFalse(state.isSettingsOpen)
        XCTAssertEqual(state.presentation, .idle)
        XCTAssertEqual(monitor.selectedSource(for: .claude), .claude, "a look does not outlive the HUD")
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
