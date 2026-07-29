import SwiftUI

/// Entry point of the Limits app.
///
/// T2.4: the real product screens land here — dashboard + settings, with the T1.1
/// `DiagnosticsView` kept (moved into Settings) rather than removed, since the
/// Sideloadly sideload test (T1.2/gate M1) hasn't happened yet and that screen is
/// the only instrument that will answer whether the App Group survives re-signing.
///
/// T3.1 : la `BGAppRefreshTask` est enregistrée dans `init()` — iOS exige que
/// l'enregistrement soit fait avant la fin du lancement, donc pas depuis un `.task` de
/// vue, qui s'exécuterait trop tard. Elle est (re)planifiée à chaque passage en
/// arrière-plan, seul moment où l'on sait que l'app ne rafraîchira plus au premier plan.
@main
struct LimitsApp: App {
    @StateObject private var settings = AppSettingsStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settings)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                BackgroundRefresh.schedule()
            }
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.50percent")
                }

            SettingsView()
                .tabItem {
                    Label("Réglages", systemImage: "gearshape")
                }
        }
    }
}
