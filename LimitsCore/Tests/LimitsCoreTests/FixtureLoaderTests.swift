import XCTest
@testable import LimitsCore

/// Proves the fixture-loading plumbing works before any real decoder is built on top
/// of it (T2.1). Every fixture captured by `scripts/capture-fixtures.ps1` must load
/// and parse as valid JSON.
final class FixtureLoaderTests: XCTestCase {
    private let fixtureNames = [
        "claude-usage",
        "codex-usage",
        "codex-credits",
        "codex-profile"
    ]

    func testAllFixturesLoadAsValidJSON() throws {
        for name in fixtureNames {
            let data = try FixtureLoader.load(name)
            XCTAssertFalse(data.isEmpty, "\(name).json should not be empty")

            let json = try JSONSerialization.jsonObject(with: data)
            XCTAssertTrue(
                json is [String: Any] || json is [Any],
                "\(name).json should decode to a JSON object or array"
            )
        }
    }

    func testMissingFixtureThrows() {
        XCTAssertThrowsError(try FixtureLoader.load("does-not-exist")) { error in
            XCTAssertTrue(error is FixtureLoader.FixtureLoaderError)
        }
    }
}
