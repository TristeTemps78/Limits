import Foundation
import BackgroundTasks

/// Enregistrement et replanification de la `BGAppRefreshTask`.
///
/// L'identifiant doit **aussi** figurer dans `BGTaskSchedulerPermittedIdentifiers` de
/// l'`Info.plist`, sinon `register` lève une exception au lancement (PLAN.md §4).
///
/// iOS déclenche ces tâches de façon **opportuniste** : de ~15 minutes à plusieurs heures
/// selon l'usage de l'app, la batterie et le réseau. C'est suffisant ici — les widgets
/// affichent l'âge de la donnée et les comptes à rebours défilent tout seuls, et
/// l'ouverture de l'app force de toute façon un fetch.
enum BackgroundRefresh {
    /// Doit rester synchronisé avec `BGTaskSchedulerPermittedIdentifiers` (App/Info.plist).
    static let taskIdentifier = "com.caldf.limitsapp.refresh"

    /// À appeler **une seule fois**, au lancement, avant la fin de
    /// `application(_:didFinishLaunchingWithOptions:)` — iOS l'exige.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Replanifie systématiquement : une `BGAppRefreshTask` est **à usage unique**, ne pas
    /// la replanifier à la fin de son exécution arrêterait définitivement les
    /// rafraîchissements de fond — panne silencieuse classique.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // Aligné sur le minimum de `PollingPolicy` (15 min) : demander plus tôt ne
        // servirait à rien, la politique refuserait le fetch et on aurait consommé un
        // réveil pour rien.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Replanifier **d'abord** : si le travail dépasse le budget alloué et qu'iOS nous
        // tue, la prochaine occurrence est déjà en file.
        schedule()

        let work = Task {
            let success = await RefreshManager().runScheduledRefresh()
            task.setTaskCompleted(success: success)
        }

        // iOS accorde quelques dizaines de secondes puis appelle ce handler. Annuler
        // proprement évite d'être pénalisé sur les réveils suivants.
        task.expirationHandler = {
            work.cancel()
        }
    }
}
