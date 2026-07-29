import SwiftUI

/// Entry point of the Limits app.
///
/// This is a minimal scaffold (T0.2): just enough to compile and archive in CI. The
/// real dashboard/onboarding UI lands in T2.4.
@main
struct LimitsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("Limits")
            .padding()
    }
}
