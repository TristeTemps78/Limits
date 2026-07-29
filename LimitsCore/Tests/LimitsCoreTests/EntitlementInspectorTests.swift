import XCTest
@testable import LimitsCore

/// The `swift test` binary has no App Group entitlement at all, so
/// `grantedApplicationGroups()` is expected to return `nil` here — this test's job is
/// only to prove the call is safe (never crashes/traps) in an environment with no
/// entitlements to read, which is the same shape of failure as "Sideloadly stripped
/// the entitlement."
final class EntitlementInspectorTests: XCTestCase {
    func testGrantedApplicationGroupsDoesNotCrashWithoutEntitlements() {
        let result = EntitlementInspector.grantedApplicationGroups()
        // No assertion on the value itself (environment-dependent) — reaching this
        // line at all is the assertion.
        _ = result
    }
}
