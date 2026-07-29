import Foundation
import UserNotifications
import LimitsCore

/// Exécute un plan de notifications produit par `LimitsCore.NotificationPlanner`.
///
/// Aucune décision ici : quoi notifier, quand, et ce qui a déjà été notifié, tout est
/// calculé dans `LimitsCore` (donc testé par `swift test`). Ce fichier n'est que la
/// plomberie `UserNotifications`, non testable sans device.
///
/// Rappel de contexte : avec une signature gratuite il n'y a **pas d'APNs** (PLAN.md
/// §5.3). Une notification locale programmée est donc le seul mécanisme qui puisse
/// prévenir l'utilisateur d'un reset alors que l'app est fermée.
enum LocalNotificationScheduler {
    /// Demande l'autorisation. Appelée au moment où l'utilisateur active réellement les
    /// alertes dans les réglages, pas au premier lancement : un prompt système présenté
    /// sans contexte se fait refuser, et un refus est difficile à rattraper.
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    /// Applique le plan. Les identifiants du plan sont stables et déterministes, donc
    /// reprogrammer un plan identique **remplace** les requêtes existantes au lieu
    /// d'empiler des doublons (`UNUserNotificationCenter` écrase à identifiant égal).
    static func apply(_ notifications: [PlannedNotification]) async {
        let center = UNUserNotificationCenter.current()

        // On ne programme rien si l'utilisateur n'a pas autorisé : inutile de remplir la
        // file d'attente système, et surtout pas de prompt surgissant depuis une tâche de
        // fond (iOS ne l'afficherait pas et l'autorisation serait consommée en refus).
        guard await authorizationStatus() == .authorized else { return }

        // Purge des resets déjà programmés mais devenus obsolètes : une fenêtre dont la
        // date de reset a bougé (session prolongée) laisserait sinon une notification
        // fantôme qui sonnerait au mauvais moment.
        let plannedIDs = Set(notifications.map(\.id))
        let pending = await center.pendingNotificationRequests()
        let obsolete = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("reset|") && !plannedIDs.contains($0) }
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
        }

        for planned in notifications {
            let content = UNMutableNotificationContent()
            content.title = planned.title
            content.body = planned.body
            content.sound = .default

            let trigger: UNNotificationTrigger?
            switch planned.trigger {
            case .immediate:
                trigger = nil
            case .at(let date):
                let interval = date.timeIntervalSinceNow
                // Une date déjà passée entre le calcul du plan et son application : on
                // laisse tomber plutôt que de sonner pour un évènement révolu.
                guard interval > 0 else { continue }
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            }

            let request = UNNotificationRequest(identifier: planned.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
