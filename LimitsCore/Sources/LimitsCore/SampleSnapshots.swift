import Foundation

/// Example `SharedUsageSnapshots` built from the real values captured 2026-07-29
/// (`fixtures/claude-usage.json`, `fixtures/codex-usage.json` — verified against those
/// fixtures in `ClaudeUsageClientTests`/`CodexUsageClientTests`, T2.1), for use by both
/// widget previews and this package's own tests. Widget preview targets can't reach
/// outside the SwiftPM/Xcode sandbox to read repo-root `fixtures/*.json` the way
/// `LimitsCoreTests.FixtureLoader` does (that trick relies on `#filePath`, which points
/// somewhere Xcode preview processes don't have unsandboxed access to) — so these are
/// reproduced by hand instead of decoded at preview time. Keeping them here, instead of
/// duplicated inline in each preview, is what keeps a preview's numbers from silently
/// drifting away from the fixture-verified ones.
///
/// Percentages, severities and structure are the exact fixture values. Reset instants
/// are expressed as **offsets from `referenceNow`**, not the fixtures' literal
/// timestamps (`2026-08-04T17:59:59...`) — those are now in the past relative to
/// whenever this code actually runs, which would make every preview/test show a
/// `WindowDisplayState.awaitingRefresh` instead of the "counting down" state most of
/// them are meant to demonstrate. `588_610` s is Codex's own captured
/// `reset_after_seconds`; Claude's fixture only gave an absolute timestamp with no
/// captured relative offset, so its reset is approximated at the same order of
/// magnitude (~6 days) rather than invented precisely.
public enum SampleSnapshots {
    /// A fixed instant, not `Date()` — previews and tests must render identically on
    /// every run. No hidden `Date()` reads here, matching `PollingPolicy`'s injected-
    /// clock discipline.
    public static let referenceNow = Date(timeIntervalSince1970: 1_800_000_000)

    private static let codexWeeklyResetOffset: TimeInterval = 588_610
    private static let claudeWeeklyResetOffset: TimeInterval = 6 * 24 * 60 * 60

    /// Claude: session inactive at 0 % (`resets_at: null` — a state, not an error),
    /// weekly at 8 %, both `"normal"` severity. `extra_usage`/`spend` reproduced too
    /// (monthly_limit 16 000, used_credits 15 558, ~97.24 % utilization, 97 % spend,
    /// `"critical"` spend severity).
    public static let claude = UsageSnapshot(
        provider: .claude,
        fetchedAt: referenceNow,
        windows: [
            LimitWindow(windowKind: .session, rawKind: "session", percent: 0, severity: "normal", resetsAt: nil, isActive: false),
            LimitWindow(
                windowKind: .weekly,
                rawKind: "weekly_all",
                percent: 8,
                severity: "normal",
                resetsAt: referenceNow.addingTimeInterval(claudeWeeklyResetOffset),
                isActive: true
            )
        ],
        extraUsage: ClaudeExtraUsage(
            isEnabled: false,
            monthlyLimit: 16000,
            usedCredits: 15558,
            utilizationPercent: 97.2375,
            currency: "AUD",
            spendPercent: 97,
            spendSeverity: "critical"
        )
    )

    /// Codex: `primary_window` (604 800 s → weekly) at 9 %, classified by duration —
    /// **not** treated as the 5 h session just because it was `primary`.
    /// `secondary_window` was `null` in the real capture, so there is deliberately no
    /// session window here.
    public static let codex = UsageSnapshot(
        provider: .codex,
        fetchedAt: referenceNow,
        windows: [
            LimitWindow(
                windowKind: .weekly,
                percent: 9,
                resetsAt: referenceNow.addingTimeInterval(codexWeeklyResetOffset),
                windowSeconds: 604_800
            )
        ],
        resetCredits: ResetCredit(availableCount: 0, applicableAvailableCount: 0)
    )

    /// Both providers connected and fresh — the common case, and what `systemLarge`'s
    /// preview should mostly look like.
    public static let bothConnected = SharedUsageSnapshots(
        updatedAt: referenceNow,
        claude: claude,
        codex: codex,
        claudeStatus: .connected,
        codexStatus: .connected
    )

    /// Only Claude connected — exercises the "non connecté" per-provider rendering in
    /// multi-provider families (`systemMedium`/`systemLarge`) without needing the
    /// whole-widget `.notConnected` placeholder.
    public static let claudeOnly = SharedUsageSnapshots(
        updatedAt: referenceNow,
        claude: claude,
        codex: nil,
        claudeStatus: .connected,
        codexStatus: .notConnected
    )

    /// Neither provider ever connected — `WidgetContentStateBuilder` must map this to
    /// `.notConnected`.
    public static let notConnected = SharedUsageSnapshots(
        updatedAt: referenceNow,
        claude: nil,
        codex: nil,
        claudeStatus: .notConnected,
        codexStatus: .notConnected
    )

    /// Claude's token died after a refresh attempt failed; last known numbers are kept
    /// (PLAN.md §6) alongside a reconnect banner. Also one hour stale, to preview the
    /// "aging" freshness banner at the same time as "reconnect" — the two are
    /// independent signals that can co-occur.
    public static let claudeNeedsReconnect = SharedUsageSnapshots(
        updatedAt: referenceNow.addingTimeInterval(-60 * 60),
        claude: claude,
        codex: codex,
        claudeStatus: .needsReconnect,
        codexStatus: .connected
    )

    /// Half a day since the last successful fetch — past `SnapshotFreshness.staleThreshold`.
    public static let stale = SharedUsageSnapshots(
        updatedAt: referenceNow.addingTimeInterval(-7 * 60 * 60),
        claude: claude,
        codex: codex,
        claudeStatus: .connected,
        codexStatus: .connected
    )

    /// A window whose `resetsAt` has already passed without a re-fetch —
    /// `WindowPresentation.displayState` must classify it `.awaitingRefresh`, not keep
    /// counting down past zero.
    public static let pastReset = SharedUsageSnapshots(
        updatedAt: referenceNow,
        claude: UsageSnapshot(
            provider: .claude,
            fetchedAt: referenceNow,
            windows: [
                LimitWindow(
                    windowKind: .weekly,
                    rawKind: "weekly_all",
                    percent: 8,
                    severity: "normal",
                    resetsAt: referenceNow.addingTimeInterval(-30 * 60),
                    isActive: true
                )
            ]
        ),
        codex: nil,
        claudeStatus: .connected,
        codexStatus: .notConnected
    )
}
