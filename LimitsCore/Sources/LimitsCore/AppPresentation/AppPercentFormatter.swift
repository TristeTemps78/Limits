import Foundation

/// Percent display formatting for the T2.4 app screens (dashboard, gauges).
///
/// Named with the `App` prefix, like every file in `AppPresentation/`, and kept in
/// this subfolder deliberately: Sonnet C is building the widget UI (`Widgets/`) in
/// parallel and may need very similar-looking formatting under very different
/// constraints (accessory-family text is far more space-constrained than a dashboard
/// row). Rather than guess at one shared formatter and risk two competing ones
/// appearing at merge time, this one is scoped and named unambiguously to the app; a
/// future unification is a deliberate call for whoever integrates both lots, not
/// something to pre-empt here.
public enum AppPercentFormatter {
    /// The API always returns 0-100 already, never a fraction (see `LimitWindow`'s
    /// doc comment in Models.swift) — this only rounds for display and defends
    /// against an out-of-range value (e.g. 100.4 from upstream float rounding)
    /// rather than showing something like "104 %".
    public static func label(percent: Double) -> String {
        let clamped = min(max(percent, 0), 100)
        return "\(Int(clamped.rounded())) %"
    }

    /// 0-1 fraction for progress-style views (`Circle().trim`, `ProgressView`, ...),
    /// clamped the same way as `label(percent:)` so the two never disagree about an
    /// out-of-range input.
    public static func fraction(percent: Double) -> Double {
        min(max(percent, 0), 100) / 100
    }
}
