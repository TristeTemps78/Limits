import SwiftUI
import LimitsCore

/// Renders `WindowPresentation.displayState(for:now:)` as text, handling all three
/// states explicitly (T2.3 brief: `resets_at: null` is "inactive", not an error; a past
/// `resets_at` must read as "réinitialisation attendue", never a frozen/negative
/// countdown — see `WindowDisplayState.awaitingRefresh`'s doc comment for why
/// `Text(timerInterval:)` alone can't distinguish those on its own).
///
/// Both `Text(timerInterval:)` and `Text(_:style: .relative)` update live, on-device,
/// without spending any timeline-reload budget — this is the one piece of UI in the
/// whole widget that must never be recomputed on a schedule; `WidgetTimelinePlanner`
/// only schedules a new entry for the *transition* into `.awaitingRefresh`, not to tick
/// the countdown itself. Which of the two styles is used for a `.counting` window is a
/// legibility choice (`WindowPresentation.countdownRenderStyle`), not a cost trade-off.
///
/// Exposed as a static `Text`-returning function (`countdownText`) as well as a `View`
/// wrapper, so `accessoryInline` — which has room for exactly one line and needs to
/// concatenate this with other `Text` via `+` — can use the same logic as every other
/// family instead of a second, separately-maintained implementation.
enum ResetCountdown {
    static func text(for window: LimitWindow, now: Date) -> Text {
        switch WindowPresentation.displayState(for: window, now: now) {
        case .inactive:
            return Text("inactif")
        case .counting(let resetsAt):
            // Both branches are native, auto-updating `Text` styles — neither costs a
            // timeline entry. `WindowPresentation.countdownRenderStyle` picks based on
            // legibility, not budget: precise (mm:ss-accurate) makes sense for a
            // window closing soon, but degrades to an unreadable "144:00:00" for a
            // multi-day wait, where "dans 6 j" (`.relative`) is what a glance needs.
            switch WindowPresentation.countdownRenderStyle(resetsAt: resetsAt, now: now) {
            case .precise:
                return Text(timerInterval: now...resetsAt, countsDown: true)
            case .relative:
                return Text(resetsAt, style: .relative)
            }
        case .awaitingRefresh:
            return Text("réinitialisation attendue")
        }
    }
}

struct ResetCountdownText: View {
    let window: LimitWindow
    let now: Date

    var body: some View {
        ResetCountdown.text(for: window, now: now)
    }
}
