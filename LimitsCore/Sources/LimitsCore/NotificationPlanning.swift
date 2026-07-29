import Foundation

/// Décide **quelles** notifications locales programmer, sans jamais toucher à
/// `UserNotifications` : c'est de la logique pure, donc testable par `swift test`
/// (règle 4 d'AGENTS.md). La couche app se contente d'exécuter le plan produit ici.
///
/// Deux familles, qui ne se déclenchent pas du tout de la même façon :
///
/// - **Reset de fenêtre** : programmée *à l'avance*, à la date `resetsAt`. C'est la
///   seule qui peut arriver alors que l'app n'a pas tourné depuis longtemps — sans
///   APNs (signature gratuite, cf. PLAN.md §5.3) une notification locale programmée
///   est le seul mécanisme qui survit à l'app fermée.
/// - **Franchissement de seuil** (80 % / 95 %) : ne peut être constatée qu'au moment
///   du fetch, donc envoyée immédiatement. Elle exige un **journal** persistant :
///   sans lui, chaque rafraîchissement en arrière-plan re-notifierait le même 85 %
///   toutes les 15 minutes.
public enum PlannedNotificationTrigger: Equatable, Sendable {
    /// À envoyer tout de suite (franchissement constaté au fetch).
    case immediate
    /// À programmer pour cette date (reset de fenêtre à venir).
    case at(Date)
}

public struct PlannedNotification: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    public let trigger: PlannedNotificationTrigger

    public init(id: String, title: String, body: String, trigger: PlannedNotificationTrigger) {
        self.id = id
        self.title = title
        self.body = body
        self.trigger = trigger
    }
}

/// Mémoire de ce qui a déjà été notifié, persistée entre deux exécutions (y compris
/// entre un rafraîchissement en arrière-plan et l'ouverture de l'app).
///
/// La clé est `provider|windowKind`, et l'entrée retient **à quelle fenêtre** elle se
/// rapporte (`windowResetsAt`). C'est le point subtil : quand une fenêtre se
/// réinitialise, `resetsAt` change, et il faut alors **oublier** les seuils déjà
/// notifiés — sinon l'utilisateur ne serait plus jamais averti après le premier cycle.
/// À l'inverse, tant que la fenêtre est la même, un seuil déjà franchi ne doit plus
/// jamais re-notifier.
public struct NotificationLedger: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        /// Identité de la fenêtre à laquelle ces seuils se rapportent. `nil` = fenêtre
        /// inactive (Claude sans session en cours) : traité comme une identité à part
        /// entière, pas comme « inconnu ».
        public var windowResetsAt: Date?
        /// Seuils déjà notifiés pour cette fenêtre, en points de pourcentage entiers.
        public var notifiedThresholds: Set<Int>

        public init(windowResetsAt: Date?, notifiedThresholds: Set<Int>) {
            self.windowResetsAt = windowResetsAt
            self.notifiedThresholds = notifiedThresholds
        }
    }

    public var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    public static func key(provider: ProviderKind, windowKind: LimitWindowKind) -> String {
        "\(provider.rawValue)|\(windowKind.rawValue)"
    }
}

public enum NotificationPlanner {
    /// Seuils par défaut (PLAN.md §1 : « 80 % / 95 %, configurable »).
    public static let defaultThresholds: [Double] = [80, 95]

