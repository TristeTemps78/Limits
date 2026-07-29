import Foundation

/// A named channel result, in the fixed display order used by both the app and the
/// widget so the diagnostic reads the same everywhere.
public enum SharedChannel: String, CaseIterable {
    case userDefaults
    case file
    case keychain

    public var displayName: String {
        switch self {
        case .userDefaults: return "UserDefaults"
        case .file: return "Fichier App Group"
        case .keychain: return "Keychain"
        }
    }
}

/// Wires the three shared-data channels together for the App/Widgets targets. Thin
/// composition only — the actual testable logic lives in the individual stores
/// (`SharedDefaultsStore`, `SharedFileStore`, `SharedKeychainStore`), which accept
/// injected dependencies for unit testing. This facade always resolves the *real*
/// App Group container/suite, so it is exercised on-device, not in CI.
public struct SharedChannelsFacade {
    public let appGroupIdentifier: String

    private let defaultsStore: SharedDefaultsStore
    private let fileStore: SharedFileStore
    private let keychainStore: SharedKeychainStore

    public init(appGroupIdentifier: String = AppGroup.identifier) {
        self.appGroupIdentifier = appGroupIdentifier
        self.defaultsStore = SharedDefaultsStore(suiteName: appGroupIdentifier)
        self.fileStore = SharedFileStore(
            containerURL: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        )
        self.keychainStore = SharedKeychainStore()
    }

    @discardableResult
    public func writeAll(writeCount: Int, date: Date = Date()) -> [SharedChannel: DiagnosticResult<Void>] {
        let payload = SharedPayload(updatedAt: date, writeCount: writeCount)
        return [
            .userDefaults: defaultsStore.write(payload),
            .file: fileStore.write(payload),
            .keychain: keychainStore.write(payload)
        ]
    }

    public func readAll() -> [SharedChannel: DiagnosticResult<SharedPayload>] {
        [
            .userDefaults: defaultsStore.read(),
            .file: fileStore.read(),
            .keychain: keychainStore.read()
        ]
    }
}
