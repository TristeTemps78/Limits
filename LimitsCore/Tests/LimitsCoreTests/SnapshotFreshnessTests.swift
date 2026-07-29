import XCTest
@testable import LimitsCore

final class SnapshotFreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Levels

    func testFreshJustUnderAgingThreshold() {
        let fetchedAt = now.addingTimeInterval(-(SnapshotFreshness.agingThreshold - 1))
        XCTAssertEqual(SnapshotFreshness.level(fetchedAt: fetchedAt, now: now), .fresh)
    }

    func testAgingAtExactlyAgingThreshold() {
        let fetchedAt = now.addingTimeInterval(-SnapshotFreshness.agingThreshold)
        XCTAssertEqual(SnapshotFreshness.level(fetchedAt: fetchedAt, now: now), .aging)
    }

    func testAgingJustUnderStaleThreshold() {
        let fetchedAt = now.addingTimeInterval(-(SnapshotFreshness.staleThreshold - 1))
        XCTAssertEqual(SnapshotFreshness.level(fetchedAt: fetchedAt, now: now), .aging)
    }

    func testStaleAtExactlyStaleThreshold() {
        let fetchedAt = now.addingTimeInterval(-SnapshotFreshness.staleThreshold)
        XCTAssertEqual(SnapshotFreshness.level(fetchedAt: fetchedAt, now: now), .stale)
    }

    func testAgingThresholdIsTwicePollingPolicysScheduledInterval() {
        // Not a coincidence — documents the relationship so a future change to
        // `PollingPolicy.minimumScheduledInterval` doesn't silently desync this.
        XCTAssertEqual(SnapshotFreshness.agingThreshold, PollingPolicy.minimumScheduledInterval * 2)
    }

    // MARK: - relativeLabel

    func testRelativeLabelWording() {
        XCTAssertEqual(SnapshotFreshness.relativeLabel(fetchedAt: now, now: now), "à l'instant")
        XCTAssertEqual(SnapshotFreshness.relativeLabel(fetchedAt: now.addingTimeInterval(-30), now: now), "à l'instant")
        XCTAssertEqual(SnapshotFreshness.relativeLabel(fetchedAt: now.addingTimeInterval(-60), now: now), "il y a 1 min")
        XCTAssertEqual(SnapshotFreshness.relativeLabel(fetchedAt: now.addingTimeInterval(-15 * 60), now: now), "il y a 15 min")
        XCTAssertEqual(SnapshotFreshness.relativeLabel(fetchedAt: now.addingTimeInterval(-3600), now: now), "il y a 1 h")
        XCTAssertEqual(SnapshotFreshness.relativeLabel(fetchedAt: now.addingTimeInterval(-25 * 3600), now: now), "il y a 25 h")
        XCTAssertEqual(SnapshotFreshness.relativeLabel(fetchedAt: now.addingTimeInterval(-3 * 24 * 3600), now: now), "il y a 3 j")
    }

    func testRelativeLabelNeverGoesNegativeOnAFutureFetchedAt() {
        // Defensive: a clock skew or a bad injected `now` must not print "il y a -5 min".
        let future = now.addingTimeInterval(300)
        XCTAssertEqual(SnapshotFreshness.relativeLabel(fetchedAt: future, now: now), "à l'instant")
    }
}
