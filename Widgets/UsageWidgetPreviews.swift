import SwiftUI
import WidgetKit
import LimitsCore

/// Previews driven by `LimitsCore.SampleSnapshots` — real fixture values (T2.1), not
/// numbers invented in this file (PLAN.md §4 asks for fixture-backed previews).
///
/// `#Preview(as:)`'s `timeline:` trailing closure is a result builder over bare
/// `TimelineEntry` values (Apple's own examples list entries directly, not wrapped in
/// an array literal) — verifiable only in Xcode, which no agent on this project has;
/// this follows the documented shape as closely as possible without being able to
/// render it.

#Preview("systemSmall — connecté", as: .systemSmall) {
    UsageWidget()
} timeline: {
    readyEntry(SampleSnapshots.bothConnected, freshness: .fresh)
}

#Preview("systemSmall — jamais connecté", as: .systemSmall) {
    UsageWidget()
} timeline: {
    UsageWidgetEntry(date: SampleSnapshots.referenceNow, state: .notConnected)
}

#Preview("systemSmall — App Group indisponible", as: .systemSmall) {
    UsageWidget()
} timeline: {
    UsageWidgetEntry(date: SampleSnapshots.referenceNow, state: .readFailed(.containerUnavailable))
}

#Preview("systemMedium — Claude seul", as: .systemMedium) {
    UsageWidget()
} timeline: {
    readyEntry(SampleSnapshots.claudeOnly, freshness: .fresh)
}

#Preview("systemMedium — données périmées", as: .systemMedium) {
    UsageWidget()
} timeline: {
    readyEntry(SampleSnapshots.stale, freshness: .stale)
}

#Preview("systemLarge — connecté", as: .systemLarge) {
    UsageWidget()
} timeline: {
    readyEntry(SampleSnapshots.bothConnected, freshness: .fresh)
}

#Preview("systemLarge — reconnexion Claude requise", as: .systemLarge) {
    UsageWidget()
} timeline: {
    readyEntry(SampleSnapshots.claudeNeedsReconnect, freshness: .aging, reconnectNeeded: [.claude])
}

#Preview("accessoryCircular", as: .accessoryCircular) {
    UsageWidget()
} timeline: {
    readyEntry(SampleSnapshots.bothConnected, freshness: .fresh)
}

#Preview("accessoryRectangular", as: .accessoryRectangular) {
    UsageWidget()
} timeline: {
    readyEntry(SampleSnapshots.bothConnected, freshness: .fresh)
}

#Preview("accessoryInline", as: .accessoryInline) {
    UsageWidget()
} timeline: {
    readyEntry(SampleSnapshots.bothConnected, freshness: .fresh)
}

#Preview("accessoryInline — reset attendu", as: .accessoryInline) {
    UsageWidget()
} timeline: {
    readyEntry(SampleSnapshots.pastReset, freshness: .fresh)
}

private func readyEntry(
    _ snapshots: SharedUsageSnapshots,
    freshness: SnapshotFreshnessLevel,
    reconnectNeeded: [ProviderKind] = []
) -> UsageWidgetEntry {
    UsageWidgetEntry(
        date: SampleSnapshots.referenceNow,
        state: .ready(snapshots: snapshots, freshness: freshness, reconnectNeeded: reconnectNeeded)
    )
}
