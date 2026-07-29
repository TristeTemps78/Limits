import XCTest
@testable import LimitsCore

/// Locks in the exact wording so two widget views can never silently drift onto
/// different text for the same state — the actual value of centralizing copy in
/// `LimitsCore` (rule 4, AGENTS.md) is only real if it's covered.
final class WidgetCopyTests: XCTestCase {
    func testProviderDisplayNames() {
        XCTAssertEqual(ProviderKind.claude.displayName, "Claude")
        XCTAssertEqual(ProviderKind.codex.displayName, "Codex")
    }

    func testWindowKindLabels() {
        XCTAssertEqual(LimitWindowKind.session.shortLabel, "5 h")
        XCTAssertEqual(LimitWindowKind.weekly.shortLabel, "hebdo")
    }

    func testSnapshotStoreErrorMessagesAreAllDistinct() {
        let errors: [SnapshotStoreError] = [
            .containerUnavailable, .fileNotFound,
            .unsupportedSchemaVersion(found: 2, expected: 1), .corrupted, .encodingFailed
        ]
        let messages = Set(errors.map(\.widgetDiagnosticMessage))
        XCTAssertEqual(messages.count, errors.count, "every failure mode must read as a distinct, explicit placeholder")
    }

    func testFreshnessBannerIsNilOnlyWhenFresh() {
        XCTAssertNil(SnapshotFreshnessLevel.fresh.widgetBannerMessage)
        XCTAssertNotNil(SnapshotFreshnessLevel.aging.widgetBannerMessage)
        XCTAssertNotNil(SnapshotFreshnessLevel.stale.widgetBannerMessage)
        XCTAssertNotEqual(
            SnapshotFreshnessLevel.aging.widgetBannerMessage,
            SnapshotFreshnessLevel.stale.widgetBannerMessage
        )
    }
}
