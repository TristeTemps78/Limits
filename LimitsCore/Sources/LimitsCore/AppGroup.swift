import Foundation

/// Single source of truth for the App Group and Keychain sharing identifiers.
///
/// PLAN.md §4: Sideloadly/AltStore remap bundle/App-Group identifiers when they
/// re-sign the IPA with a free Apple ID — no other file in this codebase should
/// hardcode or compare these strings. Both `App/Limits.entitlements` and
/// `Widgets/LimitsWidgets.entitlements` must declare the same values.
public enum AppGroup {
    /// Must match `com.apple.security.application-groups` in both entitlements files.
    /// Used for `UserDefaults(suiteName:)` and
    /// `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`.
    public static let identifier = "group.com.caldf.limitsapp"

    /// The App/Widgets suffix declared in `keychain-access-groups` in both
    /// entitlements files (full value on disk is `$(AppIdentifierPrefix)` + this
    /// suffix). Kept here for display/diagnostic purposes only — `$(AppIdentifierPrefix)`
    /// is a build-time Xcode variable with no runtime equivalent, so
    /// `SharedKeychainStore` never passes a `kSecAttrAccessGroup` built from this
    /// constant. See `SharedKeychainStore` for the reasoning.
    public static let keychainAccessGroupSuffix = "com.caldf.limitsapp"
}
