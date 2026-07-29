import XCTest
@testable import LimitsCore

final class NotificationPlanningTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_785_000_000)

    private func window(
        kind: LimitWindowKind = .session,
        percent: Double,
        resetsAt: Date?
    ) -> LimitWindow {
        LimitWindow(windowKind: kind, percent: percent, resetsAt: resetsAt)
    }

    private func snapshots(claudeWindows: [LimitWindow] = [], codexWindows: [LimitWindow] = []) -> SharedUsageSnapshots {
        SharedUsageSnapshots(
            updatedAt: now,
            claude: claudeWindows.isEmpty ? nil : UsageSnapshot(provider: .claude, fetchedAt: now, windows: claudeWindows),
            codex: codexWindows.isEmpty ? nil : UsageSnapshot(provider: .codex, fetchedAt: now, windows: codexWindows)
        )
    }

    // MARK: - Reset

    func testSchedulesOneResetNotificationPerFutureWindow() {
        let future = now.addingTimeInterval(3_600)
        let result = NotificationPlanner.plan(
            snapshots: snapshots(claudeWindows: [window(percent: 10, resetsAt: future)]),
            ledger: NotificationLedger(),
            now: now
        )
        let resets = result.notifications.filter { $0.trigger == .at(future) }
        XCTAssertEqual(resets.count, 1)
        XCTAssertTrue(resets[0].id.hasPrefix("reset|claude|session|"))
    }

    func testInactiveWindowSchedulesNoReset() {
        // `resetsAt == nil` = fenêtre inactive, un état normal — pas de notification.
        let result = NotificationPlanner.plan(
            snapshots: snapshots(claudeWindows: [window(percent: 0, resetsAt: nil)]),
            ledger: NotificationLedger(),
            now: now
        )
        XCTAssertTrue(result.notifications.isEmpty)
    }

    func testPastResetIsNeverNotified() {
        // Sinon, ouvrir l'app après une semaine d'absence enverrait une alerte pour un
        // reset vieux de plusieurs jours.
        let result = NotificationPlanner.plan(
            snapshots: snapshots(claudeWindows: [window(percent: 10, resetsAt: now.addingTimeInterval(-60))]),
            ledger: NotificationLedger(),
            now: now
        )
        XCTAssertTrue(result.notifications.isEmpty)
    }

    func testResetIdentifierIsStableAcrossReplans() {
        // Idempotence : reprogrammer le même plan ne doit pas créer de doublon.
        let future = now.addingTimeInterval(7_200)
        let input = snapshots(claudeWindows: [window(percent: 10, resetsAt: future)])
        let first = NotificationPlanner.plan(snapshots: input, ledger: NotificationLedger(), now: now)
        let second = NotificationPlanner.plan(snapshots: input, ledger: first.ledger, now: now)
        XCTAssertEqual(first.notifications.map(\.id), second.notifications.map(\.id))
    }

    // MARK: - Seuils

    func testCrossingAThresholdNotifiesOnceThenNeverAgainForTheSameWindow() {
        let future = now.addingTimeInterval(3_600)
        let input = snapshots(claudeWindows: [window(percent: 82, resetsAt: future)])

        let first = NotificationPlanner.plan(snapshots: input, ledger: NotificationLedger(), now: now)
        let thresholdsFirst = first.notifications.filter { $0.trigger == .immediate }
        XCTAssertEqual(thresholdsFirst.count, 1)
        XCTAssertEqual(thresholdsFirst[0].id, "threshold|claude|session|80")

        // Deuxième fetch, même fenêtre, pourcentage encore au-dessus : plus rien.
        let second = NotificationPlanner.plan(
            snapshots: snapshots(claudeWindows: [window(percent: 85, resetsAt: future)]),
            ledger: first.ledger,
            now: now
        )
        XCTAssertTrue(second.notifications.filter { $0.trigger == .immediate }.isEmpty)
    }

    func testWindowResetClearsTheLedgerSoTheUserIsWarnedAgainNextCycle() {
        let firstWindowReset = now.addingTimeInterval(3_600)
        let first = NotificationPlanner.plan(
            snapshots: snapshots(claudeWindows: [window(percent: 82, resetsAt: firstWindowReset)]),
            ledger: NotificationLedger(),
            now: now
        )
        XCTAssertEqual(first.notifications.filter { $0.trigger == .immediate }.count, 1)

        // Nouvelle fenêtre (resetsAt différent) : le seuil doit pouvoir re-notifier.
        let secondWindowReset = now.addingTimeInterval(30_000)
        let second = NotificationPlanner.plan(
            snapshots: snapshots(claudeWindows: [window(percent: 81, resetsAt: secondWindowReset)]),
            ledger: first.ledger,
            now: now
        )
        XCTAssertEqual(second.notifications.filter { $0.trigger == .immediate }.count, 1)
    }

    func testJumpingPastBothThresholdsNotifiesOnlyTheHighest() {
        // Une longue session entre deux fetchs peut faire passer de 40 % à 96 % :
        // l'utilisateur doit recevoir « 95 % », pas deux notifications empilées.
        let future = now.addingTimeInterval(3_600)
        let result = NotificationPlanner.plan(
            snapshots: snapshots(claudeWindows: [window(percent: 96, resetsAt: future)]),
            ledger: NotificationLedger(),
            now: now
        )
        let immediate = result.notifications.filter { $0.trigger == .immediate }
        XCTAssertEqual(immediate.count, 1)
        XCTAssertEqual(immediate[0].id, "threshold|claude|session|95")
        // …et le seuil 80 est marqué comme notifié, pour ne pas ressortir au fetch suivant.
        let key = NotificationLedger.key(provider: .claude, windowKind: .session)
        XCTAssertEqual(result.ledger.entries[key]?.notifiedThresholds, [80, 95])
    }

    func testBelowThresholdNotifiesNothing() {
        let result = NotificationPlanner.plan(
            snapshots: snapshots(claudeWindows: [window(percent: 79.4, resetsAt: now.addingTimeInterval(3_600))]),
            ledger: NotificationLedger(),
            now: now
        )
        XCTAssertTrue(result.notifications.filter { $0.trigger == .immediate }.isEmpty)
    }

    func testProvidersAndWindowsAreTrackedIndependently() {
        let future = now.addingTimeInterval(3_600)
        let result = NotificationPlanner.plan(
            snapshots: snapshots(
                claudeWindows: [window(kind: .session, percent: 90, resetsAt: future)],
                codexWindows: [window(kind: .weekly, percent: 90, resetsAt: future)]
            ),
            ledger: NotificationLedger(),
            now: now
        )
        let ids = Set(result.notifications.filter { $0.trigger == .immediate }.map(\.id))
        XCTAssertEqual(ids, ["threshold|claude|session|80", "threshold|codex|weekly|80"])
    }

    func testInvalidThresholdsAreIgnoredRatherThanNotifiedOn() {
        let result = NotificationPlanner.plan(
            snapshots: snapshots(claudeWindows: [window(percent: 50, resetsAt: now.addingTimeInterval(3_600))]),
            thresholds: [0, -10, 120],
            ledger: NotificationLedger(),
            now: now
        )
        XCTAssertTrue(result.notifications.filter { $0.trigger == .immediate }.isEmpty)
    }

    func testLedgerSurvivesAJSONRoundTrip() {
        // Le journal est persisté entre l'app et la tâche de fond : s'il ne se
        // sérialisait pas, chaque rafraîchissement re-notifierait le même seuil.
        var ledger = NotificationLedger()
        ledger.entries[NotificationLedger.key(provider: .codex, windowKind: .weekly)] =
            NotificationLedger.Entry(windowResetsAt: now, notifiedThresholds: [80])
        let data = try! JSONEncoder().encode(ledger)
        let decoded = try! JSONDecoder().decode(NotificationLedger.self, from: data)
        XCTAssertEqual(decoded, ledger)
    }
}
