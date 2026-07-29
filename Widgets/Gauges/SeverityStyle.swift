import SwiftUI
import LimitsCore

/// Seule la **couleur** vit ici : le symbole SF et le mot court sont partagés avec l'app
/// via `LimitsCore.SeverityIconography` (ce sont des `String`, rien n'obligeait à les
/// dupliquer — et ce sont eux qui portent l'information en rendu `accented`/`vibrant`,
/// où la couleur est écrasée par le système).
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
