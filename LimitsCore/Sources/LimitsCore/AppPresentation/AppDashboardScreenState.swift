import Foundation

/// The whole dashboard screen's state: both providers plus a non-blocking App Group
/// warning.
///
/// The App Group warning is deliberately **not** a blocking case of its own (no
/// `.appGroupUnavailable` that hides the rest of the screen): a broken App Group
/// container only means the widgets won't receive fresh data (T1.1's whole
/// dérisquage concern) — it says nothing about whether the app itself can still fetch
/// and show the user their own usage right now. Blocking the dashboard on an
/// infrastructure detail the user can't fix from this screen would be worse than
/// just warning about it. See `docs/oauth-verification-2026-07-29.md`-adjacent
/// reasoning in `SnapshotSource.swift` for the wider App Group risk this reacts to.
public struct AppDashboardScreenState: Equatable, Sendable {
    public let claude: AppProviderDashboardState
    public let codex: AppProviderDashboardState
    /// `true` when the last attempt to write the shared snapshot to the App Group
    /// container failed (`SnapshotStoreError`, any case) — surfaced as a banner, not
    /// a blocker.
    public let appGroupWarning: Bool

    public init(claude: AppProviderDashboardState, codex: AppProviderDashboardState, appGroupWarning: Bool) {
        self.claude = claude
        self.codex = codex
        self.appGroupWarning = appGroupWarning
    }

    /// Neither provider is connected — the onboarding screen, not the dashboard,
    /// should be showing in this case, but the dashboard's own empty state (if
    /// reached directly) needs to say so rather than show two blank sections.
    public var isEmpty: Bool {
        claude == .notConnected && codex == .notConnected
    }
}

public enum AppDashboardScreenStateBuilder {
    public static func build(
        claude: AppProviderDashboardState,
        codex: AppProviderDashboardState,
        lastSnapshotWriteSucceeded: Bool
    ) -> AppDashboardScreenState {
        AppDashboardScreenState(claude: claude, codex: codex, appGroupWarning: !lastSnapshotWriteSucceeded)
    }
}
