import Foundation

/// Tolerant ISO 8601 parsing for Claude's `resets_at` timestamps.
///
/// `fixtures/claude-usage.json` (a real, captured response) contains
/// `"2026-08-04T17:59:59.981775+00:00"` — **6** fractional-second digits.
/// `ISO8601DateFormatter` with `.withFractionalSeconds` is documented and known to be
/// inconsistent across OS versions about how many fractional digits it accepts; some
/// versions expect exactly 3. Rather than discover that gap on-device, this degrades
/// through three attempts before giving up: parse as-is, retry with the fractional
/// part truncated to 3 digits (millisecond precision, still exact to the second),
/// then retry with the fractional part stripped entirely (second precision). A date
/// truncated to millisecond or second precision is a fine "resets in ~X" countdown;
/// returning `nil` and hiding the whole window is not.
enum FlexibleISO8601 {
    private static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ string: String) -> Date? {
        if let date = withFractionalSeconds.date(from: string) {
            return date
        }
        if let normalized = normalizingFractionalDigits(string, to: 3),
           let date = withFractionalSeconds.date(from: normalized) {
            return date
        }
        // Covers both: a string that never had fractional seconds to begin with (no
        // "." at all — `strippingFractionalSeconds` would find nothing to strip and
        // bail early), and a defensive fallback in case the fractional-aware
        // formatter rejects the input for some other reason.
        if let date = withoutFractionalSeconds.date(from: string) {
            return date
        }
        if let stripped = strippingFractionalSeconds(string),
           let date = withoutFractionalSeconds.date(from: stripped) {
            return date
        }
        return nil
    }

    /// Truncates the fractional-seconds digits (the run of digits right after the
    /// first `.`) to `digits` characters. Returns `nil` if there's no fractional part
    /// or it's already that short (nothing to retry with).
    private static func normalizingFractionalDigits(_ string: String, to digits: Int) -> String? {
        guard let dotIndex = string.firstIndex(of: ".") else { return nil }
        let afterDot = string.index(after: dotIndex)
        var end = afterDot
        while end < string.endIndex, string[end].isNumber {
            end = string.index(after: end)
        }
        let fractional = string[afterDot..<end]
        guard fractional.count > digits else { return nil }
        let truncated = fractional.prefix(digits)
        var result = string
        result.replaceSubrange(afterDot..<end, with: truncated)
        return result
    }

    /// Removes the `.` and every digit that follows it, up to (not including) the
    /// timezone suffix. Returns `nil` if there's no fractional part to strip.
    private static func strippingFractionalSeconds(_ string: String) -> String? {
        guard let dotIndex = string.firstIndex(of: ".") else { return nil }
        var end = dotIndex
        var probe = string.index(after: dotIndex)
        while probe < string.endIndex, string[probe].isNumber {
            end = probe
            probe = string.index(after: probe)
        }
        var result = string
        result.removeSubrange(dotIndex...end)
        return result
    }
}
