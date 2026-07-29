import SwiftUI
import WidgetKit
import LimitsCore

/// T2.3: the real usage widget, covering every family the brief asks for. All
/// "when to show what" logic (`WidgetContentStateBuilder`, `WindowSelector`,
/// `WidgetTimelinePlanner`, `WindowPresentation`) lives in `LimitsCore` and is unit
/// tested there — this file and `UsageWidgetViews.swift` are formatting only.
///
/// Reads exclusively through `SnapshotSource` (`AppGroupSnapshotSource` by default) —
/// no network, no token, matching rule 8 of AGENTS.md. This is also the seam PLAN.md §7
/// calls out for the gate-M1 architecture switch: if App Group sharing doesn't survive
/// Sideloadly's re-signing, only the `SnapshotSource` this provider is constructed with
/// changes, nothing in this file or `UsageWidgetViews.swift`.
struct UsageWidget: Widget {
    let kind = "LimitsUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Limites d'usage")
        .description("Claude Code et Codex : fenêtres 5 h et hebdomadaires, en un coup d'œil.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

struct UsageWidgetEntry: TimelineEntry {
    let date: Date
    let state: WidgetContentState
}

/// Thin glue between WidgetKit's callback-based `TimelineProvider` protocol and the
/// pure, synchronous, testable `LimitsCore` functions it calls. This struct itself is
/// not unit tested (it can't be, without a WidgetKit runtime — no simulator exists in
/// this project's toolchain either) — everything it does is one line handing off to
/// something that *is* tested: `SnapshotSource.loadSnapshots()` (T2.1),
/// `WidgetContentStateBuilder.build` and `WidgetTimelinePlanner.plan` (T2.3).
struct UsageTimelineProvider: TimelineProvider {
    typealias Entry = UsageWidgetEntry

    var snapshotSource: SnapshotSource = AppGroupSnapshotSource()
    var now: () -> Date = Date.init

    func placeholder(in context: Context) -> UsageWidgetEntry {
        // WidgetKit redacts placeholder content itself (`redactionReasons ==
        // .placeholder`); this only needs to be structurally representative so every
        // family has *something* shaped correctly to redact, not real data.
        UsageWidgetEntry(
            date: SampleSnapshots.referenceNow,
            state: .ready(snapshots: SampleSnapshots.bothConnected, freshness: .fresh, reconnectNeeded: [])
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageWidgetEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let current = now()
        let state = WidgetContentStateBuilder.build(result: snapshotSource.loadSnapshots(), now: current)
        completion(UsageWidgetEntry(date: current, state: state))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageWidgetEntry>) -> Void) {
        let current = now()
        // Read the App Group container exactly once per timeline request — the
        // resulting `Result` is reused both to plan *when* to re-render (which needs
        // to know each window's `resetsAt`) and to build each entry's content (which
        // needs the same data rendered at different candidate dates).
        let result = snapshotSource.loadSnapshots()
        let snapshotsForPlanning: SharedUsageSnapshots?
        if case .success(let snapshots) = result {
            snapshotsForPlanning = snapshots
        } else {
            snapshotsForPlanning = nil
        }

        let plan = WidgetTimelinePlanner.plan(snapshots: snapshotsForPlanning, now: current)
        let entries = plan.entryDates.map { date in
            UsageWidgetEntry(date: date, state: WidgetContentStateBuilder.build(result: result, now: date))
        }
        completion(Timeline(entries: entries, policy: .after(plan.reloadAfter)))
    }
}
