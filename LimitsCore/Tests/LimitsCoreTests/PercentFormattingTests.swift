import XCTest
@testable import LimitsCore

final class PercentFormattingTests: XCTestCase {
    func testWholeNumbers() {
        XCTAssertEqual((0.0).roundedPercentText, "0%")
        XCTAssertEqual((8.0).roundedPercentText, "8%")
        XCTAssertEqual((9.0).roundedPercentText, "9%")
        XCTAssertEqual((100.0).roundedPercentText, "100%")
    }

    func testRoundsToNearest() {
        XCTAssertEqual((8.4).roundedPercentText, "8%")
        XCTAssertEqual((8.6).roundedPercentText, "9%")
    }

    func testHalfRoundsAwayFromZero() {
        // Swift's default `.rounded()` rule — locked in so a future refactor can't
        // silently switch to banker's rounding and shift every displayed percent by
        // up to 1 on exact-.5 values.
        XCTAssertEqual((8.5).roundedPercentText, "9%")
    }

    func testRealFixtureValue() {
        // extra_usage.utilization from fixtures/claude-usage.json.
        XCTAssertEqual((97.2375).roundedPercentText, "97%")
    }
}
