import Foundation

/// Détecte le **mode de défaillance silencieux du parsing tolérant**.
///
/// La règle 3 d'AGENTS.md impose un parsing tolérant : clé inconnue ignorée, jamais de
/// crash. C'est le bon choix — mais il a une contrepartie que rien ne surveillait. Si un
/// provider **renomme** ses champs (`limits` → `usage_limits`, `rate_limit` → autre
/// chose), le décodage réussit toujours : il produit simplement un `UsageSnapshot` avec
/// **zéro fenêtre**. L'app affiche alors « aucune donnée », l'utilisateur en conclut que
/// sa connexion est cassée, retente un login, et le login réussit sans rien changer.
/// Autrement dit : la panne la plus probable de ce projet à moyen terme se présenterait
/// sous la forme d'un problème de connexion, en envoyant chercher exactement là où il
/// n'y a rien.
///
/// Ce type sépare donc trois situations que « aucune donnée » confondait :
/// - **pas connecté** : aucun token, rien à afficher, l'utilisateur doit se connecter ;
/// - **réponse inattendue** : appel HTTP 200, décodage réussi, mais aucune fenêtre
///   exploitable → ce n'est pas à l'utilisateur d'agir, c'est le format qui a bougé et
///   les fixtures sont à régénérer (`scripts/capture-fixtures.ps1`) ;
/// - **données normales**.
///
/// Aucune donnée sensible n'est exposée : on ne remonte qu'un état, jamais le corps de la
/// réponse (règle 6).
public enum PayloadHealth: Equatable, Sendable {
    /// Au moins une fenêtre exploitable a été trouvée.
    case usable
    /// 200 + décodage réussi, mais aucune fenêtre : le format a probablement changé.
    case unexpectedShape
}

public enum UnexpectedPayloadDetector {
    /// Un snapshot obtenu d'un appel réussi mais **sans aucune fenêtre** est suspect.
    ///
    /// Nuance importante : pour Claude, `extra_usage`/`spend` peuvent être présents sans
    /// aucune fenêtre sur un compte particulier ; on ne crie donc pas au format cassé si
    /// une autre donnée exploitable est là.
    public static func health(of snapshot: UsageSnapshot) -> PayloadHealth {
        if !snapshot.windows.isEmpty { return .usable }
        if snapshot.extraUsage != nil { return .usable }
        if snapshot.resetCredits != nil { return .usable }
        return .unexpectedShape
    }

    /// Message destiné à l'utilisateur. Il dit explicitement de **ne pas** se reconnecter :
    /// c'est le contresens que ce détecteur existe pour éviter.
    public static func userFacingMessage(for provider: ProviderKind) -> String {
        "\(provider.displayName) a répondu, mais dans un format inattendu — inutile de te "
            + "reconnecter. L'API a probablement changé : régénère les fixtures et mets l'app à jour."
    }
}
