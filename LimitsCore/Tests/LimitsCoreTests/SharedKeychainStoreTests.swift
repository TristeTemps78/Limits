import XCTest
@testable import LimitsCore

/// Deliberately does **not** exercise real `SecItemAdd`/`SecItemCopyMatching` calls:
/// a headless macOS CI runner has no unlocked login keychain to write to reliably,
/// which would make these tests flaky through no fault of the store's logic. Instead
/// this tests the one part of `SharedKeychainStore` that's pure and CI-safe: the
/// OSStatus → message mapping used to turn a Keychain failure into something
/// Tristan can read on the diagnostic screen. The real read/write path can only be
/// proven on-device (see T1.1 report).
final class SharedKeychainStoreTests: XCTestCase {
    func testDescribeMapsKnownStatusesToNonEmptyReadableMessages() {
        let knownStatuses: [OSStatus] = [
            errSecItemNotFound,
            errSecMissingEntitlement,
            errSecNotAvailable,
            errSecInteractionNotAllowed,
            errSecDuplicateItem
        ]

        for status in knownStatuses {
            let message = SharedKeychainStore.describe(status)
            XCTAssertFalse(message.isEmpty, "status \(status) produced an empty message")
        }
    }

    func testDescribeNeverCrashesOnAnUnmappedStatus() {
        let message = SharedKeychainStore.describe(-99999)
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(message.contains("-99999"))
    }

    func testMissingEntitlementMessageNamesTheLikelyCause() {
        let message = SharedKeychainStore.describe(errSecMissingEntitlement)
        XCTAssertTrue(message.lowercased().contains("entitlement"))
    }
}
