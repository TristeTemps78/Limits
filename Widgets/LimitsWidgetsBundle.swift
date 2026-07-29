import SwiftUI
import WidgetKit

/// Entry point of the LimitsWidgets extension.
///
/// T1.1: `DiagnosticsWidget` (see `DiagnosticsWidget.swift`) reads the three shared
/// channels App Group container — it never writes, and never touches the network
/// (rule 8, AGENTS.md). Kept in the final bundle on purpose (T2.3 brief): it's the
/// instrument that lets Tristan validate the App Group survived Sideloadly's
/// re-signing (T1.2), and the IPA he sideloads is this final one, not a T1.1-only build.
///
/// T2.3: `UsageWidget` (see `UsageWidget.swift`/`UsageWidgetViews.swift`) is the real
/// product — session/weekly gauges for Claude and Codex, across every WidgetKit family.
@main
struct LimitsWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
        DiagnosticsWidget()
    }
}
