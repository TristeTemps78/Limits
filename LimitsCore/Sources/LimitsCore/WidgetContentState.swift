import Foundation

/// Everything a widget view needs to decide *which* placeholder or content to render,
/// derived once from a `SnapshotSource` read — the view itself only switches on this,
/// it never inspects `Result<SharedUsageSnapshots, SnapshotStoreError>` or compares
/// dates directly (T2.3 brief: "les vues ne contiennent que de la mise en forme").
///
/// Covers all four explicit placeholders the brief calls for:
/// - `.readFailed` → "App Group indisponible" (and siblings — see
///   `SnapshotStoreError.widgetDiagnosticMessage`).
/// - `.notConnected` → "jamais connecté".
/// - `.ready(_, freshness: .aging/.stale, _)` → "données périmées".
/// - `.ready(_, _, reconnectNeeded: non-empty)` → "reconnexion nécessaire", shown
///   *alongside* the last known numbers rather than replacing them, per PLAN.md §6
///   ("conserver et afficher le dernier snapshot").
public enum WidgetContentState: Equatable, Sendable {
    case readFailed(SnapshotStoreError)
    case notConnected
    case ready(snapshots: SharedUsageSnapshots, freshness: SnapshotFreshnessLevel, reconnectNeeded: [ProviderKind])
}

public enum WidgetContentStateBuilder {
    public static func build(
        result: Result<SharedUsageSnapshots, SnapshotStoreError>,
        now: Date
    ) -> WidgetContentState {
        switch result {
        case .failure(let error):
            return .readFailed(error)
        case .success(let snapshots):
            if isNeverConnected(snapshots) {
                return .notConnected
            }
            return .ready(
                snapshots: snapshots,
                freshness: SnapshotFreshness.level(fetchedAt: snapshots.updatedAt, now: now),
                reconnectNeeded: reconnectNeededProviders(snapshots)
            )
        }
    }

    private static func isNeverConnected(_ snapshots: SharedUsageSnapshots) -> Bool {
        snapshots.claude == nil && snapshots.codex == nil
            && isNotConnectedStatus(snapshots.claudeStatus)
            && isNotConnectedStatus(snapshots.codexStatus)
    }

    /// `nil` (an older writer, or T3.1 hasn't run yet) is treated the same as
    /// `.notConnected` here — never as `.connected`. See `claudeStatus`'s doc comment
    /// in `Models.swift`.
    private static func isNotConnectedStatus(_ status: ProviderConnectionStatus?) -> Bool {
        status == nil || status == .notConnected
    }

    private static func reconnectNeededProviders(_ snapshots: SharedUsageSnapshots) -> [ProviderKind] {
        var providers: [ProviderKind] = []
        if snapshots.claudeStatus == .needsReconnect { providers.append(.claude) }
        if snapshots.codexStatus == .needsReconnect { providers.append(.codex) }
        return providers
    }
}
