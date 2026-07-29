import XCTest
@testable import LimitsCore

final class WindowSeverityTests: XCTestCase {
    // MARK: - Claude: explicit severity string wins, never re-derived from percent

    func testKnownSeverityStringIsUsedAsIs() {
        let window = LimitWindow(windowKind: .weekly, percent: 8, severity: "normal")
        XCTAssertEqual(WindowSeverity.classify(window), .normal)
    }

    func testCriticalSeverityStringIsUsedEvenAtLowPercent() {
        // Mirrors the real fixture's `spend.severity: "critical"` at 97% — but the
        // point of this test is the *rule*: a "critical" string at any percent (even
        // one a percent-only classifier would call "normal") must never be downgraded.
        let window = LimitWindow(windowKind: .session, percent: 5, severity: "critical")
        XCTAssertEqual(WindowSeverity.classify(window), .critical)
    }

    func testUnrecognizedSeverityStringMapsToUnknownNotAPercentGuess() {
        // A future/unrecognized value must not be silently reinterpreted from
        // `percent` — that would contradict a value the source actually provided.
        let window = LimitWindow(windowKind: .weekly, percent: 99, severity: "spicy")
        XCTAssertEqual(WindowSeverity.classify(window), .unknown)
    }

    // MARK: - Codex (no severity field): percent-threshold fallback, 80/95 per PLAN.md §1

    func testNoSeverityFallsBackToPercentThresholds() {
        XCTAssertEqual(WindowSeverity.classify(LimitWindow(windowKind: .weekly, percent: 9)), .normal)
        XCTAssertEqual(WindowSeverity.classify(LimitWindow(windowKind: .weekly, percent: 79.9)), .normal)
        XCTAssertEqual(WindowSeverity.classify(LimitWindow(windowKind: .weekly, percent: 80)), .warning)
        XCTAssertEqual(WindowSeverity.classify(LimitWindow(windowKind: .weekly, percent: 94.9)), .warning)
        XCTAssertEqual(WindowSeverity.classify(LimitWindow(windowKind: .weekly, percent: 95)), .critical)
        XCTAssertEqual(WindowSeverity.classify(LimitWindow(windowKind: .weekly, percent: 100)), .critical)
    }

    // MARK: - Real fixture values (T2.1)

    func testRealFixtureValuesClassifyAsExpected() {
        // Claude session: 0%, "normal".
        XCTAssertEqual(
            WindowSeverity.classify(LimitWindow(windowKind: .session, percent: 0, severity: "normal")),
            .normal
        )
        // Claude weekly: 8%, "normal".
        XCTAssertEqual(
            WindowSeverity.classify(LimitWindow(windowKind: .weekly, percent: 8, severity: "normal")),
            .normal
        )
        // Codex weekly (primary_window, no severity field): 9% → normal by threshold.
        XCTAssertEqual(
            WindowSeverity.classify(LimitWindow(windowKind: .weekly, percent: 9, windowSeconds: 604_800)),
            .normal
        )
    }
}
