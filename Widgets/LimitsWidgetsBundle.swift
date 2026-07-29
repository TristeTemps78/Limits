import SwiftUI
import WidgetKit

/// Entry point of the LimitsWidgets extension.
///
/// T1.1: `DiagnosticsWidget` (see `DiagnosticsWidget.swift`) reads the three shared
/// channels App Group container — it never writes, and never touches the network
/// (rule 8, AGENTS.md). The real gauge widgets land in T2.3, once T1.1 has proven
/// which sharing channel (if any) survives Sideloadly's re-signing.
@main
struct LimitsWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DiagnosticsWidget()
    }
}
