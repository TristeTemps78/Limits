import Foundation

/// Ranks `(provider, window)` pairs by urgency — used wherever a widget family has to
/// pick which window(s) to headline: `accessoryCircular`/`accessoryInline`/`systemSmall`
/// (room for exactly one), `accessoryRectangular` (room for a short list).
public enum WindowSelector {
    public struct Selection: Equatable, Sendable {
        public let provider: ProviderKind
        public let window: LimitWindow

        public init(provider: ProviderKind, window: LimitWindow) {
            self.provider = provider
            self.window = window
        }
    }

    /// Fixed tie-break order, applied only once severity and percent are equal — keeps
    /// the ranking deterministic (and testable) rather than dependent on array order.
    private static let providerOrder: [ProviderKind] = [.claude, .codex]
    private static let windowKindOrder: [LimitWindowKind] = [.session, .weekly, .unknown]

    /// Every window across both providers, most urgent first. Ranked by severity first
    /// (a single-glance widget exists to surface the thing that needs attention, not
    /// the thing that happens to be listed first), then by percent, then the fixed
    /// tie-break order above.
    public static func ranked(in snapshots: SharedUsageSnapshots) -> [Selection] {
        let candidates =
            (snapshots.claude?.windows ?? []).map { Selection(provider: .claude, window: $0) } +
            (snapshots.codex?.windows ?? []).map { Selection(provider: .codex, window: $0) }
        return candidates.sorted(by: isMoreUrgent)
    }

    /// `nil` only when there is truly no window to show (e.g. neither provider
    /// connected).
    public static func mostUrgent(in snapshots: SharedUsageSnapshots) -> Selection? {
        ranked(in: snapshots).first
    }

    /// Strict ordering ("does `lhs` sort before `rhs`") — every tie is broken by a
    /// fixed rule, so two candidates only ever compare equal (return `false` both ways)
    /// when they're the same provider and window kind, which `Array.sorted` handles
    /// correctly as "either order is fine".
    private static func isMoreUrgent(_ lhs: Selection, _ rhs: Selection) -> Bool {
        let l = WindowSeverity.classify(lhs.window)
        let r = WindowSeverity.classify(rhs.window)
        if l.urgencyRank != r.urgencyRank {
            return l.urgencyRank > r.urgencyRank
        }
        if lhs.window.percent != rhs.window.percent {
            return lhs.window.percent > rhs.window.percent
        }
        let lp = providerOrder.firstIndex(of: lhs.provider) ?? providerOrder.count
        let rp = providerOrder.firstIndex(of: rhs.provider) ?? providerOrder.count
        if lp != rp { return lp < rp }
        let lk = windowKindOrder.firstIndex(of: lhs.window.windowKind) ?? windowKindOrder.count
        let rk = windowKindOrder.firstIndex(of: rhs.window.windowKind) ?? windowKindOrder.count
        return lk < rk
    }
}
