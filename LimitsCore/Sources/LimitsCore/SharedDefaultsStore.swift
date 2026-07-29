import Foundation

/// Channel 1: `UserDefaults(suiteName:)` on the App Group.
///
/// Unlike `SharedFileStore`'s injected container URL, this initializer is **not a
/// reliable nil-signal** for a missing App Group entitlement. On iOS,
/// `UserDefaults(suiteName:)` practically never returns `nil` even without the
/// entitlement — it silently falls back to a defaults domain scoped to the calling
/// process. Concretely: if the App Group is broken, the app and the widget each get
/// their own isolated domain, and `write`/`read` both "succeed" independently on each
/// side — the `.failure("UserDefaults(suiteName:) nil…")` branch below essentially
/// never fires as the signal for a broken App Group; it only covers the (rarer)
/// case where the system refuses to hand back any suite at all.
///
/// What actually proves sharing on this channel is **comparing the `writeCount` the
/// app just wrote against what the widget reads back**: if they match, both
/// processes are reading the same domain; if the widget's counter lags behind or
/// never advances past what it wrote itself, they're each talking to their own
/// isolated domain despite both reporting success.
public struct SharedDefaultsStore {
    private static let key = "com.caldf.limitsapp.sharedPayload"

    private let defaults: UserDefaults?

    /// Production entry point: resolves `UserDefaults(suiteName:)` for the given App
    /// Group identifier. Kept optional for API symmetry with the other stores, but see
    /// the type-level doc comment above — a non-`nil` result here is not by itself
    /// proof that the App Group is intact.
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
