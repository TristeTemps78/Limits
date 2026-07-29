import XCTest
@testable import LimitsCore

/// `TokenStore` itself talks to the real Keychain, which (per the T1.1 precedent —
/// see `SharedKeychainStoreTests`) isn't reliably testable on a headless macOS CI
/// runner. What's tested here is everything around it that's pure: the `Codable`
/// shape actually persisted, and that error descriptions never leak token material.
final class TokenStoreTests: XCTestCase {
    func testStoredTokensRoundTripsThroughJSONWithISO8601Dates() throws {
        let original = StoredTokens(
            accessToken: "access-dummy",
            refreshToken: "refresh-dummy",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            accountID: "account-dummy"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StoredTokens.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testStoredTokensToleratesNilExpiryAndAccountID() throws {
        let original = StoredTokens(accessToken: "a", refreshToken: "r", expiresAt: nil, accountID: nil)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StoredTokens.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.expiresAt)
        XCTAssertNil(decoded.accountID)
    }

    func testKeychainErrorDescriptionNeverContainsTokenMaterial() {
        // The store's own describe() reuse (SharedKeychainStore.describe) is already
        // covered by T1.1's tests; this just locks in that TokenStoreError's message
        // surface (what a crash report or UI might display) is built only from the
        // OSStatus, never from any token/account data — there is no code path in
        // TokenStoreError that could interpolate a token, but this test documents and
        // guards that invariant against a careless future edit.
        let error = TokenStoreError.keychain(errSecItemNotFound, SharedKeychainStore.describe(errSecItemNotFound))
        XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        XCTAssertFalse((error.errorDescription ?? "").lowercased().contains("access-dummy"))
        XCTAssertFalse((error.errorDescription ?? "").lowercased().contains("refresh-dummy"))
    }

    func testEncodingAndDecodingFailureDescriptionsAreNonEmpty() {
        XCTAssertFalse((TokenStoreError.encodingFailed.errorDescription ?? "").isEmpty)
        XCTAssertFalse((TokenStoreError.decodingFailed.errorDescription ?? "").isEmpty)
    }
}
