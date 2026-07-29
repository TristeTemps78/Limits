import Foundation

/// The single place a usage percent (`LimitWindow.percent`, `ClaudeExtraUsage.spendPercent`,
/// etc. — all already 0-100, see PLAN.md §2.1/§2.2) is rounded and turned into display
/// text. Both the widget and the app dashboard (T2.4) show the same underlying numbers
/// side by side on the same device; if each rounded independently, a user could see 8 %
/// on the widget and 9 % on the dashboard for the identical fetch, which is exactly the
/// "wrong but plausible number" failure mode this project exists to avoid — so there is
/// exactly one rounding rule, here, not one per view.
extension Double {
    /// `self` rounded to the nearest whole percent (`.rounded()`'s default rule,
    /// `.toNearestOrAwayFromZero` — schoolbook rounding, e.g. 8.5 → "9%") and formatted
    /// as `"8%"`.
    public var roundedPercentText: String {
        "\(Int(self.rounded()))%"
    }
}