    /// Produit le plan **et** le journal mis à jour. L'appelant doit persister le
    /// journal retourné : ne pas le faire transformerait chaque rafraîchissement en
    /// rappel du même seuil.
    ///
    /// - Parameters:
    ///   - snapshots: dernier état connu des deux providers.
    ///   - thresholds: seuils en pourcents 0-100 (les valeurs hors ]0, 100] sont ignorées).
    ///   - ledger: journal précédent.
    ///   - now: horloge injectée (aucun `Date()` en dur ici, cf. `PollingPolicy`).
    public static func plan(
        snapshots: SharedUsageSnapshots,
        thresholds: [Double] = defaultThresholds,
        ledger: NotificationLedger,
        now: Date
    ) -> (notifications: [PlannedNotification], ledger: NotificationLedger) {
        var updatedLedger = ledger
        var planned: [PlannedNotification] = []

        let sanitizedThresholds = thresholds
            .map { Int($0.rounded()) }
            .filter { $0 > 0 && $0 <= 100 }
            .sorted()

        for snapshot in [snapshots.claude, snapshots.codex].compactMap({ $0 }) {
            for window in snapshot.windows {
                planned.append(contentsOf: resetNotifications(for: window, provider: snapshot.provider, now: now))
                let crossings = thresholdNotifications(
                    for: window,
                    provider: snapshot.provider,
                    thresholds: sanitizedThresholds,
                    ledger: &updatedLedger
                )
                planned.append(contentsOf: crossings)
            }
        }

        return (planned, updatedLedger)
    }

    // MARK: - Reset

    private static func resetNotifications(
        for window: LimitWindow,
        provider: ProviderKind,
        now: Date
    ) -> [PlannedNotification] {
        // Une fenêtre inactive n'a pas de reset à annoncer, et un `resetsAt` déjà passé
        // ne doit pas produire une notification « en retard » au prochain lancement :
        // l'utilisateur recevrait une alerte pour un évènement vieux de plusieurs jours.
        guard let resetsAt = window.resetsAt, resetsAt > now else { return [] }

        // L'identifiant embarque la date : reprogrammer le même plan est idempotent
        // (`UNUserNotificationCenter` remplace une requête de même identifiant), et une
        // fenêtre qui se décale produit un nouvel identifiant plutôt qu'un doublon.
        let id = "reset|\(provider.rawValue)|\(window.windowKind.rawValue)|\(Int(resetsAt.timeIntervalSince1970))"
        return [
            PlannedNotification(
                id: id,
                title: "\(provider.displayName) — limite réinitialisée",
                body: "Ta fenêtre « \(window.windowKind.displayName) » repart de zéro.",
                trigger: .at(resetsAt)
            )
        ]
    }

    // MARK: - Seuils

    private static func thresholdNotifications(
        for window: LimitWindow,
        provider: ProviderKind,
        thresholds: [Int],
        ledger: inout NotificationLedger
    ) -> [PlannedNotification] {
        let key = NotificationLedger.key(provider: provider, windowKind: window.windowKind)
        var entry = ledger.entries[key] ?? NotificationLedger.Entry(windowResetsAt: window.resetsAt, notifiedThresholds: [])

        // La fenêtre a changé d'identité → nouveau cycle, on oublie les seuils notifiés.
        if entry.windowResetsAt != window.resetsAt {
            entry = NotificationLedger.Entry(windowResetsAt: window.resetsAt, notifiedThresholds: [])
        }

        let percent = Int(window.percent.rounded())
        // On ne notifie que le seuil le **plus élevé** franchi et non encore notifié :
        // passer de 40 % à 96 % d'un coup (une longue session entre deux fetchs) doit
        // donner une alerte « 95 % », pas deux notifications empilées.
        let crossed = thresholds.filter { percent >= $0 && !entry.notifiedThresholds.contains($0) }
        defer { ledger.entries[key] = entry }

        guard let highest = crossed.max() else { return [] }

        // Tous les seuils franchis sont marqués, y compris ceux qu'on n'annonce pas,
        // pour ne pas les ré-annoncer au fetch suivant.
        for threshold in crossed {
            entry.notifiedThresholds.insert(threshold)
        }

        return [
            PlannedNotification(
                id: "threshold|\(provider.rawValue)|\(window.windowKind.rawValue)|\(highest)",
                title: "\(provider.displayName) — \(highest) % atteint",
                body: "Fenêtre « \(window.windowKind.displayName) » à \(percent.description) %.",
                trigger: .immediate
            )
        ]
    }
}
