import SwiftUI
import LimitsCore

/// App-side equivalent of `Widgets/Gauges/SeverityStyle.swift` — the coordinator
/// asked for the exact same colors/symbols so the app and the widget read as one
/// system when Tristan looks at them side by side. This can't be shared code (rule 4,
/// AGENTS.md: `LimitsCore` never imports SwiftUI), so it's duplicated by design, not
/// by oversight — keep these two files in sync if the widget's mapping ever changes.
extension WindowSeverity {
    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        case .unknown: return .gray
        }
    }

    var symbolName: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var shortLabel: String {
        switch self {
        case .normal: return "OK"
        case .warning: return "Attention"
        case .critical: return "Critique"
        case .unknown: return "?"
        }
    }
}
