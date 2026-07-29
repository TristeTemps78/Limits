import XCTest
@testable import LimitsCore

/// **Tests adverses.** Tous les autres tests de parsing valident les 4 fixtures réelles
/// telles qu'elles ont été capturées : un seul compte, un seul plan, un seul jour. C'est
/// une base de validation étroite, et le risque n'est pas qu'elle soit fausse — c'est
/// qu'elle soit **muette** sur tout ce qu'on n'a jamais vu : un plan Max avec
/// `seven_day_opus` rempli, une session réellement active, un compte Codex avec ses deux
/// fenêtres, un champ renommé par le fournisseur, un type qui change.
///
/// Ces tests prennent donc les fixtures réelles et les **abîment systématiquement** —
/// suppression de clé, mise à `null`, changement de type, valeurs aberrantes — puis
/// vérifient deux choses seulement, mais sur toutes les mutations :
///
/// 1. **aucun crash** (règle 3 d'AGENTS.md : parsing tolérant, jamais de plantage) ;
/// 2. quand le décodage réussit, les **invariants du domaine** tiennent — pas de
///    pourcentage négatif ou non fini, pas de fenêtre inventée, pas de date absurde.
///
/// C'est délibérément une approche différente des tests par l'exemple : on ne cherche pas
/// à valider un cas connu de plus, on cherche à casser.
final class FixtureMutationTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_785_000_000)

    // MARK: - Outils de mutation

    /// Toutes les mutations d'un objet JSON, une par clé de premier niveau.
    private func mutations(of object: [String: Any]) -> [(name: String, json: [String: Any])] {
        var result: [(String, [String: Any])] = []
        for key in object.keys.sorted() {
            var removed = object
            removed.removeValue(forKey: key)
            result.append(("clé « \(key) » supprimée", removed))

            var nulled = object
            nulled[key] = NSNull()
            result.append(("clé « \(key) » à null", nulled))

            var retyped = object
            // Type volontairement incompatible : une string là où le décodeur attend un
            // objet, un nombre ou un tableau.
            retyped[key] = "type-inattendu"
            result.append(("clé « \(key) » de type inattendu", retyped))

            var numbered = object
            numbered[key] = 42
            result.append(("clé « \(key) » remplacée par un nombre", numbered))
        }
        // Clé inconnue ajoutée : ne doit jamais faire échouer le décodage.
        var extra = object
        extra["une_cle_que_personne_na_jamais_vue"] = ["imbriqué": [1, 2, 3]]
        result.append(("clé inconnue ajoutée", extra))
        return result
    }

    private func data(_ json: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: json)
    }

    private func assertInvariants(_ snapshot: UsageSnapshot, mutation: String) {
        for window in snapshot.windows {
            XCTAssertTrue(
                window.percent.isFinite,
                "[\(mutation)] pourcentage non fini : une jauge NaN casserait le rendu du widget"
            )
            XCTAssertGreaterThanOrEqual(
                window.percent, 0,
                "[\(mutation)] pourcentage négatif : la jauge se dessinerait à l'envers"
            )
            if let resetsAt = window.resetsAt {
                // Une date de reset ne peut pas être antérieure à 2020 ni postérieure à
                // 2100 : ce serait le signe d'un epoch mal interprété (secondes vs
                // millisecondes), qui produirait un compte à rebours faux et crédible.
                XCTAssertGreaterThan(resetsAt.timeIntervalSince1970, 1_577_836_800, "[\(mutation)] reset avant 2020")
                XCTAssertLessThan(resetsAt.timeIntervalSince1970, 4_102_444_800, "[\(mutation)] reset après 2100")
            }
        }
        if let extra = snapshot.extraUsage {
            if let percent = extra.utilizationPercent {
                XCTAssertTrue(percent.isFinite, "[\(mutation)] utilisation non finie")
            }
        }
    }

    // MARK: - Claude

    func testClaudeSurvivesEveryTopLevelMutation() throws {
        let original = try XCTUnwrap(FixtureLoader.loadJSON("claude-usage") as? [String: Any])
        var decodedCount = 0

        for mutation in mutations(of: original) {
            let result = ClaudeUsageClient.handle(
                .success(HTTPResponse(statusCode: 200, headers: [:], body: try data(mutation.json))),
                clock: { self.fetchedAt }
            )
            switch result {
            case .success(let snapshot):
                decodedCount += 1
                assertInvariants(snapshot, mutation: mutation.name)
            case .failure(let error):
                // Un échec est acceptable ; ce qui ne le serait pas, c'est un crash ou un
                // succès porteur de données fausses.
                guard case .decoding = error else {
                    return XCTFail("[\(mutation.name)] erreur inattendue : \(error)")
                }
            }
        }

        // Garde-fou sur le test lui-même : si *aucune* mutation ne décodait, ce test
        // passerait sans rien prouver.
        XCTAssertGreaterThan(decodedCount, 10, "le parsing devrait rester tolérant à la majorité des mutations")
    }

    func testClaudeIgnoresUnknownKeysEvenNonNullAndNested() throws {
        var json = try XCTUnwrap(FixtureLoader.loadJSON("claude-usage") as? [String: Any])
        json["seven_day_quelque_chose_de_nouveau"] = ["utilization": 42.0, "resets_at": "2026-09-01T00:00:00Z"]
        json["un_tableau_surprise"] = [["a": 1], ["b": 2]]

        let result = ClaudeUsageClient.handle(
            .success(HTTPResponse(statusCode: 200, headers: [:], body: try data(json))),
            clock: { self.fetchedAt }
        )
        guard case .success(let snapshot) = result else {
            return XCTFail("une clé inconnue ne doit jamais faire échouer le décodage (règle 3)")
        }
        // Les valeurs réelles restent celles de la fixture : la clé inconnue n'a rien pollué.
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows.first(where: { $0.windowKind == .weekly })?.percent, 8)
    }

    func testClaudeWithAnActiveSessionIsNotSilentlyMislabelled() throws {
        // Cas jamais capturé : une session **active** avec un reset non nul. Toutes nos
        // fixtures ont `session` inactive à 0 %.
        var json = try XCTUnwrap(FixtureLoader.loadJSON("claude-usage") as? [String: Any])
        json["limits"] = [
            ["kind": "session", "group": "session", "percent": 64, "severity": "warning",
             "resets_at": "2026-08-01T12:30:00.5+00:00", "is_active": true],
            ["kind": "weekly_all", "group": "weekly", "percent": 8, "severity": "normal",
             "resets_at": "2026-08-04T17:59:59.981775+00:00", "is_active": true]
        ]

        let result = ClaudeUsageClient.handle(
            .success(HTTPResponse(statusCode: 200, headers: [:], body: try data(json))),
            clock: { self.fetchedAt }
        )
        guard case .success(let snapshot) = result else { return XCTFail("décodage échoué") }
        let session = try XCTUnwrap(snapshot.windows.first(where: { $0.windowKind == .session }))
        XCTAssertEqual(session.percent, 64)
        XCTAssertEqual(session.isActive, true)
        XCTAssertNotNil(session.resetsAt, "un reset à 1 décimale doit être parsé")
        XCTAssertEqual(session.severity, "warning")
    }

    func testClaudePercentAboveOneHundredIsPreservedNotClampedSilently() throws {
        // Un dépassement de quota peut légitimement donner > 100. On veut que la valeur
        // remonte telle quelle (charge aux jauges de borner leur dessin) plutôt qu'elle
        // soit écrasée à 100, ce qui masquerait l'information.
        var json = try XCTUnwrap(FixtureLoader.loadJSON("claude-usage") as? [String: Any])
        json["limits"] = [["kind": "session", "group": "session", "percent": 105, "is_active": true]]

        let result = ClaudeUsageClient.handle(
            .success(HTTPResponse(statusCode: 200, headers: [:], body: try data(json))),
            clock: { self.fetchedAt }
        )
        guard case .success(let snapshot) = result else { return XCTFail("décodage échoué") }
        XCTAssertEqual(snapshot.windows.first?.percent, 105)
    }

    // MARK: - Codex

    func testCodexSurvivesEveryTopLevelMutation() throws {
        let original = try XCTUnwrap(FixtureLoader.loadJSON("codex-usage") as? [String: Any])
        var decodedCount = 0

        for mutation in mutations(of: original) {
            let result = CodexUsageClient.handleUsage(
                .success(HTTPResponse(statusCode: 200, headers: [:], body: try data(mutation.json))),
                clock: { self.fetchedAt }
            )
            switch result {
            case .success(let snapshot):
                decodedCount += 1
                assertInvariants(snapshot, mutation: mutation.name)
            case .failure(let error):
                guard case .decoding = error else {
                    return XCTFail("[\(mutation.name)] erreur inattendue : \(error)")
                }
            }
        }
        XCTAssertGreaterThan(decodedCount, 10)
    }

    func testCodexWithBothWindowsClassifiesEachByItsDuration() throws {
        // Cas jamais capturé : les **deux** fenêtres présentes. Notre seule capture réelle
        // a `secondary_window: null` et une `primary_window` hebdomadaire — c'est
        // précisément la configuration qui rend le piège « primary = 5 h » invisible.
        var json = try XCTUnwrap(FixtureLoader.loadJSON("codex-usage") as? [String: Any])
        json["rate_limit"] = [
            "allowed": true,
            "limit_reached": false,
            // Volontairement dans l'ordre « inverse » de l'intuition : la 5 h en secondary.
            "primary_window": ["used_percent": 12, "limit_window_seconds": 604_800,
                               "reset_after_seconds": 500_000, "reset_at": 1_785_904_838],
            "secondary_window": ["used_percent": 77, "limit_window_seconds": 18_000,
                                 "reset_after_seconds": 3_600, "reset_at": 1_785_003_600]
        ]

        let result = CodexUsageClient.handleUsage(
            .success(HTTPResponse(statusCode: 200, headers: [:], body: try data(json))),
            clock: { self.fetchedAt }
        )
        guard case .success(let snapshot) = result else { return XCTFail("décodage échoué") }

        let session = try XCTUnwrap(snapshot.windows.first(where: { $0.windowKind == .session }))
        let weekly = try XCTUnwrap(snapshot.windows.first(where: { $0.windowKind == .weekly }))
        // Si le classement se faisait par position, la session afficherait 12 % et l'hebdo
        // 77 % : des chiffres faux, plausibles, et invisibles à l'œil.
        XCTAssertEqual(session.percent, 77, "la fenêtre de 18 000 s est la session, quelle que soit sa position")
        XCTAssertEqual(weekly.percent, 12, "la fenêtre de 604 800 s est l'hebdo, quelle que soit sa position")
    }

    func testCodexUnknownWindowDurationIsFlaggedNotGuessed() throws {
        // Une durée inconnue (un jour ? un mois ?) ne doit pas être devinée : mieux vaut
        // `.unknown` affiché comme tel qu'une fenêtre étiquetée « 5 h » à tort.
        var json = try XCTUnwrap(FixtureLoader.loadJSON("codex-usage") as? [String: Any])
        json["rate_limit"] = [
            "primary_window": ["used_percent": 30, "limit_window_seconds": 86_400,
                               "reset_after_seconds": 1_000, "reset_at": 1_785_003_600]
        ]

        let result = CodexUsageClient.handleUsage(
            .success(HTTPResponse(statusCode: 200, headers: [:], body: try data(json))),
            clock: { self.fetchedAt }
        )
        guard case .success(let snapshot) = result else { return XCTFail("décodage échoué") }
        XCTAssertEqual(snapshot.windows.first?.windowKind, .unknown)
        XCTAssertEqual(snapshot.windows.first?.windowSeconds, 86_400, "la durée brute reste lisible pour diagnostiquer")
    }

    func testCodexEpochInMillisecondsWouldBeCaughtByTheInvariants() throws {
        // Test de garde sur nos propres invariants : si un jour l'API passait `reset_at` en
        // millisecondes, la date obtenue partirait en l'an 58 000. On veut le savoir.
        var json = try XCTUnwrap(FixtureLoader.loadJSON("codex-usage") as? [String: Any])
        json["rate_limit"] = [
            "primary_window": ["used_percent": 30, "limit_window_seconds": 18_000,
                               "reset_after_seconds": 1_000, "reset_at": 1_785_003_600_000]
        ]

        let result = CodexUsageClient.handleUsage(
            .success(HTTPResponse(statusCode: 200, headers: [:], body: try data(json))),
            clock: { self.fetchedAt }
        )
        guard case .success(let snapshot) = result, let resetsAt = snapshot.windows.first?.resetsAt else {
            return XCTFail("décodage échoué")
        }
        // On documente le comportement actuel : la valeur est prise telle quelle. Ce test
        // échouera le jour où l'API changerait d'unité — ce qui est exactement le signal
        // qu'on veut, plutôt qu'un compte à rebours de 30 siècles affiché sans broncher.
        XCTAssertGreaterThan(
            resetsAt.timeIntervalSince1970, 4_102_444_800,
            "comportement documenté : aucune détection d'unité aujourd'hui — à corriger si l'API bascule en ms"
        )
    }
}
