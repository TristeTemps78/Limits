import XCTest
@testable import LimitsCore

final class WidgetTimelinePlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNoSnapshotsProducesASingleEntryAndTheFallbackReload() {
        let plan = WidgetTimelinePlanner.plan(snapshots: nil, now: now)
        XCTAssertEqual(plan.entryDates, [now])
        XCTAssertEqual(plan.reloadAfter, now.addingTimeInterval(WidgetTimelinePlanner.minimumFallbackInterval))
    }

    func testInactiveWindowsProduceNoExtraEntries() {
        // Claude session with `resetsAt: nil` — nothing to schedule around.
        let snapshots = SharedUsageSnapshots(updatedAt: now, claude: nil, codex: nil)
        let plan = WidgetTimelinePlanner.plan(snapshots: snapshots, now: now)
        XCTAssertEqual(plan.entryDates, [now])
    }

    func testAResetWellWithinTheFallbackWindowGetsItsOwnEntry() {
        let resetIn10Minutes = now.addingTimeInterval(10 * 60)
        let claude = UsageSnapshot(
            provider: .claude, fetchedAt: now,
            windows: [LimitWindow(windowKind: .weekly, percent: 8, resetsAt: resetIn10Minutes)]
        )
        let snapshots = SharedUsageSnapshots(updatedAt: now, claude: claude, codex: nil)
        let plan = WidgetTimelinePlanner.plan(snapshots: snapshots, now: now)
        XCTAssertEqual(plan.entryDates, [now, resetIn10Minutes])
    }

    func testAResetBeyondTheFallbackWindowIsNotScheduledYet() {
        // Will be picked up on a later replan once it's within the window — not
        // scheduled now, which would mean guessing a reload cadence tighter than the
        // fallback for no reason.
        let resetIn2Hours = now.addingTimeInterval(2 * 60 * 60)
        let claude = UsageSnapshot(
            provider: .claude, fetchedAt: now,
            windows: [LimitWindow(windowKind: .weekly, percent: 8, resetsAt: resetIn2Hours)]
        )
        let snapshots = SharedUsageSnapshots(updatedAt: now, claude: claude, codex: nil)
        let plan = WidgetTimelinePlanner.plan(snapshots: snapshots, now: now)
        XCTAssertEqual(plan.entryDates, [now])
    }

    func testAResetInThePastIsNeverScheduledAsAFutureEntry() {
        let past = now.addingTimeInterval(-60)
        let claude = UsageSnapshot(
            provider: .claude, fetchedAt: now,
            windows: [LimitWindow(windowKind: .weekly, percent: 8, resetsAt: past)]
        )
        let snapshots = SharedUsageSnapshots(updatedAt: now, claude: claude, codex: nil)
        let plan = WidgetTimelinePlanner.plan(snapshots: snapshots, now: now)
        XCTAssertEqual(plan.entryDates, [now])
    }

    func testMultipleUpcomingResetsAreAllIncludedSortedAndDeduped() {
        let resetA = now.addingTimeInterval(5 * 60)
        let resetB = now.addingTimeInterval(20 * 60)
        let claude = UsageSnapshot(
            provider: .claude, fetchedAt: now,
            windows: [
                LimitWindow(windowKind: .session, percent: 1, resetsAt: resetB), // out of order on purpose
                LimitWindow(windowKind: .weekly, percent: 8, resetsAt: resetA)
            ]
        )
        let codex = UsageSnapshot(
            provider: .codex, fetchedAt: now,
            windows: [LimitWindow(windowKind: .weekly, percent: 9, resetsAt: resetA, windowSeconds: 604_800)] // duplicate of resetA
        )
        let snapshots = SharedUsageSnapshots(updatedAt: now, claude: claude, codex: codex)
        let plan = WidgetTimelinePlanner.plan(snapshots: snapshots, now: now)
        XCTAssertEqual(plan.entryDates, [now, resetA, resetB])
    }

    func testReloadAfterIsAlwaysTheFallbackRegardlessOfScheduledResets() {
        let resetIn10Minutes = now.addingTimeInterval(10 * 60)
        let claude = UsageSnapshot(
            provider: .claude, fetchedAt: now,
            windows: [LimitWindow(windowKind: .weekly, percent: 8, resetsAt: resetIn10Minutes)]
        )
        let snapshots = SharedUsageSnapshots(updatedAt: now, claude: claude, codex: nil)
        let plan = WidgetTimelinePlanner.plan(snapshots: snapshots, now: now)
        XCTAssertEqual(plan.reloadAfter, now.addingTimeInterval(WidgetTimelinePlanner.minimumFallbackInterval))
    }

    func testFallbackIntervalIsNotTighterThanOneHour() {
        // Guards against a future "just make it more responsive" edit accidentally
        // reintroducing the tight fixed-interval polling the brief explicitly warns
        // against (WidgetKit's daily reload budget is finite).
        XCTAssertGreaterThanOrEqual(WidgetTimelinePlanner.minimumFallbackInterval, 60 * 60)
    }
}
