import XCTest
@testable import LimitsCore

final class FlexibleISO8601Tests: XCTestCase {
    /// The exact string captured in `fixtures/claude-usage.json` — 6 fractional
    /// digits, which `ISO8601DateFormatter` is known to be inconsistent about across
    /// OS versions. This must never regress to `nil` on-device.
    func testParsesTheExactFixtureStringWithSixFractionalDigits() throws {
        let date = try XCTUnwrap(FlexibleISO8601.parse("2026-08-04T17:59:59.981775+00:00"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 4)
        XCTAssertEqual(components.hour, 17)
        XCTAssertEqual(components.minute, 59)
        XCTAssertEqual(components.second, 59)

        // Millisecond precision must survive even if the 4th-6th fractional digits
        // are truncated along the way.
        let fractional = date.timeIntervalSince1970 - date.timeIntervalSince1970.rounded(.down)
        XCTAssertEqual(fractional, 0.981, accuracy: 0.001)
    }

    func testParsesThreeFractionalDigits() throws {
        let date = try XCTUnwrap(FlexibleISO8601.parse("2026-01-01T00:00:00.123+00:00"))
        XCTAssertEqual(date.timeIntervalSince1970, 1_767_225_600.123, accuracy: 0.001)
    }

    func testParsesNoFractionalDigits() throws {
        let date = try XCTUnwrap(FlexibleISO8601.parse("2026-01-01T00:00:00+00:00"))
        XCTAssertEqual(date.timeIntervalSince1970, 1_767_225_600, accuracy: 0.001)
    }

    func testReturnsNilOnGarbage() {
        XCTAssertNil(FlexibleISO8601.parse("not a date"))
        XCTAssertNil(FlexibleISO8601.parse(""))
    }
}
