import Foundation

/// What a widget should render for one `LimitWindow`'s reset countdown, given "now".
/// Pure and testable so the view never has to compare dates itself — it just switches
/// on this.
public enum WindowDisplayState: Equatable, Sendable {
    /// `resetsAt == nil`: no active session (Claude) — not an error, render "inactif",
    /// no countdown at all.
    case inactive
    /// `resetsAt` is still ahead of `now` — safe to hand to `Text(timerInterval:)`.
    case counting(resetsAt: Date)
    /// `resetsAt` is behind `now`. This is the **normal** state of a widget that
    /// hasn't been re-rendered since the window's real reset moment passed — the app
    /// hasn't re-fetched yet, so the percent value on screen is now stale relative to
    /// what the provider would report. `Text(timerInterval:)` given a past
    /// `resetsAt` as its upper bound does not count into negative numbers; it freezes
    /// on the end-of-range formatting, which reads as "stuck", not "reset". This case
    /// exists so the view shows an explicit "réinitialisation attendue" state instead.
    case awaitingRefresh(resetsAt: Date)
}

/// Which native, auto-updating `Text` style to hand a `.counting` window's `resetsAt`
/// to. Both styles are equally free in WidgetKit's refresh-budget terms — neither
/// spends a timeline entry, both update on-device — so this is purely a legibility
/// choice, not a cost/precision trade-off.
public enum CountdownRenderStyle: Equatable, Sendable {
    /// `Text(timerInterval:)` — second-accurate, but degrades to a long hour count
    /// (e.g. "144:00:00") past a day or so with no documented day-granularity mode.
    /// Meaningful precision on a window closing within the next 24h.
    case precise
    /// `Text(_:style: .relative)` — reads as "dans 6 j", the right grain once the
    /// reset is more than a day out.
    case relative
}

public enum WindowPresentation {
    public static func displayState(for window: LimitWindow, now: Date) -> WindowDisplayState {
        guard let resetsAt = window.resetsAt else { return .inactive }
        return resetsAt > now ? .counting(resetsAt: resetsAt) : .awaitingRefresh(resetsAt: resetsAt)
    }

    /// The threshold between the two `CountdownRenderStyle`s.
    public static let preciseCountdownHorizon: TimeInterval = 24 * 60 * 60

    /// Only meaningful for a `resetsAt` that's still ahead of `now` (a `.counting`
    /// state) — callers in `.awaitingRefresh`/`.inactive` never reach this.
    /// `>= preciseCountdownHorizon` (not `>`) resolves the boundary the same way
    /// `SnapshotFreshness.level` does: the threshold instant itself already counts as
    /// the coarser bucket.
    public static func countdownRenderStyle(resetsAt: Date, now: Date) -> CountdownRenderStyle {
        resetsAt.timeIntervalSince(now) >= preciseCountdownHorizon ? .relative : .precise
    }
}
