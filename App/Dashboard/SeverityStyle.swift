import SwiftUI
import LimitsCore

/// Seule la **couleur** est dupliquée entre l'app et le widget : `SwiftUI.Color` ne peut
/// pas descendre dans `LimitsCore` (règle 4 d'AGENTS.md). Le symbole SF et le mot court,
/// eux, sont des `String` et vivent désormais dans `LimitsCore.SeverityIconography` —
/// partagés, donc impossibles à faire diverger. Ce sont précisément eux qui portent
/// l'information quand iOS écrase les couleurs sur l'écran verrouillé.
extension WindowSeverity {
    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        case .unknown: return .gray
        }
    }
}
