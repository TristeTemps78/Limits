import XCTest
@testable import LimitsCore

final class UnexpectedPayloadDetectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_785_000_000)

    func testSnapshotWithWindowsIsUsable() {
        let snapshot = UsageSnapshot(
            provider: .claude,
            fetchedAt: now,
            windows: [LimitWindow(windowKind: .weekly, percent: 8)]
        )
        XCTAssertEqual(UnexpectedPayloadDetector.health(of: snapshot), .usable)
    }

    func testSnapshotWithNoWindowAtAllIsFlaggedAsUnexpectedShape() {
        // Le scénario réel : le provider renomme `limits`. Le décodage réussit, le snapshot
        // est vide, et sans ce signal l'app dirait « aucune donnée » — ce que l'utilisateur
        // lirait comme « ma connexion est cassée ».
        let snapshot = UsageSnapshot(provider: .claude, fetchedAt: now, windows: [])
        XCTAssertEqual(UnexpectedPayloadDetector.health(of: snapshot), .unexpectedShape)
    }

    func testClaudeWithOnlyExtraUsageIsStillUsable() {
        // Un compte peut légitimement n'avoir aucune fenêtre mais des crédits : ne pas
        // hurler au format cassé dans ce cas.
        let snapshot = UsageSnapshot(
            provider: .claude,
            fetchedAt: now,
            windows: [],
            extraUsage: ClaudeExtraUsage(isEnabled: false, monthlyLimit: 16_000)
        )
        XCTAssertEqual(UnexpectedPayloadDetector.health(of: snapshot), .usable)
    }

    func testCodexWithOnlyResetCreditsIsStillUsable() {
        let snapshot = UsageSnapshot(
            provider: .codex,
            fetchedAt: now,
            windows: [],
            resetCredits: ResetCredit(availableCount: 0, totalEarnedCount: 0, creditCount: 0)
        )
        XCTAssertEqual(UnexpectedPayloadDetector.health(of: snapshot), .usable)
    }

    func testMessageTellsTheUserNotToReconnect() {
        // Le contresens que ce détecteur existe pour éviter : envoyer l'utilisateur refaire
        // un login qui réussira sans rien réparer.
        let message = UnexpectedPayloadDetector.userFacingMessage(for: .codex)
        XCTAssertTrue(message.contains("Codex"))
        XCTAssertTrue(message.lowercased().contains("inutile de te reconnecter"))
        // Et surtout, aucun détail technique de la réponse (règle 6 d'AGENTS.md).
        XCTAssertFalse(message.contains("{"))
    }

    func testRealFixtureIsUsableSoTheDetectorDoesNotCryWolf() throws {
        // Garde-fou : le détecteur ne doit pas signaler un faux positif sur la vraie
        // réponse d'aujourd'hui, sinon il serait ignoré le jour où il a raison.
        let data = try FixtureLoader.load("claude-usage")
        let result = ClaudeUsageClient.handle(
            .success(HTTPResponse(statusCode: 200, headers: [:], body: data)),
            clock: { self.now }
        )
        guard case .success(let snapshot) = result else { return XCTFail("fixture non décodée") }
        XCTAssertEqual(UnexpectedPayloadDetector.health(of: snapshot), .usable)
    }
}
