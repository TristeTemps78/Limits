import Foundation

/// Which usage provider a value belongs to.
public enum ProviderKind: String, Codable, Equatable, CaseIterable, Sendable {
    case claude
    case codex
}

/// Normalized window classification, shared by both providers so the app/widgets can
/// render session vs weekly uniformly without caring which provider produced it.
///
/// - Claude: derived from `limits[].group` ("session"/"weekly"), not from `kind`
///   (whose values like "weekly_all" are provider-specific labels kept in `rawKind`).
/// - Codex: derived from `limit_window_seconds` (18 000 → session, 604 800 →
///   weekly) — **never** from `primary_window`/`secondary_window` position. PLAN.md
///   §2.2: on a Plus-plan capture, `primary_window` was the *weekly* window; trusting
///   position instead of duration would silently show wrong numbers under the wrong
///   label — the one failure mode worse than a visible error.
public enum LimitWindowKind: String, Codable, Equatable, Sendable {
    case session
    case weekly
    case unknown
}

/// One usage window (session or weekly), normalized across providers.
public struct LimitWindow: Codable, Equatable, Sendable {
    /// Normalized classification — see `LimitWindowKind`.
    public let windowKind: LimitWindowKind

    /// The provider's own label for this window, kept for display/debugging only.
    /// Claude: `limits[].kind` (e.g. "session", "weekly_all"). Codex: `nil` — Codex
    /// windows carry no textual kind, only a duration.
    public let rawKind: String?

    /// 0-100. PLAN.md §2.1: Claude's `utilization`/`percent` and Codex's
    /// `used_percent` are already percents, never fractions — never divide/multiply
    /// by 100 again downstream.
    public let percent: Double

    /// Claude only (`limits[].severity`); `nil` for Codex, which has no equivalent
    /// field.
    public let severity: String?

    /// `nil` means the window is currently inactive (Claude: no session in
    /// progress) or the source didn't provide a value — **not an error**, a state to
    /// render as "no active window" rather than a blank/loading state.
    public let resetsAt: Date?

    /// Claude only (`limits[].is_active`, an explicit tri-state signal). `nil` for
    /// Codex, which has no equivalent flag — never infer activity from percent > 0.
    public let isActive: Bool?

    /// Codex only (`limit_window_seconds`) — kept because it's the source of truth
    /// `windowKind` was classified from; useful to display/debug a window Codex
    /// might report with a duration we don't recognize (classified `.unknown`).
    public let windowSeconds: Int?

    public init(
        windowKind: LimitWindowKind,
        rawKind: String? = nil,
        percent: Double,
        severity: String? = nil,
        resetsAt: Date? = nil,
        isActive: Bool? = nil,
        windowSeconds: Int? = nil
    ) {
        self.windowKind = windowKind
        self.rawKind = rawKind
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
        self.isActive = isActive
        self.windowSeconds = windowSeconds
    }
}

/// Claude's "extra usage" / spend-on-credits data (`extra_usage` + `spend` in
/// `fixtures/claude-usage.json`) — bonus info beyond the core session/weekly limits,
/// parity with Codex's reset credits. Both source objects describe the same
/// underlying balance from two angles (`extra_usage` in raw credits, `spend` in
/// money with a percent/severity already computed); merged here into one type rather
/// than mirrored 1:1, since the app only ever displays one "extra usage" story.
public struct ClaudeExtraUsage: Codable, Equatable, Sendable {
    /// `extra_usage.is_enabled`.
    public let isEnabled: Bool
    /// `extra_usage.monthly_limit`.
    public let monthlyLimit: Double?
    /// `extra_usage.used_credits`.
    public let usedCredits: Double?
    /// `extra_usage.utilization`, already 0-100.
    public let utilizationPercent: Double?
    /// `extra_usage.currency`.
    public let currency: String?
    /// `spend.percent`, already 0-100 — kept distinct from `utilizationPercent`
    /// because the two source fields can disagree in principle (different rounding);
    /// never averaged or reconciled here, both surfaced as-is.
    public let spendPercent: Double?
    /// `spend.severity` (e.g. "critical").
    public let spendSeverity: String?

