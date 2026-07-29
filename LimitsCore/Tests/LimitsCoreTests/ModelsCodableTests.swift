import XCTest
@testable import LimitsCore

final class ModelsCodableTests: XCTestCase {
    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func testUsageSnapshotRoundTripsThroughJSON() throws {
        let original = UsageSnapshot(
            provider: .claude,
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
            windows: [
                LimitWindow(windowKind: .session, rawKind: "session", percent: 0, severity: "normal", resetsAt: nil, isActive: false),
                LimitWindow(windowKind: .weekly, rawKind: "weekly_all", percent: 8, severity: "normal", resetsAt: Date(timeIntervalSince1970: 1_800_500_000), isActive: true)
            ],
            extraUsage: ClaudeExtraUsage(isEnabled: false, monthlyLimit: 16000, usedCredits: 15558, utilizationPercent: 97.2375, currency: "AUD", spendPercent: 97, spendSeverity: "critical")
        )

        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.schemaVersion, UsageSnapshot.currentSchemaVersion)
    }

    func testSharedUsageSnapshotsRoundTripsWithBothProvidersAndWithNils() throws {
        let claude = UsageSnapshot(provider: .claude, fetchedAt: Date(timeIntervalSince1970: 1_800_000_000), windows: [])
        let codex = UsageSnapshot(
            provider: .codex,
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_100),
            windows: [LimitWindow(windowKind: .weekly, percent: 9, windowSeconds: 604_800)],
            resetCredits: ResetCredit(availableCount: 0, applicableAvailableCount: 0)
        )
        let bundle = SharedUsageSnapshots(updatedAt: Date(timeIntervalSince1970: 1_800_000_200), claude: claude, codex: codex)

        let data = try makeEncoder().encode(bundle)
        let decoded = try makeDecoder().decode(SharedUsageSnapshots.self, from: data)
        XCTAssertEqual(decoded, bundle)

        let claudeOnly = SharedUsageSnapshots(updatedAt: Date(timeIntervalSince1970: 1_800_000_200), claude: claude, codex: nil)
        let claudeOnlyData = try makeEncoder().encode(claudeOnly)
        let claudeOnlyDecoded = try makeDecoder().decode(SharedUsageSnapshots.self, from: claudeOnlyData)
        XCTAssertNil(claudeOnlyDecoded.codex)
        XCTAssertEqual(claudeOnlyDecoded.claude, claude)
    }

    func testProviderKindRawValuesAreStable() {
        // These raw values are what ends up on disk (SnapshotStore) and must never
        // silently change, or an old widget reading a new file (or vice versa) would
        // misclassify providers.
        XCTAssertEqual(ProviderKind.claude.rawValue, "claude")
        XCTAssertEqual(ProviderKind.codex.rawValue, "codex")
    }
}
