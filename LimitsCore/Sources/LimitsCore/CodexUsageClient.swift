import Foundation

/// `wham/usage` and `wham/rate-limit-reset-credits` (PLAN.md §2.2). Parsing rules
/// verified against the real captures in `fixtures/codex-usage.json` and
/// `fixtures/codex-credits.json`:
/// - Windows are classified by **duration** (`limit_window_seconds`: 18 000 →
///   session, 604 800 → weekly), **never** by `primary_window`/`secondary_window`
///   position. The real capture (a Plus-plan account) has `primary_window` as the
///   *weekly* window and `secondary_window` as `null` — a "primary = 5h" client
///   would show a wrong-but-plausible number, the worst failure mode.
/// - `secondary_window` (or either window) can be absent; both are optional.
/// - `reset_at` is an **epoch in seconds**; `reset_after_seconds` is a duration.
/// - PLAN.md documents alias field names seen in other implementations
///   (`five_hour_limit`/`weekly_limit` instead of `rate_limit.primary_window`/
///   `secondary_window`; `resets_in_seconds` instead of `reset_after_seconds`).
///   Accepted tolerantly below, but **unverified**: no real capture exercises these
///   paths (every real capture uses `rate_limit.primary_window`/`secondary_window`).
///   The tests for this alias path are synthetic, not fixture-driven — flagged as
///   such.
public struct CodexUsageClient {
    private static let usageEndpoint = "wham/usage"
    private static let resetCreditsEndpoint = "wham/rate-limit-reset-credits"

    private let httpClient: HTTPClient
    private let clock: () -> Date

    public init(httpClient: HTTPClient, clock: @escaping () -> Date = Date.init) {
        self.httpClient = httpClient
        self.clock = clock
    }

    public func fetchUsage(accessToken: String, accountID: String) async -> Result<UsageSnapshot, UsageClientError> {
        let request = HTTPRequest(
            url: ProviderConfig.Codex.usageURL,
            headers: headers(accessToken: accessToken, accountID: accountID)
        )
        let result = await httpClient.send(request)
        return Self.handleUsage(result, clock: clock)
    }

    public func fetchResetCredits(accessToken: String, accountID: String) async -> Result<ResetCredit, UsageClientError> {
        let request = HTTPRequest(
            url: ProviderConfig.Codex.resetCreditsURL,
            headers: headers(accessToken: accessToken, accountID: accountID)
        )
        let result = await httpClient.send(request)
        return Self.handleResetCredits(result)
    }

    private func headers(accessToken: String, accountID: String) -> [String: String] {
        [
            "Authorization": "Bearer \(accessToken)",
            "ChatGPT-Account-ID": accountID,
            "originator": ProviderConfig.Codex.originator,
            "User-Agent": ProviderConfig.Codex.userAgent
        ]
    }

    // MARK: - Response handling (pure, testable without a real HTTPClient)

    static func handleUsage(
        _ result: Result<HTTPResponse, HTTPTransportError>,
        clock: () -> Date
    ) -> Result<UsageSnapshot, UsageClientError> {
        switch decodeBody(result, endpoint: usageEndpoint, as: UsageResponseDTO.self) {
        case .failure(let error):
            return .failure(error)
        case .success(let dto):
            return .success(map(dto, fetchedAt: clock()))
        }
    }

    static func handleResetCredits(
        _ result: Result<HTTPResponse, HTTPTransportError>
    ) -> Result<ResetCredit, UsageClientError> {
        switch decodeBody(result, endpoint: resetCreditsEndpoint, as: ResetCreditsResponseDTO.self) {
        case .failure(let error):
            return .failure(error)
        case .success(let dto):
            return .success(
                ResetCredit(
                    availableCount: dto.availableCount ?? 0,
                    totalEarnedCount: dto.totalEarnedCount,
                    applicableAvailableCount: nil,
                    creditCount: dto.credits?.count
                )
            )
        }
    }

    private static func decodeBody<T: Decodable>(
        _ result: Result<HTTPResponse, HTTPTransportError>,
        endpoint: String,
        as type: T.Type
    ) -> Result<T, UsageClientError> {
        switch result {
        case .failure(let error):
            return .failure(.transport(endpoint: endpoint, reason: error.reason))
        case .success(let response):
            switch response.statusCode {
            case 200:
                do {
                    return .success(try JSONDecoder().decode(T.self, from: response.body))
                } catch {
                    return .failure(.decoding(endpoint: endpoint))
                }
            case 401:
                return .failure(.unauthorized(endpoint: endpoint))
            case 429:
                let retryAfter = response.header("Retry-After").flatMap(TimeInterval.init)
                return .failure(.rateLimited(endpoint: endpoint, retryAfter: retryAfter))
            default:
                return .failure(.httpStatus(endpoint: endpoint, status: response.statusCode))
            }
        }
    }

    // MARK: - DTO → domain mapping

