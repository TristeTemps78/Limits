import XCTest
@testable import LimitsCore

/// Cohérence entre les surfaces (app, widget) et bout-en-bout de la politique réseau.
///
/// Ces tests n'existaient pas avant l'audit final, et c'est révélateur : chaque lot avait
/// été testé isolément et relu isolément, mais **rien** ne vérifiait les propriétés qui
/// n'appartiennent à aucun lot en particulier — la cohérence entre deux cibles UI, et
/// l'enchaînement de trois composants sur un scénario réel.
final class CrossSurfaceConsistencyTests: XCTestCase {

    // MARK: - Iconographie partagée app ↔ widget

    func testEverySeverityHasANonEmptySymbolAndLabel() {
        // Le symbole et le mot court sont la **seule** information de sévérité qui survive
        // au rendu `accented`/`vibrant` de l'écran verrouillé, où iOS écrase les couleurs.
        // Un cas vide y serait une perte d'information totale, pas un détail esthétique.
        for severity in WindowSeverity.allCases {
            XCTAssertFalse(severity.symbolName.isEmpty, "\(severity) sans symbole")
            XCTAssertFalse(severity.shortLabel.isEmpty, "\(severity) sans libellé court")
        }
    }

    func testSeveritySymbolsAreAllDistinct() {
        // Deux sévérités qui partageraient le même symbole seraient indiscernables une fois
        // la couleur écrasée.
        let symbols = WindowSeverity.allCases.map(\.symbolName)
        XCTAssertEqual(Set(symbols).count, symbols.count, "symboles en doublon : \(symbols)")
    }

    func testSeverityLabelsAreAllDistinct() {
        let labels = WindowSeverity.allCases.map(\.shortLabel)
        XCTAssertEqual(Set(labels).count, labels.count, "libellés en doublon : \(labels)")
    }

    func testPercentFormattingIsSharedSoAppAndWidgetCannotDisagree() {
        // Un seul arrondi possible : sinon 8,5 % pourrait s'afficher « 8 % » dans l'app et
        // « 9 % » sur le widget pour le même relevé.
        XCTAssertEqual(8.5.roundedPercentText, "9%")
        XCTAssertEqual(8.4.roundedPercentText, "8%")
        XCTAssertEqual(0.0.roundedPercentText, "0%")
        XCTAssertEqual(105.0.roundedPercentText, "105%", "un dépassement doit rester visible, pas être borné")
    }

    // MARK: - Le même snapshot doit produire des états cohérents des deux côtés

    func testUnexpectedPayloadIsDetectedIdenticallyByAppAndWidget() {
        // Même entrée, deux réducteurs distincts (un pour l'app, un pour le widget) : ils
        // doivent conclure la même chose, sinon l'app dirait « format inattendu » pendant
        // que le widget dirait « non connecté ».
        let emptySnapshot = UsageSnapshot(provider: .claude, fetchedAt: Date(), windows: [])

        let appState = AppProviderDashboardStateBuilder.build(
            isConnected: true,
            lastSnapshot: emptySnapshot,
            pollingState: .idle,
            lastOutcome: .success
        )
        let widgetState = WidgetContentStateBuilder.build(
            result: .success(SharedUsageSnapshots(
                updatedAt: Date(),
                claude: emptySnapshot,
                codex: nil,
                claudeStatus: .connected,
                codexStatus: .notConnected
            )),
            now: Date()
        )

        XCTAssertEqual(appState, .unexpectedPayload(snapshot: emptySnapshot))
        XCTAssertEqual(widgetState, .unexpectedPayload)
    }

    func testFirstLoadIsNotMistakenForABrokenAPI() {
        // Nuance qui compte : un provider connecté dont aucun fetch n'a encore abouti n'a
        // pas de snapshot du tout. Ce n'est pas un format cassé, c'est un premier
        // chargement — le confondre afficherait « mets l'app à jour » au tout premier
        // lancement.
        let widgetState = WidgetContentStateBuilder.build(
            result: .success(SharedUsageSnapshots(
                updatedAt: Date(),
                claude: nil,
                codex: nil,
                claudeStatus: .connected,
                codexStatus: .notConnected
            )),
            now: Date()
        )
        XCTAssertNotEqual(widgetState, .unexpectedPayload)
    }

