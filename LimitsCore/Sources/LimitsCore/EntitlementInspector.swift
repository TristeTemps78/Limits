import Foundation
import Security

/// Best-effort read of this process's own code-signing entitlements at runtime, via
/// the public `SecTask` API (`Security/SecTask.h` — no private/undocumented symbols).
///
/// This is the most direct evidence available of what Sideloadly actually granted
/// after re-signing with a free Apple ID: read/write failures on the shared channels
/// can have several causes (corrupted file, wrong key, ...), but the entitlement
/// value itself says definitively whether the App Group survived re-signing.
///
/// Every call is guarded: a `nil` task handle, a missing entitlement, or an
/// unexpected value type all resolve to `nil` rather than crashing. If a future
/// change discovers `SecTask` isn't usable cleanly here (e.g. sandbox restrictions
/// specific to widget extensions), prefer returning `nil` over forcing it.
public enum EntitlementInspector {
    private static let applicationGroupsEntitlement = "com.apple.security.application-groups"

    /// The `com.apple.security.application-groups` array actually granted to this
    /// process, or `nil` if it can't be read (task handle unavailable, entitlement
    /// absent, or unexpected value shape).
    public static func grantedApplicationGroups() -> [String]? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        var error: Unmanaged<CFError>?
        guard let value = SecTaskCopyValueForEntitlement(
            task,
            applicationGroupsEntitlement as CFString,
            &error
        ) else {
            return nil
        }
        return value as? [String]
    }
}
