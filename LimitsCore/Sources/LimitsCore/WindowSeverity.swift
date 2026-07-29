import Foundation

/// Normalized urgency for one `LimitWindow`, the single source of truth the widget
/// color/symbol code is keyed off of (T2.3 brief: "un code couleur adossé à la
/// `severity` du modèle, pas un seuil réinventé dans la vue").
///
/// - Claude carries an explicit `limits[].severity` string (`fixtures/claude-usage.json`
///   shows `"normal"`; `spend.severity` separately shows `"critical"`). When present,
///   it is trusted as-is — a string we don't recognize maps to `.unknown`, never
///   silently reinterpreted from `percent`, because that would contradict a value the
///   source actually gave us just because it's spelled differently than expected.
/// - Codex carries no severity field at all (`fixtures/codex-usage.json`), so its
///   windows fall back to a percent threshold. That threshold is defined **once**,
///   here, reusing the exact 80 %/95 % figures PLAN.md §1 already names for
///   notification thresholds — not a value invented for this widget.
public enum WindowSeverity: String, Codable, Equatable, Sendable, CaseIterable {
    case normal
    case warning
    case critical
    /// Either no signal was available (Codex, percent below `warningPercentThreshold`
    /// is `.normal`, not `.unknown` — `.unknown` is reserved for "we got a severity
    /// string we don't recognize"), a case the view must render neutrally.
    case unknown

    public static let warningPercentThreshold: Double = 80
    public static let criticalPercentThreshold: Double = 95

    public static func classify(_ window: LimitWindow) -> WindowSeverity {
        guard let raw = window.severity else {
            return classify(percent: window.percent)
        }
        return WindowSeverity(rawValue: raw) ?? .unknown
    }

    public static func classify(percent: Double) -> WindowSeverity {
        switch percent {
        case criticalPercentThreshold...:
            return .critical
        case warningPercentThreshold..<criticalPercentThreshold:
            return .warning
        default:
            return .normal
        }
    }

    /// Higher is more urgent. Used by `WindowSelector` to pick which window headlines
    /// a single-gauge presentation; `.unknown` is deliberately ranked with `.normal`
    /// rather than treated as alarming — an unrecognized severity string is a data gap,
    /// not evidence of a problem.
    var urgencyRank: Int {
        switch self {
        case .normal, .unknown: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }
}
