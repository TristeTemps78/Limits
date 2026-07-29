import Foundation
import Security

/// Channel 3: a shared Keychain generic-password item.
///
/// Two deliberate choices, both required for this to actually work as a *shared*
/// item between the App and the Widgets extension:
///
/// 1. **No `kSecAttrAccessGroup` is ever set.** `$(AppIdentifierPrefix)` (the team
///    prefix that precedes the group name in `keychain-access-groups`) only exists as
///    an Xcode build variable — there is no supported runtime API to read "my own"
///    prefix reliably before you've resolved it via one throwaway Keychain write, and
///    hardcoding a prefix would break the moment Sideloadly re-signs with a different
///    free Apple ID. Per Apple's documented behavior, when `kSecAttrAccessGroup` is
///    omitted, an item is written to the **first** access group listed in the calling
///    process's `keychain-access-groups` entitlement. Both `App/Limits.entitlements`
///    and `Widgets/LimitsWidgets.entitlements` list the same single group
///    (`$(AppIdentifierPrefix)com.caldf.limitsapp`) in that position, so omitting the
///    attribute makes App and Widgets land on the same item by construction — without
///    ever encoding the prefix in source.
/// 2. **`kSecAttrAccessibleAfterFirstUnlock`**, not the default
///    (`WhenUnlocked`/`AfterFirstUnlockThisDeviceOnly` variants some samples use).
///    WidgetKit can refresh a lock-screen widget's timeline while the device is
///    locked; an item stored `WhenUnlocked` would then read back
///    `errSecInteractionNotAllowed` and get misdiagnosed as "Keychain broken" when the
///    real cause is just the accessibility class.
public struct SharedKeychainStore {
    private let service = "com.caldf.limitsapp.shared"
    private let account = "shared-payload"

    public init() {}

    public func write(_ payload: SharedPayload) -> DiagnosticResult<Void> {
        let data: Data
        do {
            data = try SharedPayloadCoding.makeEncoder().encode(payload)
        } catch {
            return .failure("Encodage impossible : \(error.localizedDescription)")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        var status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            return .failure(Self.describe(status))
        }
        return .ok(())
    }

    public func read() -> DiagnosticResult<SharedPayload> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return .failure(Self.describe(status))
        }

        do {
            let payload = try SharedPayloadCoding.makeDecoder().decode(SharedPayload.self, from: data)
            return .ok(payload)
        } catch {
            return .failure("JSON illisible/corrompu : \(error.localizedDescription)")
        }
    }

    /// Pure OSStatus → human-readable message mapping, kept separate from the actual
    /// `SecItem*` calls so it can be unit-tested on the CI runner without touching a
    /// real keychain (headless macOS runners make live Keychain I/O unreliable to
    /// assert on in CI).
    public static func describe(_ status: OSStatus) -> String {
        switch status {
        case errSecItemNotFound:
            return "Item Keychain absent (errSecItemNotFound) — jamais écrit"
        case errSecMissingEntitlement:
            return "Entitlement Keychain manquant (errSecMissingEntitlement) — access group perdu à la re-signature"
        case errSecNotAvailable:
            return "Keychain indisponible (errSecNotAvailable)"
        case errSecInteractionNotAllowed:
            return "Accès refusé avant déverrouillage (errSecInteractionNotAllowed)"
        case errSecDuplicateItem:
            return "Item en double (errSecDuplicateItem)"
        default:
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Erreur Keychain OSStatus \(status) : \(message)"
            }
            return "Erreur Keychain OSStatus \(status)"
        }
    }
}
