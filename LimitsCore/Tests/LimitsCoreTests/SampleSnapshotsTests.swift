import XCTest
@testable import LimitsCore

/// Cross-checks `SampleSnapshots` against the exact fixture-derived numbers already
/// verified in `ClaudeUsageClientTests`/`CodexUsageClientTests` (T2.1) — so this file's
/// preview/test fixtures can never silently drift from the real captures they claim to
/// represent.
final class SampleSnapshotsTests: XCTestCase {
    func testClaudeMatchesTheRealFixtureNumbers() throws {
        let windows = SampleSnapshots.claude.windows
        XCTAssertEqual(windows.count, 2)

        let session = try XCTUnwrap(windows.first { $0.windowKind == .session })
        XCTAssertEqual(session.percent, 0)
        XCTAssertEqual(session.severity, "normal")
        XCTAssertNil(session.resetsAt, "session is inactive — resets_at must be nil")
        XCTAssertEqual(session.isActive, false)

        let weekly = try XCTUnwrap(windows.first { $0.windowKind == .weekly })
        XCTAssertEqual(weekly.percent, 8)
        XCTAssertEqual(weekly.severity, "normal")
        XCTAssertEqual(weekly.isActive, true)
        XCTAssertNotNil(weekly.resetsAt)

        let extraUsage = try XCTUnwrap(SampleSnapshots.claude.extraUsage)
        XCTAssertEqual(extraUsage.monthlyLimit, 16000)
        XCTAssertEqual(extraUsage.usedCredits, 15558)
        XCTAssertEqual(extraUsage.spendPercent, 97)
        XCTAssertEqual(extraUsage.spendSeverity, "critical")
    }

    func testCodexMatchesTheRealFixtureNumbers() {
        let windows = SampleSnapshots.codex.windows
        XCTAssertEqual(windows.count, 1, "secondary_window was null in the real capture")

        let window = windows[0]
        XCTAssertEqual(window.windowKind, .weekly, "604800s primary_window is weekly, never treated as session")
        XCTAssertEqual(window.percent, 9)
        XCTAssertEqual(window.windowSeconds, 604_800)
    }

    func testAllResetInstantsAreInTheFutureRelativeToReferenceNow() {
        // Guards the whole premise these samples exist for: previews demonstrating a
        // live countdown must not accidentally show `.awaitingRefresh` instead.
        for window in SampleSnapshots.claude.windows + SampleSnapshots.codex.windows {
            if let resetsAt = window.resetsAt {
                XCTAssertGreaterThan(resetsAt, SampleSnapshots.referenceNow)
            }
        }
    }

    func testNotConnectedSampleBuildsTheNotConnectedContentState() {
        let state = WidgetContentStateBuilder.build(result: .success(SampleSnapshots.notConnected), now: SampleSnapshots.referenceNow)
        XCTAssertEqual(state, .notConnected)
    }

    func testPastResetSampleBuildsAnAwaitingRefreshWindow() {
        guard let window = SampleSnapshots.pastReset.claude?.windows.first else {
            return XCTFail("expected a Claude window")
        }
        let state = WindowPresentation.displayState(for: window, now: SampleSnapshots.referenceNow)
        guard case .awaitingRefresh = state else {
            return XCTFail("expected .awaitingRefresh, got \(state)")
        }
    }
}
