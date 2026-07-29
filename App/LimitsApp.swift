import SwiftUI

/// Entry point of the Limits app.
///
/// T1.1: the real screen here is `DiagnosticsView` — a dérisquage tool, not product
/// UI. It answers one question on Tristan's iPhone after Sideloadly re-signs the IPA:
/// do the App and the Widgets extension still share data, and through which of the
/// three channels? The real dashboard/onboarding UI lands in T2.4, once that question
/// has an answer.
@main
struct LimitsApp: App {
    var body: some Scene {
        WindowGroup {
            DiagnosticsView()
        }
    }
}
