import SwiftUI

/// Entry point of the Limits app.
///
/// T2.4: the real product screens land here — dashboard + settings, with the T1.1
/// `DiagnosticsView` kept (moved into Settings) rather than removed, since the
/// Sideloadly sideload test (T1.2/gate M1) hasn't happened yet and that screen is
/// the only instrument that will answer whether the App Group survives re-signing.
@main
struct LimitsApp: App {
    @StateObject private var settings = AppSettingsStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settings)
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
