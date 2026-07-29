import Foundation

/// Channel 1: `UserDefaults(suiteName:)` on the App Group.
public struct SharedDefaultsStore {
    private static let key = "com.caldf.limitsapp.sharedPayload"

    private let defaults: UserDefaults?

    /// Production entry point: resolves `UserDefaults(suiteName:)` for the given App
    /// Group identifier. `nil` when the suite can't be opened (entitlement missing).
    public init(suiteName: String) {
        self.defaults = UserDefaults(suiteName: suiteName)
    }

    /// Test entry point: inject a `UserDefaults` instance directly (e.g. a disposable
    /// suite created in a unit test) instead of resolving one by name.
    public init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    public func write(_ payload: SharedPayload) -> DiagnosticResult<Void> {
        guard let defaults else {
            return .failure("UserDefaults(suiteName:) nil — App Group non accordé")
        }
        do {
            let data = try SharedPayloadCoding.makeEncoder().encode(payload)
            defaults.set(data, forKey: Self.key)
            return .ok(())
        } catch {
            return .failure("Encodage impossible : \(error.localizedDescription)")
        }
    }

    public func read() -> DiagnosticResult<SharedPayload> {
        guard let defaults else {
            return .failure("UserDefaults(suiteName:) nil — App Group non accordé")
        }
        guard let data = defaults.data(forKey: Self.key) else {
            return .failure("Clé absente — jamais écrite")
        }
        do {
            let payload = try SharedPayloadCoding.makeDecoder().decode(SharedPayload.self, from: data)
            return .ok(payload)
        } catch {
            return .failure("JSON illisible/corrompu : \(error.localizedDescription)")
        }
    }
}
