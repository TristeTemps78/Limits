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
}
