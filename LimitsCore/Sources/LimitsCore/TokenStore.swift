import Foundation
import Security

/// Keychain storage for OAuth tokens (access/refresh/expiry/account id), one item per
/// provider.
///
/// Distinct from `SharedKeychainStore` (T1.1's App-Group-sharing gate diagnostic,
/// which stores a throwaway counter for a different purpose) — this is the actual
/// product data, with its own service naming so the two items never collide, as
/// requested for this lot.
///
/// Same two Keychain choices as `SharedKeychainStore`, for the same reasons (see that
/// file's doc comment for the full rationale):
/// - **No `kSecAttrAccessGroup`** is ever set — the item lands in the first
///   `keychain-access-groups` entry by omission, without ever hardcoding
///   `$(AppIdentifierPrefix)` (a build-time-only Xcode variable).
/// - **`kSecAttrAccessibleAfterFirstUnlock`** on both `SecItemUpdate` and
///   `SecItemAdd`, so a background refresh task can still read tokens after the
///   device has been unlocked once, even if it's locked again when the task runs.
public struct TokenStore {
    public enum Provider: String {
        case claude
        case codex
    }

    private let service: String
    private let account = "oauth-tokens"

    public init(provider: Provider) {
        self.service = "com.caldf.limitsapp.tokenstore.\(provider.rawValue)"
    }

    public func save(_ tokens: StoredTokens) -> Result<Void, TokenStoreError> {
        let data: Data
        do {
            data = try TokenCoding.makeEncoder().encode(tokens)
        } catch {
            return .failure(.encodingFailed)
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
            return .failure(.keychain(status, SharedKeychainStore.describe(status)))
        }
        return .success(())
    }

    public func load() -> Result<StoredTokens, TokenStoreError> {
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
            return .failure(.keychain(status, SharedKeychainStore.describe(status)))
        }

        do {
            return .success(try TokenCoding.makeDecoder().decode(StoredTokens.self, from: data))
        } catch {
            return .failure(.decodingFailed)
        }
    }

    @discardableResult
    public func delete() -> Result<Void, TokenStoreError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            return .failure(.keychain(status, SharedKeychainStore.describe(status)))
        }
        return .success(())
    }
}

/// `accountID` is Codex-only (the claim extracted via `CodexIDToken`); `nil` for
/// Claude.
public struct StoredTokens: Codable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date?
    public let accountID: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date?, accountID: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountID = accountID
    }
}

public enum TokenStoreError: Error, LocalizedError, Equatable {
    case encodingFailed
    case decodingFailed
    /// Carries the raw `OSStatus` (for programmatic handling) alongside the same
    /// human-readable message `SharedKeychainStore.describe(_:)` produces — never the
    /// token data itself.
    case keychain(OSStatus, String)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Encodage des tokens impossible."
        case .decodingFailed:
            return "Tokens illisibles ou corrompus."
        case .keychain(_, let message):
            return message
        }
    }
}

private enum TokenCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
