import XCTest
@testable import LimitsCore

final class RefreshStateStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "limits.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore() -> RefreshStateStore {
        RefreshStateStore(defaults: defaults)
    }

    func testEmptyStoreReportsIdleAndNoLastFetch() {
        let store = makeStore()
        XCTAssertNil(store.lastFetchAt(for: .claude))
        XCTAssertEqual(store.pollingState(for: .claude), .idle)
        XCTAssertEqual(store.notificationLedger(), NotificationLedger())
    }

    func testBackoffSurvivesANewStoreInstance() {
        // Le scénario réel : iOS réveille la tâche de fond dans un processus neuf. Si le
        // backoff ne survivait pas, on retaperait sur un endpoint qui vient de répondre
        // 429 — exactement ce que la règle 7 interdit.
        let until = Date(timeIntervalSince1970: 1_785_100_000)
        let fetchedAt = Date(timeIntervalSince1970: 1_785_099_000)
        makeStore().record(provider: .codex, lastFetchAt: fetchedAt, state: .backoff(until: until, consecutiveFailures: 3))

        let reread = makeStore()
        XCTAssertEqual(reread.pollingState(for: .codex), .backoff(until: until, consecutiveFailures: 3))
        XCTAssertEqual(reread.lastFetchAt(for: .codex), fetchedAt)
    }

    func testNeedsReconnectSurvivesAndStaysTerminal() {
        makeStore().record(provider: .claude, lastFetchAt: Date(), state: .needsReconnect)
        XCTAssertEqual(makeStore().pollingState(for: .claude), .needsReconnect)
    }

    func testProvidersAreStoredIndependently() {
        let store = makeStore()
        store.record(provider: .claude, lastFetchAt: Date(timeIntervalSince1970: 1), state: .needsReconnect)
        store.record(provider: .codex, lastFetchAt: Date(timeIntervalSince1970: 2), state: .idle)
        XCTAssertEqual(store.pollingState(for: .claude), .needsReconnect)
        XCTAssertEqual(store.pollingState(for: .codex), .idle)
    }

    func testClearingOneProviderUnblocksItWithoutTouchingTheOther() {
        // Sans ce reset, `.needsReconnect` étant terminal, une reconnexion réussie
        // laisserait l'app bloquée malgré un token neuf.
        let store = makeStore()
        store.record(provider: .claude, lastFetchAt: Date(), state: .needsReconnect)
        store.record(provider: .codex, lastFetchAt: Date(), state: .needsReconnect)
        store.clear(provider: .claude)
        XCTAssertEqual(store.pollingState(for: .claude), .idle)
        XCTAssertNil(store.lastFetchAt(for: .claude))
        XCTAssertEqual(store.pollingState(for: .codex), .needsReconnect)
    }

    func testLedgerPersistsAlongsideProviderState() {
        let store = makeStore()
        var ledger = NotificationLedger()
        ledger.entries[NotificationLedger.key(provider: .claude, windowKind: .weekly)] =
            NotificationLedger.Entry(windowResetsAt: Date(timeIntervalSince1970: 10), notifiedThresholds: [80, 95])
        store.save(ledger: ledger)
        store.record(provider: .claude, lastFetchAt: Date(timeIntervalSince1970: 5), state: .idle)

        // Enregistrer un état de provider ne doit pas effacer le journal, et inversement.
        XCTAssertEqual(makeStore().notificationLedger(), ledger)
        XCTAssertEqual(makeStore().lastFetchAt(for: .claude), Date(timeIntervalSince1970: 5))
    }

    func testCorruptedPayloadDegradesToEmptyRatherThanCrashing() {
        defaults.set(Data("pas du JSON".utf8), forKey: "refresh-state.v1")
        let store = makeStore()
        XCTAssertEqual(store.pollingState(for: .claude), .idle)
        XCTAssertEqual(store.notificationLedger(), NotificationLedger())
    }

    func testMissingAppGroupIsToleratedNotFatal() {
        let store = RefreshStateStore(defaults: nil)
        store.record(provider: .claude, lastFetchAt: Date(), state: .idle)
        XCTAssertEqual(store.pollingState(for: .claude), .idle)
        XCTAssertNil(store.lastFetchAt(for: .claude))
    }
}
