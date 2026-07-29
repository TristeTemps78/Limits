import Foundation

/// Minimal payload written to every shared-data channel for the T1.1 dérisquage: just
/// enough to tell "did this channel survive re-signing" and "is the data fresh."
/// Real usage snapshots (`UsageSnapshot`, ...) land in T2.x — this type is scoped to
/// the diagnostic, not the product.
public struct SharedPayload: Codable, Equatable {
    public let updatedAt: Date
    public let writeCount: Int

    public init(updatedAt: Date, writeCount: Int) {
        self.updatedAt = updatedAt
        self.writeCount = writeCount
    }
}

extension SharedPayload {
    /// Age of this payload relative to `now`, in whole seconds. Negative values (clock
    /// skew) are clamped to 0 rather than displayed as a nonsensical "in the future."
    public func ageInSeconds(now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(updatedAt)))
    }
}

enum SharedPayloadCoding {
    /// ISO 8601 with fractional seconds, shared by every channel's encoder/decoder so
    /// a payload written by one channel's code path can always be read back by
    /// another's without a format mismatch.
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
