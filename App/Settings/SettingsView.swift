import SwiftUI
import LimitsCore

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var notificationsAuthorized: Bool?

    var body: some View {
        NavigationStack {
            Form {
                Section("Comptes") {
                    ClaudeConnectView()
                    Divider()
                    CodexConnectView()
                }

                Section("Notifications") {
                    VStack(alignment: .leading) {
                        Text("Seuil d'alerte : \(Int(settings.warningThresholdPercent)) %")
                        Slider(value: $settings.warningThresholdPercent, in: 50...100, step: 5)
                    }
                    VStack(alignment: .leading) {
                        Text("Seuil critique : \(Int(settings.criticalThresholdPercent)) %")
                        Slider(value: $settings.criticalThresholdPercent, in: 50...100, step: 5)
                    }
                    if notificationsAuthorized == false {
                        Button("Autoriser les notifications") {
                            Task { notificationsAuthorized = await LocalNotificationScheduler.requestAuthorization() }
                        }
                        Text(
                            "Sans autorisation, aucune alerte de seuil ni de réinitialisation ne sera envoyée. " +
                            "Il n'y a pas de notification poussée : tout est programmé localement sur l'appareil."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Alertes locales aux seuils ci-dessus et à chaque réinitialisation de fenêtre.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Rafraîchissement") {
                    Stepper(
                        "Intervalle : \(settings.refreshIntervalMinutes) min",
                        value: $settings.refreshIntervalMinutes,
                        in: 15...120,
                        step: 15
                    )
                    Text("Le minimum réel entre deux rafraîchissements automatiques reste 15 min (anti-429).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Apparence") {
                    Picker("Style de jauge", selection: $settings.gaugeStyle) {
                        ForEach(GaugeStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    NavigationLink("Diagnostic App Group (T1.1)") {
                        DiagnosticsView()
                    }
                } footer: {
                    Text(
                        "Conservé pour valider le partage app/widget après re-signature Sideloadly — " +
                        "utile tant que le gate M1 n'a pas été validé sur l'iPhone."
                    )
                }
            }
            .navigationTitle("Réglages")
            .task {
                // On ne demande jamais l'autorisation au premier lancement : un prompt
                // système sans contexte se fait refuser, et un refus est difficile à
                // rattraper. On l'affiche ici, à côté des seuils qu'il sert.
                notificationsAuthorized = await LocalNotificationScheduler.authorizationStatus() == .authorized
            }
        }
    }
}
