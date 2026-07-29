import Foundation

/// A precomputed set of timeline entry dates plus when WidgetKit should ask for a new
/// plan. See `WidgetTimelinePlanner.plan`.
public struct WidgetTimelinePlan: Equatable, Sendable {
    public let entryDates: [Date]
    public let reloadAfter: Date

    public init(entryDates: [Date], reloadAfter: Date) {
        self.entryDates = entryDates
        self.reloadAfter = reloadAfter
    }
}

/// Chooses *when* a widget should re-render, without ever fetching anything (rule 8,
/// AGENTS.md — widgets are read-only against the App Group). Pure and testable with an
/// injected `now`, exactly like `PollingPolicy`, which this deliberately mirrors in
/// spirit though it answers a different question (`PollingPolicy` gates *network*
/// fetches the app makes; this schedules *re-renders* of data the widget already has).
///
/// Two, and only two, things justify a new timeline entry:
/// 1. A window's `resetsAt` arriving. `Text(timerInterval:)` can count down on its own,
///    but it cannot know the number it's counting down *to* is now stale — only a new
///    entry, rendered via `WindowPresentation.displayState(for:now:)`, can flip the
///    view from "counting" to "réinitialisation attendue".
/// 2. A fallback nudge (`minimumFallbackInterval`) so freshness/staleness
///    (`SnapshotFreshnessLevel`) doesn't go stale forever between app-triggered
///    `WidgetCenter.reloadAllTimelines()` calls. `Text(date, style: .relative)` handles
///    the *label* wording on its own, but the `.fresh`/`.aging`/`.stale` *banner
///    threshold* is only re-evaluated when a new entry is generated.
///
/// Never scheduled tighter than `minimumFallbackInterval` on its own initiative:
/// WidgetKit's daily refresh budget is finite and silently throttles a widget that
/// outruns it, which looks exactly like the frozen-widget bug this project exists to
/// avoid. One hour is a judgment call (~24 background reloads/day) balancing that
/// budget against how late the aging/stale banners are allowed to lag — not something
/// verifiable without a device over several days.
public enum WidgetTimelinePlanner {
    public static let minimumFallbackInterval: TimeInterval = 60 * 60

    public static func plan(snapshots: SharedUsageSnapshots?, now: Date) -> WidgetTimelinePlan {
        let fallback = now.addingTimeInterval(minimumFallbackInterval)
        guard let snapshots else {
            return WidgetTimelinePlan(entryDates: [now], reloadAfter: fallback)
        }

        // All upcoming resets due before the next fallback reload anyway — bounded to
        // at most four (session/weekly × two providers), so including every one of
        // them (not just the nearest) costs nothing and avoids a window's flip being
        // missed because a different window's reset was picked instead.
        let upcomingResets = Set(allWindows(snapshots).compactMap(\.resetsAt))
            .filter { $0 > now && $0 <= fallback }
            .sorted()

        return WidgetTimelinePlan(entryDates: [now] + upcomingResets, reloadAfter: fallback)
    }

    private static func allWindows(_ snapshots: SharedUsageSnapshots) -> [LimitWindow] {
        (snapshots.claude?.windows ?? []) + (snapshots.codex?.windows ?? [])
    }
}
