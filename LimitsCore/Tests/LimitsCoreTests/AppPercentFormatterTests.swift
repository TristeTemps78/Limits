import XCTest
@testable import LimitsCore

final class AppPercentFormatterTests: XCTestCase {
    func testLabelRoundsToNearestWholePercent() {
        XCTAssertEqual(AppPercentFormatter.label(percent: 41.6), "42 %")
        XCTAssertEqual(AppPercentFormatter.label(percent: 41.4), "41 %")
        XCTAssertEqual(AppPercentFormatter.label(percent: 0), "0 %")
        XCTAssertEqual(AppPercentFormatter.label(percent: 100), "100 %")
    }

    func testLabelClampsOutOfRangeValues() {
        XCTAssertEqual(AppPercentFormatter.label(percent: 104), "100 %")
        XCTAssertEqual(AppPercentFormatter.label(percent: -3), "0 %")
    }

    func testFractionMatchesLabelClamping() {
        XCTAssertEqual(AppPercentFormatter.fraction(percent: 50), 0.5)
        XCTAssertEqual(AppPercentFormatter.fraction(percent: 150), 1.0)
        XCTAssertEqual(AppPercentFormatter.fraction(percent: -10), 0.0)
    }
}
