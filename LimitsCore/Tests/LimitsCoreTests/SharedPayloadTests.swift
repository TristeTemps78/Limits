import XCTest
@testable import LimitsCore

final class SharedPayloadTests: XCTestCase {
    func testEncodeDecodeRoundTripPreservesValue() throws {
        let original = SharedPayload(updatedAt: Date(timeIntervalSince1970: 1_800_000_000), writeCount: 42)

        let data = try SharedPayloadCoding.makeEncoder().encode(original)
        let decoded = try SharedPayloadCoding.makeDecoder().decode(SharedPayload.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testEncodesTimestampAsISO8601String() throws {
        let payload = SharedPayload(updatedAt: Date(timeIntervalSince1970: 1_800_000_000), writeCount: 1)
        let data = try SharedPayloadCoding.makeEncoder().encode(payload)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let updatedAt = try XCTUnwrap(json["updatedAt"] as? String)

        // ISO 8601 dates always contain a "T" separator and end in "Z" (UTC) for
        // JSONEncoder's default .iso8601 strategy.
        XCTAssertTrue(updatedAt.contains("T"))
        XCTAssertTrue(updatedAt.hasSuffix("Z"))
    }

    func testAgeInSecondsComputesElapsedTime() {
        let payload = SharedPayload(updatedAt: Date(timeIntervalSinceNow: -30), writeCount: 1)
        let age = payload.ageInSeconds(now: Date())
        XCTAssertTrue((28...32).contains(age), "expected ~30s, got \(age)s")
    }

    func testAgeInSecondsClampsFutureTimestampsToZero() {
        let payload = SharedPayload(updatedAt: Date(timeIntervalSinceNow: 60), writeCount: 1)
        XCTAssertEqual(payload.ageInSeconds(now: Date()), 0)
    }
}
