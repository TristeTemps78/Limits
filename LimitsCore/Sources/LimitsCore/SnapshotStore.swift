import Foundation

/// Failure reading/writing the shared snapshot. `unsupportedSchemaVersion` is
/// distinct from `corrupted` on purpose: a version mismatch means "a newer binary
/// wrote a format I don't understand yet" (show "mets à jour l'app"), which is a very
/// different situation from "the file is garbage" (show "erreur, réessaie").
public enum SnapshotStoreError: Error, Equatable, Sendable {
    case containerUnavailable
    case fileNotFound
    case unsupportedSchemaVersion(found: Int, expected: Int)
    case corrupted
    case encodingFailed
}

/// Reads/writes the shared `SharedUsageSnapshots` JSON file in the App Group
/// container.
///
/// The container URL is **injected**, exactly like T1.1's `SharedFileStore` — that's
/// what makes this testable on the CI runner (macOS, no App Group entitlement) with a
/// plain temp directory standing in for the real container. Production call sites
/// pass `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:
/// AppGroup.identifier)`, which is `nil` when the entitlement isn't granted.
public struct SnapshotStore {
    private let containerURL: URL?
    private let fileName: String

    public init(containerURL: URL?, fileName: String = "usage-snapshots.json") {
        self.containerURL = containerURL
        self.fileName = fileName
    }

    private var fileURL: URL? {
        containerURL?.appendingPathComponent(fileName)
    }

    public func write(_ snapshots: SharedUsageSnapshots) -> Result<Void, SnapshotStoreError> {
        guard let url = fileURL else { return .failure(.containerUnavailable) }
        do {
            let data = try Self.makeEncoder().encode(snapshots)
            try data.write(to: url, options: .atomic)
            return .success(())
        } catch {
            return .failure(.encodingFailed)
        }
    }

    public func read() -> Result<SharedUsageSnapshots, SnapshotStoreError> {
        guard let url = fileURL else { return .failure(.containerUnavailable) }
        guard FileManager.default.fileExists(atPath: url.path) else { return .failure(.fileNotFound) }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failure(.corrupted)
        }

        // Two-pass decode: check the schema version *before* attempting a full
        // decode of a shape we might not understand. This is the mechanism that lets
        // an old widget binary detect a format it can't read instead of silently
        // mis-decoding partial/wrong values.
        guard let probe = try? JSONDecoder().decode(SchemaVersionProbe.self, from: data) else {
            return .failure(.corrupted)
        }
        guard probe.schemaVersion == SharedUsageSnapshots.currentSchemaVersion else {
            return .failure(
                .unsupportedSchemaVersion(found: probe.schemaVersion, expected: SharedUsageSnapshots.currentSchemaVersion)
            )
        }

        do {
            let snapshots = try Self.makeDecoder().decode(SharedUsageSnapshots.self, from: data)
            return .success(snapshots)
        } catch {
            return .failure(.corrupted)
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private struct SchemaVersionProbe: Decodable {
        let schemaVersion: Int
    }
}
