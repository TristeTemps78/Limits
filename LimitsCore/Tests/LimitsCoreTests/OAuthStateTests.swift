import XCTest
@testable import LimitsCore

final class OAuthStateTests: XCTestCase {
    func testGeneratedStateIsNonEmptyAndURLSafe() {
        let state = OAuthState.generate()
        XCTAssertFalse(state.isEmpty)
        XCTAssertFalse(state.contains("="))
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        for scalar in state.unicodeScalars {
            XCTAssertTrue(allowed.contains(scalar))
        }
    }

    func testTwoGeneratedStatesDiffer() {
        XCTAssertNotEqual(OAuthState.generate(), OAuthState.generate())
    }

    func testVerifyReturnsTrueForMatchingState() {
        let state = OAuthState.generate()
        XCTAssertTrue(OAuthState.verify(received: state, expected: state))
    }

    func testVerifyReturnsFalseForMismatchedState() {
        XCTAssertFalse(OAuthState.verify(received: "abc123", expected: "xyz789"))
    }

    func testVerifyReturnsFalseForDifferentLengthState() {
        XCTAssertFalse(OAuthState.verify(received: "short", expected: "a-lot-longer-value"))
    }

    func testVerifyReturnsFalseForEmptyVsNonEmpty() {
        XCTAssertFalse(OAuthState.verify(received: "", expected: "nonempty"))
    }

    func testVerifyReturnsTrueForBothEmpty() {
        XCTAssertTrue(OAuthState.verify(received: "", expected: ""))
    }
}