    static func map(_ dto: UsageResponseDTO, fetchedAt: Date) -> UsageSnapshot {
        var rawWindows: [UsageResponseDTO.Window] = []
        if let rateLimit = dto.rateLimit {
            rawWindows.append(contentsOf: [rateLimit.primaryWindow, rateLimit.secondaryWindow].compactMap { $0 })
        }
        // Unverified alias path (PLAN.md §2.2) — only consulted when `rate_limit`
        // produced no usable window at all (absent entirely, or present with both
        // `primary_window`/`secondary_window` null). Never overrides a real window.
        if rawWindows.isEmpty {
            rawWindows.append(contentsOf: [dto.fiveHourLimitAlias, dto.weeklyLimitAlias].compactMap { $0 })
        }

        let windows = rawWindows.map { window -> LimitWindow in
            LimitWindow(
                windowKind: windowKind(forSeconds: window.limitWindowSeconds),
                percent: window.usedPercent ?? 0,
                resetsAt: resetsAt(for: window, fetchedAt: fetchedAt),
                windowSeconds: window.limitWindowSeconds
            )
        }

        let resetCredits: ResetCredit?
        if let embedded = dto.rateLimitResetCredits {
            resetCredits = ResetCredit(
                availableCount: embedded.availableCount ?? 0,
                totalEarnedCount: nil,
                applicableAvailableCount: embedded.applicableAvailableCount,
                creditCount: nil
            )
        } else {
            resetCredits = nil
        }

        return UsageSnapshot(
            provider: .codex,
            fetchedAt: fetchedAt,
            windows: windows,
            extraUsage: nil,
            resetCredits: resetCredits
        )
    }

    /// `reset_at` (an absolute epoch) is preferred when present; `reset_after_seconds`
    /// (a duration, relative to when we fetched) is the fallback — PLAN.md §2.2 lists
    /// both as fields to handle, and an implementation that only reads one would
    /// silently show "no reset time" whenever a response only carries the other.
    static func resetsAt(for window: UsageResponseDTO.Window, fetchedAt: Date) -> Date? {
        if let epoch = window.resetAt {
            return Date(timeIntervalSince1970: TimeInterval(epoch))
        }
        if let duration = window.resetAfterSeconds {
            return fetchedAt.addingTimeInterval(TimeInterval(duration))
        }
        return nil
    }

    /// Classifies by duration only — see the type-level doc comment for why position
    /// (`primary`/`secondary`) is never trusted.
    static func windowKind(forSeconds seconds: Int?) -> LimitWindowKind {
        switch seconds {
        case 18_000: return .session
        case 604_800: return .weekly
        default: return .unknown
        }
    }

    // MARK: - Wire format

    struct UsageResponseDTO: Decodable {
        struct Window: Decodable {
            let usedPercent: Double?
            let limitWindowSeconds: Int?
            let resetAfterSeconds: Int?
            let resetAt: Int?

            private enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case limitWindowSeconds = "limit_window_seconds"
                case resetAfterSeconds = "reset_after_seconds"
                case resetsInSeconds = "resets_in_seconds" // alias, PLAN.md §2.2, unverified
                case resetAt = "reset_at"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                usedPercent = try container.decodeIfPresent(Double.self, forKey: .usedPercent)
                limitWindowSeconds = try container.decodeIfPresent(Int.self, forKey: .limitWindowSeconds)
                resetAt = try container.decodeIfPresent(Int.self, forKey: .resetAt)
                if let value = try container.decodeIfPresent(Int.self, forKey: .resetAfterSeconds) {
                    resetAfterSeconds = value
                } else {
                    resetAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .resetsInSeconds)
                }
            }
        }

        struct RateLimit: Decodable {
            let primaryWindow: Window?
            let secondaryWindow: Window?

            enum CodingKeys: String, CodingKey {
                case primaryWindow = "primary_window"
                case secondaryWindow = "secondary_window"
            }
        }

        struct EmbeddedResetCredits: Decodable {
            let availableCount: Int?
            let applicableAvailableCount: Int?

            enum CodingKeys: String, CodingKey {
                case availableCount = "available_count"
                case applicableAvailableCount = "applicable_available_count"
            }
        }

        let rateLimit: RateLimit?
        let rateLimitResetCredits: EmbeddedResetCredits?
        // Alias top-level windows (PLAN.md §2.2), only ever consulted if `rateLimit`
        // is absent entirely — see the type-level doc comment. Unverified.
        let fiveHourLimitAlias: Window?
        let weeklyLimitAlias: Window?

        enum CodingKeys: String, CodingKey {
            case rateLimit = "rate_limit"
            case rateLimitResetCredits = "rate_limit_reset_credits"
            case fiveHourLimitAlias = "five_hour_limit"
            case weeklyLimitAlias = "weekly_limit"
        }
    }

    struct ResetCreditsResponseDTO: Decodable {
        /// Deliberately empty: every real capture (`fixtures/codex-credits.json`)
        /// shows `credits: []`, so there is no verified field shape to decode. A
        /// struct with no stored properties still successfully "decodes" any JSON
        /// object without asserting anything about its contents — exactly the
        /// tolerance we want until a non-empty capture exists (see `ResetCredit`'s
        /// doc comment in Models.swift).
        struct Credit: Decodable {}

        let credits: [Credit]?
        let availableCount: Int?
        let totalEarnedCount: Int?

        enum CodingKeys: String, CodingKey {
            case credits
            case availableCount = "available_count"
            case totalEarnedCount = "total_earned_count"
        }
    }
}
