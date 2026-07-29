import XCTest
@testable import LimitsCore

final class AppFreshnessFormatterTests: XCTestCase {
    func testJustNowUnderOneMinute() {
        XCTAssertEqual(AppFreshnessFormatter.label(ageSeconds: 0), "à jour à l'instant")
        XCTAssertEqual(AppFreshnessFormatter.label(ageSeconds: 59), "à jour à l'instant")
    }

    func testMinutesBucket() {
        XCTAssertEqual(AppFreshnessFormatter.label(ageSeconds: 60), "à jour il y a 1 min")
        XCTAssertEqual(AppFreshnessFormatter.label(ageSeconds: 125), "à jour il y a 2 min")
        XCTAssertEqual(AppFreshnessFormatter.label(ageSeconds: 3599), "à jour il y a 59 min")
    }

    func testHoursBucket() {
        XCTAssertEqual(AppFreshnessFormatter.label(ageSeconds: 3600), "à jour il y a 1 h")
        XCTAssertEqual(AppFreshnessFormatter.label(ageSeconds: 86399), "à jour il y a 23 h")
    }

    func testDaysBucket() {
        XCTAssertEqual(AppFreshnessFormatter.label(ageSeconds: 86400), "à jour il y a 1 j")
        XCTAssertEqual(AppFreshnessFormatter.label(ageSeconds: 86400 * 5), "à jour il y a 5 j")
    }

    func testNegativeAgeClampsToJustNow() {
        // Clock skew guard: a negative age must never read as "in the future."
        XCTAssertEqual(AppFreshnessFormatter.label(ageSeconds: -30), "à jour à l'instant")
    }

    func testLabelFromDatesComputesAge() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let now = fetchedAt.addingTimeInterval(125)
        XCTAssertEqual(AppFreshnessFormatter.label(fetchedAt: fetchedAt, now: now), "à jour il y a 2 min")
    }

    func testBucketExposesStructuredValueNotJustText() {
        XCTAssertEqual(AppFreshnessFormatter.bucket(ageSeconds: 125), .minutes(2))
    }
}
