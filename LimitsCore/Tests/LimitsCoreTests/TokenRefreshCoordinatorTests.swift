import XCTest
@testable import LimitsCore

/// Ces tests portent sur la **classification** des échecs de refresh, pas sur le
/// Keychain (indisponible de façon fiable sur un runner headless, cf. la note de tête
/// de `SharedKeychainStoreTests`) ni sur le réseau. Le point à verrouiller : une panne
/// passagère ne doit **jamais** être classée « reconnecter », sinon l'app déconnecte
/// l'utilisateur à la première erreur 500.
final class TokenRefreshCoordinatorTests: XCTestCase {
    func testClaudeTreats400And401And403AsPermanent() {
        for status in [400, 401, 403] {
            XCTAssertTrue(
                ClaudeOAuthError.httpStatus(status, endpoint: "token endpoint").isPermanentAuthFailure,
                "HTTP \(status) sur l'endpoint token = refresh token refusé"
            )
        }
    }

    func testClaudeTreatsServerAndNetworkFailuresAsTransient() {
        XCTAssertFalse(ClaudeOAuthError.httpStatus(500, endpoint: "token endpoint").isPermanentAuthFailure)
        XCTAssertFalse(ClaudeOAuthError.httpStatus(429, endpoint: "token endpoint").isPermanentAuthFailure)
        XCTAssertFalse(ClaudeOAuthError.transport(endpoint: "token endpoint").isPermanentAuthFailure)
        XCTAssertFalse(ClaudeOAuthError.decodingFailed(endpoint: "token endpoint").isPermanentAuthFailure)
    }

    func testOutcomeDistinguishesReconnectFromTransient() {
        // Garde-fou de typage : les deux cas d'échec ne doivent pas être confondables.
        XCTAssertNotEqual(TokenRefreshCoordinator.Outcome.needsReconnect, .transientFailure)
    }

    func testConcurrentRefreshesAreCoalescedIntoASingleCall() async throws {
        // Le cœur de la dette de T2.2 : deux refresh concurrents avec le même
        // refresh_token déclenchent `refresh_token_reused` côté OpenAI, qui est un échec
        // définitif. On vérifie ici la primitive de coalescence telle qu'utilisée par le
        // coordinateur — une seule exécution pour N appelants simultanés.
        let flight = SingleFlight<Int>()
        let counter = CallCounter()

        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try await flight.run {
                        await counter.increment()
                        try await Task.sleep(nanoseconds: 20_000_000)
                        return await counter.count
                    }
                }
            }
            var collected: [Int] = []
            for try await value in group { collected.append(value) }
            return collected
        }

        XCTAssertEqual(await counter.count, 1, "un seul appel réseau pour 10 appelants")
        XCTAssertEqual(Set(results).count, 1, "tous les appelants reçoivent le même résultat")
    }
}

private actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
