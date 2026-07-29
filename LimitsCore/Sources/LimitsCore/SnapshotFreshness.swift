import Foundation

/// How stale `SharedUsageSnapshots.updatedAt` is, relative to "now". Drives the widget's
/// "données périmées" placeholder: PLAN.md §6 says the last snapshot must always stay
/// visible, but a widget that quietly shows a week-old percent as if it were current is
/// exactly the "wrong but plausible number" failure mode this project exists to avoid —
/// so staleness gets an explicit, escalating signal instead of just a relative label.
public enum SnapshotFreshnessLevel: Equatable, Sendable {
    /// Within one scheduled-fetch interval of expected — nothing to call out.
    case fresh
    /// Late enough that the next scheduled fetch (`PollingPolicy`, every 15 min) has
    /// clearly been missed at least once. Still just informational.
    case aging
    /// Hours stale — the background refresh loop is very likely not running at all
    /// (app backgrounded/killed, `BGAppRefreshTask` never granted, Sideloadly's 7-day
    /// certificate lapsed...). Worth a visible banner, not just a quiet label.
    case stale
}

public enum SnapshotFreshness {
    /// Twice `PollingPolicy.minimumScheduledInterval`: `BGAppRefreshTask` timing is
    /// opportunistic, not exact, so one missed cycle shouldn't itself read as "aging" —
    /// two gives enough slack to avoid false-triggering on ordinary jitter.
    public static let agingThreshold: TimeInterval = PollingPolicy.minimumScheduledInterval * 2
    /// Half a day with zero successful fetch is past "the OS just hasn't scheduled us
    /// yet" and into "something is actually broken".
    public static let staleThreshold: TimeInterval = 6 * 60 * 60

    public static func level(fetchedAt: Date, now: Date) -> SnapshotFreshnessLevel {
        let age = now.timeIntervalSince(fetchedAt)
        if age >= staleThreshold { return .stale }
        if age >= agingThreshold { return .aging }
        return .fresh
    }

    /// Pure, testable relative-age formatting in French.
    ///
    /// Live widget views should prefer the native `Text(date, style: .relative)`,
    /// which updates on-device without spending any timeline-reload budget. This
    /// string form exists for `accessoryInline` (which composes everything into a
    /// single interpolated line, where mixing in a second native dynamic `Text` isn't
    /// practical) and for tests to assert on wording without a device.
    public static func relativeLabel(fetchedAt: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(fetchedAt) / 60))
        if minutes < 1 { return "à l'instant" }
        if minutes < 60 { return "il y a \(minutes) min" }
        let hours = minutes / 60
        if hours < 48 { return "il y a \(hours) h" }
        let days = hours / 24
        return "il y a \(days) j"
    }
}