    public init(
        isEnabled: Bool,
        monthlyLimit: Double? = nil,
        usedCredits: Double? = nil,
        utilizationPercent: Double? = nil,
        currency: String? = nil,
        spendPercent: Double? = nil,
        spendSeverity: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.monthlyLimit = monthlyLimit
        self.usedCredits = usedCredits
        self.utilizationPercent = utilizationPercent
        self.currency = currency
        self.spendPercent = spendPercent
        self.spendSeverity = spendSeverity
    }
}

/// Codex "reset credits" — bonus usage credits granted after a rate-limit reset.
///
/// Two real, differently-shaped sources both feed this same type, tolerantly:
/// - `/wham/rate-limit-reset-credits` (dedicated endpoint,
///   `fixtures/codex-credits.json`): `available_count`, `total_earned_count`, and an
///   itemized `credits` array.
/// - `/wham/usage`'s embedded `rate_limit_reset_credits` object
///   (`fixtures/codex-usage.json`): a smaller summary with `available_count` and
///   `applicable_available_count` instead of `total_earned_count`.
///
/// Every real capture we have shows `credits: []` — we have **zero verified
/// evidence** of what a non-empty entry looks like (id? amount? expiry date?).
/// Per AGENTS.md rule 3 ("fixtures = vérité du parsing", never invent an unverified
/// shape) this type does not model individual credit entries, only how many are
/// present (`creditCount`). Revisit once a non-empty capture exists.
public struct ResetCredit: Codable, Equatable, Sendable {
    public let availableCount: Int
    /// Only present when decoded from the dedicated `/wham/rate-limit-reset-credits`
    /// response.
    public let totalEarnedCount: Int?
    /// Only present when decoded from `/wham/usage`'s embedded summary.
    public let applicableAvailableCount: Int?
    /// `credits.count` from the dedicated endpoint, when that array was present.
    public let creditCount: Int?

    public init(
        availableCount: Int,
        totalEarnedCount: Int? = nil,
        applicableAvailableCount: Int? = nil,
        creditCount: Int? = nil
    ) {
        self.availableCount = availableCount
        self.totalEarnedCount = totalEarnedCount
        self.applicableAvailableCount = applicableAvailableCount
        self.creditCount = creditCount
    }
}

/// A single provider's usage snapshot, timestamped and schema-versioned.
///
/// `schemaVersion` exists so that the day this shape changes, a widget still running
/// an older binary (a very real scenario here: widgets update independently of the
/// containing app on iOS, and Sideloadly's 7-day certificate cycle adds its own lag)
/// can detect a format it doesn't understand and show "mets à jour l'app" instead of
/// mis-decoding partial/wrong data. See `SnapshotStore`, which enforces this check
/// before attempting a full decode.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let provider: ProviderKind
    public let fetchedAt: Date
    public let windows: [LimitWindow]
    /// Claude only.
    public let extraUsage: ClaudeExtraUsage?
    /// Codex only.
    public let resetCredits: ResetCredit?

    public init(
        schemaVersion: Int = UsageSnapshot.currentSchemaVersion,
        provider: ProviderKind,
        fetchedAt: Date,
        windows: [LimitWindow],
        extraUsage: ClaudeExtraUsage? = nil,
        resetCredits: ResetCredit? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.windows = windows
        self.extraUsage = extraUsage
        self.resetCredits = resetCredits
    }
}

/// The single JSON payload written to the App Group container and read by both the
/// app and the widgets — "le snapshot partagé" of PLAN.md §4. Either provider may be
/// `nil` (not connected yet, or its last fetch never succeeded).
public struct SharedUsageSnapshots: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let updatedAt: Date
    public let claude: UsageSnapshot?
    public let codex: UsageSnapshot?

    public init(
        updatedAt: Date,
        claude: UsageSnapshot?,
        codex: UsageSnapshot?,
        schemaVersion: Int = SharedUsageSnapshots.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.claude = claude
        self.codex = codex
    }
}
