import Foundation

/// Channel 2/3: a JSON file in the App Group container
/// (`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`).
///
/// The container URL is **injected**, never resolved internally with
/// `AppGroup.identifier` — that's what makes this store testable on the CI runner
/// (macOS, no App Group entitlement) with a plain temporary directory standing in for
/// the container. Production call sites (App/Widgets targets) pass the real
/// `containerURL(forSecurityApplicationGroupIdentifier:)` result, which is `nil` when
/// the entitlement isn't granted — the exact failure mode we're trying to catch after
/// Sideloadly re-signs the IPA.
public struct SharedFileStore {
    private let containerURL: URL?
    private let fileName: String

    public init(containerURL: URL?, fileName: String = "shared-payload.json") {
        self.containerURL = containerURL
        self.fileName = fileName
    }

    private var fileURL: URL? {
        containerURL?.appendingPathComponent(fileName)
    }

    public func write(_ payload: SharedPayload) -> DiagnosticResult<Void> {
        guard let url = fileURL else {
            return .failure("Conteneur App Group introuvable (containerURL nil — entitlement perdu ?)")
        }
        do {
            let data = try SharedPayloadCoding.makeEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
            return .ok(())
        } catch {
            return .failure("Écriture fichier impossible : \(error.localizedDescription)")
        }
    }

    public func read() -> DiagnosticResult<SharedPayload> {
        guard let url = fileURL else {
            return .failure("Conteneur App Group introuvable (containerURL nil — entitlement perdu ?)")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure("Fichier absent (\(url.lastPathComponent)) — jamais écrit ou supprimé")
        }
        do {
            let data = try Data(contentsOf: url)
            let payload = try SharedPayloadCoding.makeDecoder().decode(SharedPayload.self, from: data)
            return .ok(payload)
        } catch {
            return .failure("JSON illisible/corrompu : \(error.localizedDescription)")
        }
    }
}
