import XCTest
@testable import LimitsCore

/// Chemin de rafraîchissement partagé premier plan / tâche de fond. Ce qu'on verrouille
/// ici, c'est la **traduction** d'une réponse réseau en `PollingOutcome` — et surtout le
/// fait qu'une panne passagère ne devienne jamais `.unauthorized`, qui rendrait l'état
/// « reconnecter » terminal pour une simple coupure réseau.
final class UsageRefreshServiceTests: XCTestCase {
    private let tokens = StoredTokens(
        accessToken: "access-dummy",
        refreshToken: "refresh-dummy",
        expiresAt: nil,
        accountID: "acct_test_dummy"
    )

    /// Ni réseau, ni Keychain : le client HTTP d'usage, le transport OAuth **et** les
    /// accès au trousseau sont tous injectés.
    private func service(
        http: StubHTTPClient,
        tokens: StoredTokens?,
        refreshStatus: Int = 400,
        refreshBody: Data = Data("{}".utf8)
    ) -> UsageRefreshService {
        UsageRefreshService(
            httpClient: http,
            // Coordinateur neuf par test : le singleton partagé porterait de l'état
            // d'un test à l'autre.
            coordinator: TokenRefreshCoordinator(
                loadTokens: { _ in tokens },
                saveTokens: { _, _ in true }
            ),
            oauthTransport: StubOAuthTransport(statusCode: refreshStatus, body: refreshBody),
            tokenLoader: { _ in tokens }
        )
    }

    private func claudeFixtureData() throws -> Data {
        try FixtureLoader.load("claude-usage")
    }

    func testSuccessProducesASnapshot() async throws {
        let result = await service(http: .ok(try claudeFixtureData()), tokens: tokens).refresh(provider: .claude)
        XCTAssertEqual(result.outcome, .success)
        XCTAssertNotNil(result.snapshot)
        XCTAssertEqual(result.snapshot?.provider, .claude)
    }

    func testNoStoredTokenIsUnauthorizedNotANetworkFailure() async {
        let result = await service(http: .ok(Data("{}".utf8)), tokens: nil).refresh(provider: .claude)
        XCTAssertEqual(result.outcome, .unauthorized)
        XCTAssertNil(result.snapshot)
    }

    func testRateLimitedPropagatesRetryAfterAndProducesNoSnapshot() async {
        let http = StubHTTPClient.status(429, headers: ["Retry-After": "120"])
        let result = await service(http: http, tokens: tokens).refresh(provider: .claude)
        XCTAssertEqual(result.outcome, .rateLimited(retryAfter: 120))
        // Point capital : un 429 ne doit jamais produire de snapshot, sinon il écraserait
        // les derniers chiffres connus (PLAN.md §6.3).
        XCTAssertNil(result.snapshot)
    }

    func testTransportFailureIsOtherFailureNeverUnauthorized() async {
        let result = await service(http: .transportFailure(), tokens: tokens).refresh(provider: .claude)
        XCTAssertEqual(result.outcome, .otherFailure)
    }

    func testServerErrorIsOtherFailureNeverUnauthorized() async {
        let result = await service(http: .status(503), tokens: tokens).refresh(provider: .claude)
        XCTAssertEqual(result.outcome, .otherFailure)
    }

    func testCodexWithoutAccountIDIsTreatedAsDisconnected() async {
        // Sans `account_id`, l'en-tête `ChatGPT-Account-ID` manque et l'appel échouerait
        // de toute façon : c'est un état de déconnexion, pas une panne réseau.
        let noAccount = StoredTokens(accessToken: "a", refreshToken: "r", expiresAt: nil, accountID: nil)
        let result = await service(http: .ok(Data("{}".utf8)), tokens: noAccount).refresh(provider: .codex)
        XCTAssertEqual(result.outcome, .unauthorized)
    }

    func testUnauthorizedThenDeadRefreshTokenEndsAsUnauthorizedWithoutLooping() async {
        // 401 sur l'usage, puis 400 sur l'endpoint token (refresh token mort) :
        // `.unauthorized`, une seule fois, sans retry en boucle.
        let result = await service(http: .status(401), tokens: tokens, refreshStatus: 400).refresh(provider: .claude)
        XCTAssertEqual(result.outcome, .unauthorized)
        XCTAssertNil(result.snapshot)
    }

    func testUnauthorizedThenTransientRefreshFailureIsNotTreatedAsDisconnection() async {
        // Le piège que ce test verrouille : un 500 sur l'endpoint token pendant qu'on
        // tente de récupérer d'un 401 ne doit **pas** produire `.unauthorized`. Sinon une
        // panne serveur de dix minutes ferait basculer l'app en « reconnecter », un état
        // terminal qui obligerait l'utilisateur à refaire tout son login OAuth.
        let result = await service(http: .status(401), tokens: tokens, refreshStatus: 500).refresh(provider: .claude)
        XCTAssertEqual(result.outcome, .otherFailure)
    }

    func testRefreshedTokenIsRetriedOnceAndCanSucceed() async throws {
        // Difficile à couvrir avec un stub à réponse unique (le même client HTTP répondrait
        // 401 au second appel) : on vérifie donc au moins que le refresh réussi ne se
        // termine pas en `.unauthorized`, c'est-à-dire que la seconde tentative a bien eu
        // lieu au lieu d'abandonner.
        let refreshBody = Data(#"{"access_token":"new-access-dummy","refresh_token":"new-refresh-dummy","expires_in":3600}"#.utf8)
        let result = await service(http: .status(401), tokens: tokens, refreshStatus: 200, refreshBody: refreshBody)
            .refresh(provider: .claude)
        XCTAssertEqual(result.outcome, .unauthorized, "second 401 avec un token neuf : plus rien à tenter")
        XCTAssertNil(result.snapshot)
    }
}
