import SwiftUI
import LimitsCore

/// Maps `LimitsCore.WindowSeverity` (the classification, computed once in Core off the
/// model's own `severity` field or, for Codex, the shared 80/95 percent thresholds — see
/// `WindowSeverity.classify`) to color/symbol/label. This file is the *only* place a
/// color is chosen from a severity; nothing downstream re-derives severity from a raw
/// percent (T2.3 brief: "un code couleur adossé à la `severity` du modèle, pas un seuil
/// réinventé dans la vue").
///
/// Lock-screen `accessory*` families render in `.accented`/`.vibrant` mode, where the
/// system overrides `color` entirely — so `symbolName`/`shortLabel` exist as the
/// non-chromatic redundancy those families must fall back to (shape/text, not color).
extension WindowSeverity {
    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        case .unknown: return .gray
        }
    }

    /// SF Symbol conveying the same urgency as `color`, still legible once
    /// `accessory*` families strip color in vibrant/accented rendering mode.
    var symbolName: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Short French word, the textual half of the non-chromatic redundancy — used
    /// where a symbol alone might be ambiguous at accessory sizes.
    var shortLabel: String {
        switch self {
        case .normal: return "OK"
        case .warning: return "Attention"
        case .critical: return "Critique"
        case .unknown: return "?"
        }
    }
}
