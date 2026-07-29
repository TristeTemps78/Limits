import Foundation

/// "à jour il y a X" freshness label — deliberately first-class in the T2.4 brief: a
/// monitoring app that shows a stale number as if it were current is worse than an
/// empty screen. See `AppPercentFormatter`'s doc comment for why this lives in
/// `AppPresentation/` under an `App`-prefixed name rather than somewhere Sonnet C's
/// parallel widget work might also reach for.
public enum AppFreshnessFormatter {
    public enum Bucket: Equatable, Sendable {
        case justNow
        case minutes(Int)
        case hours(Int)
        case days(Int)
    }

    /// Coarse-grained on purpose (seconds only under a minute, then minutes/hours/
    /// days) — a dashboard doesn't need "il y a 47 secondes" precision, and finer
    /// granularity would just make the label visibly tick during a session, which
    /// reads as more alarming than informative.
    public static func bucket(ageSeconds: Int) -> Bucket {
        let age = max(0, ageSeconds)
        switch age {
        case ..<60: return .justNow
        case 60..<3600: return .minutes(age / 60)
        case 3600..<86400: return .hours(age / 3600)
        default: return .days(age / 86400)
        }
    }

    public static func label(ageSeconds: Int) -> String {
        switch bucket(ageSeconds: ageSeconds) {
        case .justNow: return "à jour à l'instant"
        case .minutes(let minutes): return "à jour il y a \(minutes) min"
        case .hours(let hours): return "à jour il y a \(hours) h"
        case .days(let days): return "à jour il y a \(days) j"
        }
    }

    /// Convenience over `label(ageSeconds:)` for callers holding a `Date`/`Date`
    /// pair rather than a precomputed age.
    public static func label(fetchedAt: Date, now: Date) -> String {
        label(ageSeconds: max(0, Int(now.timeIntervalSince(fetchedAt))))
    }
}