    func testReconnectTakesPrecedenceOverUnexpectedPayload() {
        // Un provider en « reconnecter » avec un snapshot vide : c'est la reconnexion qui
        // explique la situation, pas un changement de format. Afficher « format inattendu »
        // ici enverrait l'utilisateur régénérer des fixtures au lieu de se reconnecter.
        let widgetState = WidgetContentStateBuilder.build(
            result: .success(SharedUsageSnapshots(
                updatedAt: Date(),
                claude: UsageSnapshot(provider: .claude, fetchedAt: Date(), windows: []),
                codex: nil,
                claudeStatus: .needsReconnect,
                codexStatus: .notConnected
            )),
            now: Date()
        )
        XCTAssertNotEqual(widgetState, .unexpectedPayload)
    }

    // MARK: - 429 de bout en bout : politique + persistance + refus au réveil suivant

    func testRateLimitBackoffSurvivesAProcessRestartAndBlocksTheNextWake() {
        // Le scénario que rien ne couvrait : trois composants s'enchaînent (PollingPolicy
        // décide, RefreshStateStore persiste, le réveil suivant relit). Si le maillon de
        // persistance manquait, chaque réveil de la tâche de fond repartirait « idle » et
        // retaperait sur un endpoint qui vient de répondre 429 — précisément ce que la
        // règle 7 d'AGENTS.md interdit.
        let suiteName = "limits.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let t0 = Date(timeIntervalSince1970: 1_785_000_000)
        let policy = PollingPolicy(clock: { t0 })

        // 1. Un 429 avec Retry-After de 5 minutes.
        let afterRateLimit = policy.nextState(current: .idle, outcome: .rateLimited(retryAfter: 300))
        guard case .backoff(let until, _) = afterRateLimit else {
            return XCTFail("un 429 doit produire un backoff")
        }
        XCTAssertEqual(until, t0.addingTimeInterval(300), "Retry-After doit être respecté tel quel")

        // 2. Persistance, puis « redémarrage du processus ».
        RefreshStateStore(defaults: defaults).record(provider: .claude, lastFetchAt: t0, state: afterRateLimit)
        let afterRestart = RefreshStateStore(defaults: defaults)
        XCTAssertEqual(afterRestart.pollingState(for: .claude), afterRateLimit)

        // 3. Réveil 1 minute plus tard : refusé.
        let oneMinuteLater = t0.addingTimeInterval(60)
        XCTAssertFalse(
            PollingPolicy(clock: { oneMinuteLater }).canFetch(
                trigger: .scheduled,
                lastFetchAt: afterRestart.lastFetchAt(for: .claude),
                state: afterRestart.pollingState(for: .claude)
            ),
            "pendant le backoff, aucun fetch — même après un redémarrage"
        )

        // 4. Réveil après l'expiration du backoff **et** du minimum de 15 min : autorisé.
        let later = t0.addingTimeInterval(16 * 60)
        XCTAssertTrue(
            PollingPolicy(clock: { later }).canFetch(
                trigger: .scheduled,
                lastFetchAt: afterRestart.lastFetchAt(for: .claude),
                state: afterRestart.pollingState(for: .claude)
            ),
            "une fois le backoff expiré, le fetch doit repartir"
        )
    }

    func testNeedsReconnectIsNeverUnblockedByTimeAlone() {
        // `.needsReconnect` est terminal : seul un vrai reset (reconnexion) le lève. Si le
        // temps suffisait, l'app boucherait indéfiniment sur un token mort.
        let t0 = Date(timeIntervalSince1970: 1_785_000_000)
        let veryMuchLater = t0.addingTimeInterval(30 * 24 * 3_600)
        XCTAssertFalse(
            PollingPolicy(clock: { veryMuchLater }).canFetch(
                trigger: .scheduled,
                lastFetchAt: t0,
                state: .needsReconnect
            )
        )
        XCTAssertFalse(
            PollingPolicy(clock: { veryMuchLater }).canFetch(
                trigger: .manualRefresh,
                lastFetchAt: t0,
                state: .needsReconnect
            ),
            "même un rafraîchissement manuel ne doit pas contourner un état terminal"
        )
    }
}
