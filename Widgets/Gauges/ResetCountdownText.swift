import SwiftUI
import LimitsCore

/// Renders `WindowPresentation.displayState(for:now:)` as text, handling all three
/// states explicitly (T2.3 brief: `resets_at: null` is "inactive", not an error; a past
/// `resets_at` must read as "réinitialisation attendue", never a frozen/negative
/// countdown — see `WindowDisplayState.awaitingRefresh`'s doc comment for why
/// `Text(timerInterval:)` alone can't distinguish those on its own).
///
/// `Text(timerInterval:)` updates live, on-device, without spending any timeline-reload
/// budget — this is the one piece of UI in the whole widget that must never be
/// recomputed on a schedule; `WidgetTimelinePlanner` only schedules a new entry for the
/// *transition* into `.awaitingRefresh`, not to tick the countdown itself.
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
            // Displays hours:minutes:seconds and counts down live; for a multi-day
            // weekly window this reads as a large hour count (e.g. "144:00:00")
            // rather than "6j" — a known `Text(timerInterval:)` formatting quirk with
            // no documented day-granularity mode, only verifiable by eye on-device.
            return Text(timerInterval: now...resetsAt, countsDown: true)
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
