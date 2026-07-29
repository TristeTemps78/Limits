import XCTest
@testable import LimitsCore

final class WindowPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNilResetsAtIsInactive() {
        let window = LimitWindow(windowKind: .session, percent: 0, resetsAt: nil)
        XCTAssertEqual(WindowPresentation.displayState(for: window, now: now), .inactive)
    }

    func testFutureResetsAtIsCounting() {
        let future = now.addingTimeInterval(3600)
        let window = LimitWindow(windowKind: .weekly, percent: 8, resetsAt: future)
        XCTAssertEqual(WindowPresentation.displayState(for: window, now: now), .counting(resetsAt: future))
    }

    func testPastResetsAtIsAwaitingRefreshNotANegativeCountdown() {
        let past = now.addingTimeInterval(-3600)
        let window = LimitWindow(windowKind: .weekly, percent: 8, resetsAt: past)
        XCTAssertEqual(WindowPresentation.displayState(for: window, now: now), .awaitingRefresh(resetsAt: past))
    }

    func testResetsAtExactlyNowIsAwaitingRefresh() {
        // The boundary: `resetsAt == now` must not be treated as "still counting"
        // (which would require `resetsAt > now`, strictly).
        let window = LimitWindow(windowKind: .weekly, percent: 8, resetsAt: now)
        XCTAssertEqual(WindowPresentation.displayState(for: window, now: now), .awaitingRefresh(resetsAt: now))
    }

    // MARK: - countdownRenderStyle (precise Text(timerInterval:) vs. relative "dans X j")

    func testJustUnderTheHorizonIsPrecise() {
        let resetsAt = now.addingTimeInterval(WindowPresentation.preciseCountdownHorizon - 1)
        XCTAssertEqual(WindowPresentation.countdownRenderStyle(resetsAt: resetsAt, now: now), .precise)
    }

    func testExactlyAtTheHorizonIsRelative() {
        let resetsAt = now.addingTimeInterval(WindowPresentation.preciseCountdownHorizon)
        XCTAssertEqual(WindowPresentation.countdownRenderStyle(resetsAt: resetsAt, now: now), .relative)
    }

    func testWellBeyondTheHorizonIsRelative() {
        let resetsAt = now.addingTimeInterval(6 * 24 * 60 * 60) // a weekly window's typical reset
        XCTAssertEqual(WindowPresentation.countdownRenderStyle(resetsAt: resetsAt, now: now), .relative)
    }

    func testAFewMinutesOutIsPrecise() {
        let resetsAt = now.addingTimeInterval(5 * 60)
        XCTAssertEqual(WindowPresentation.countdownRenderStyle(resetsAt: resetsAt, now: now), .precise)
    }

    func testHorizonIsExactlyTwentyFourHours() {
        // Locks the specific figure the brief asked for, independent of the boundary
        // tests above (which would still pass at a different threshold value).
        XCTAssertEqual(WindowPresentation.preciseCountdownHorizon, 24 * 60 * 60)
    }
}
