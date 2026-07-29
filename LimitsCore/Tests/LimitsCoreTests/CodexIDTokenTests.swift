import XCTest
@testable import LimitsCore

final class CodexIDTokenTests: XCTestCase {
    /// Builds a syntactically valid but entirely synthetic JWT (fixed dummy header,
    /// caller-provided payload dictionary, dummy signature) — no real token, no
    /// network call, just base64url encoding exercised the same way a real id_token
    /// would be.
    private func makeJWT(payload: [String: Any]) throws -> String {
        let header = PKCE.base64URLEncode(Data(#"{"alg":"none","typ":"JWT"}"#.utf8))
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let payloadSegment = PKCE.base64URLEncode(payloadData)
        let signature = PKCE.base64URLEncode(Data("dummy-unsigned".utf8))
        return "\(header).\(payloadSegment).\(signature)"
    }

    func testExtractsAccountIDFromNamespacedClaim() throws {
        let jwt = try makeJWT(payload: [
            "https://api.openai.com/auth": ["chatgpt_account_id": "acct_test_dummy"],
            "sub": "user_test_dummy"
        ])

        switch CodexIDToken.accountID(fromIDToken: jwt) {
        case .success(let accountID):
            XCTAssertEqual(accountID, "acct_test_dummy")
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    func testPayloadSegmentIsUnpaddedBase64URL() throws {
        // The whole point of this pitfall: an unpadded base64url segment's length is
        // not always a multiple of 4, so a naive `Data(base64Encoded:)` call on it
        // (which requires padding) would return nil. Assert the segment we produce
        // actually exercises that (no trailing "=") and that decoding it still works.
        let jwt = try makeJWT(payload: ["https://api.openai.com/auth": ["chatgpt_account_id": "x"]])
        let payloadSegment = jwt.split(separator: ".")[1]
        XCTAssertFalse(payloadSegment.contains("="))

        let decoded = CodexIDToken.base64URLDecode(String(payloadSegment))
        XCTAssertNotNil(decoded, "unpadded base64url segment should still decode")
    }

    func testFailsWithClaimMissingWhenNamespaceAbsent() throws {
        let jwt = try makeJWT(payload: ["sub": "user_test_dummy"])
        XCTAssertEqual(CodexIDToken.accountID(fromIDToken: jwt), .failure(.claimMissing))
    }

    func testFailsWithClaimMissingWhenAccountIDKeyAbsentFromNamespace() throws {
        let jwt = try makeJWT(payload: ["https://api.openai.com/auth": ["some_other_key": "value"]])
        XCTAssertEqual(CodexIDToken.accountID(fromIDToken: jwt), .failure(.claimMissing))
    }

    func testFailsWithMalformedWhenNotThreeSegments() {
        XCTAssertEqual(CodexIDToken.accountID(fromIDToken: "only.two"), .failure(.malformed))
        XCTAssertEqual(CodexIDToken.accountID(fromIDToken: "no-dots-at-all"), .failure(.malformed))
    }

    func testFailsWithMalformedWhenPayloadSegmentIsNotValidBase64() {
        XCTAssertEqual(CodexIDToken.accountID(fromIDToken: "header.not!valid!base64url.sig"), .failure(.malformed))
    }

    func testFailsWithMalformedWhenPayloadSegmentIsNotValidJSON() {
        let notJSON = PKCE.base64URLEncode(Data("not a json object".utf8))
        XCTAssertEqual(CodexIDToken.accountID(fromIDToken: "header.\(notJSON).sig"), .failure(.malformed))
    }

    func testErrorDescriptionsNeverContainTheTokenItself() throws {
        // Defensive check for AGENTS.md rule 5/6: whatever the fixed error message
        // is, it must not somehow interpolate the input token.
        let jwt = try makeJWT(payload: [:])
        if case .failure(let error) = CodexIDToken.accountID(fromIDToken: jwt) {
            XCTAssertFalse((error.errorDescription ?? "").contains(jwt))
        }
    }
}
