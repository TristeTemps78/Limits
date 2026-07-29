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

public enum WindowPresentation {
    public static func displayState(for window: LimitWindow, now: Date) -> WindowDisplayState {
        guard let resetsAt = window.resetsAt else { return .inactive }
        return resetsAt > now ? .counting(resetsAt: resetsAt) : .awaitingRefresh(resetsAt: resetsAt)
    }
}
