import XCTest
@testable import LimitsCore

final class WindowSelectorTests: XCTestCase {
    func testNoWindowsReturnsNil() {
        let snapshots = SharedUsageSnapshots(updatedAt: Date(), claude: nil, codex: nil)
        XCTAssertNil(WindowSelector.mostUrgent(in: snapshots))
    }

    func testRealFixtureValuesPickHighestPercentAmongEqualSeverity() {
        // Claude session 0%, Claude weekly 8%, Codex weekly 9% — all "normal"
        // severity (Codex has none, falls back to `.normal` at 9%). Highest percent
        // wins: Codex's 9% weekly window.
        let selection = WindowSelector.mostUrgent(in: SampleSnapshots.bothConnected)
        XCTAssertEqual(selection?.provider, .codex)
        XCTAssertEqual(selection?.window.percent, 9)
        XCTAssertEqual(selection?.window.windowKind, .weekly)
    }

    func testSeverityBeatsPercent() {
        let claude = UsageSnapshot(
            provider: .claude,
            fetchedAt: Date(),
            windows: [
                LimitWindow(windowKind: .session, percent: 5, severity: "critical"),
                LimitWindow(windowKind: .weekly, percent: 50, severity: "normal")
            ]
        )
        let snapshots = SharedUsageSnapshots(updatedAt: Date(), claude: claude, codex: nil)
        let selection = WindowSelector.mostUrgent(in: snapshots)
        XCTAssertEqual(selection?.window.percent, 5, "critical at 5% must outrank normal at 50%")
    }

    func testTieBreaksDeterministicallyByProviderThenWindowKind() {
        let claudeWindow = LimitWindow(windowKind: .weekly, percent: 10, severity: "normal")
        let codexWindow = LimitWindow(windowKind: .weekly, percent: 10, windowSeconds: 604_800)
        let claude = UsageSnapshot(provider: .claude, fetchedAt: Date(), windows: [claudeWindow])
        let codex = UsageSnapshot(provider: .codex, fetchedAt: Date(), windows: [codexWindow])
        let snapshots = SharedUsageSnapshots(updatedAt: Date(), claude: claude, codex: codex)

        let selection = WindowSelector.mostUrgent(in: snapshots)
        XCTAssertEqual(selection?.provider, .claude, "exact tie must always resolve to Claude, deterministically")
    }

    func testOnlyOneProviderConnected() {
        let selection = WindowSelector.mostUrgent(in: SampleSnapshots.claudeOnly)
        XCTAssertEqual(selection?.provider, .claude)
        XCTAssertEqual(selection?.window.windowKind, .weekly, "8% weekly must outrank 0% session within Claude alone")
    }

    // MARK: - ranked (accessoryRectangular's short list)

    func testRankedReturnsEveryWindowMostUrgentFirst() {
        let ranked = WindowSelector.ranked(in: SampleSnapshots.bothConnected)
        XCTAssertEqual(ranked.count, 3, "Claude session + Claude weekly + Codex weekly")
        XCTAssertEqual(ranked.map(\.window.percent), [9, 8, 0], "descending urgency: Codex 9%, Claude weekly 8%, Claude session 0%")
    }

    func testRankedOnEmptySnapshotsIsEmptyNotNil() {
        let snapshots = SharedUsageSnapshots(updatedAt: Date(), claude: nil, codex: nil)
        XCTAssertEqual(WindowSelector.ranked(in: snapshots), [])
    }

    func testRankedFirstAlwaysMatchesMostUrgent() {
        XCTAssertEqual(WindowSelector.ranked(in: SampleSnapshots.bothConnected).first, WindowSelector.mostUrgent(in: SampleSnapshots.bothConnected))
    }
}
