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
        XCTAssertEqual(ProviderHoverGeometry.source(distanceFromTop: 20, railHeight: 220), .claude)
        XCTAssertEqual(ProviderHoverGeometry.source(distanceFromTop: 110, railHeight: 220), .codex)
        XCTAssertEqual(ProviderHoverGeometry.source(distanceFromTop: 200, railHeight: 220), .cursor)
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
