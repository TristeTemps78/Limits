import Foundation

/// `GET /api/oauth/usage` (PLAN.md §2.1). Parsing rules verified against the real
/// capture in `fixtures/claude-usage.json`:
/// - `limits[]` (`kind`, `group`, `percent`, `severity`, `resets_at`, `is_active`) is
///   the **preferred** source — uniform across session/weekly. The root objects
///   (`five_hour`, `seven_day`) are only used as a **fallback** when `limits` is
///   missing or empty.
/// - `utilization`/`percent` are already 0-100.
/// - `resets_at` is `null` when the window is inactive — a state, not an error.
/// - The fixture carries several always-`null`, made-up-sounding top-level keys
///   (`tangelo`, `iguana_necktie`, ...). Codable already ignores any key not listed
///   in a type's `CodingKeys`, so tolerance here is structural, not something extra
///   to write.
public struct ClaudeUsageClient {
    private static let endpoint = "api/oauth/usage"

    private let httpClient: HTTPClient
    private let clock: () -> Date

    public init(httpClient: HTTPClient, clock: @escaping () -> Date = Date.init) {
        self.httpClient = httpClient
        self.clock = clock
    }

    public func fetchUsage(accessToken: String) async -> Result<UsageSnapshot, UsageClientError> {
        let request = HTTPRequest(
            url: ProviderConfig.Claude.usageURL,
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "anthropic-beta": ProviderConfig.Claude.anthropicBetaHeader,
                "User-Agent": ProviderConfig.Claude.userAgent
            ]
        )
        let result = await httpClient.send(request)
        return Self.handle(result, clock: clock)
    }

    // MARK: - Response handling (pure, testable without a real HTTPClient)

    static func handle(
        _ result: Result<HTTPResponse, HTTPTransportError>,
        clock: () -> Date
    ) -> Result<UsageSnapshot, UsageClientError> {
        switch result {
        case .failure(let error):
            return .failure(.transport(endpoint: endpoint, reason: error.reason))
        case .success(let response):
            switch response.statusCode {
            case 200:
                do {
                    let dto = try JSONDecoder().decode(ResponseDTO.self, from: response.body)
                    return .success(map(dto, fetchedAt: clock()))
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

    static func map(_ dto: ResponseDTO, fetchedAt: Date) -> UsageSnapshot {
        let windows: [LimitWindow]
        if let limits = dto.limits, !limits.isEmpty {
            windows = limits.map { entry in
                LimitWindow(
                    windowKind: windowKind(fromGroup: entry.group, kind: entry.kind),
                    rawKind: entry.kind,
                    percent: entry.percent ?? 0,
                    severity: entry.severity,
                    resetsAt: entry.resetsAt.flatMap(FlexibleISO8601.parse),
                    isActive: entry.isActive,
                    windowSeconds: nil
                )
            }
        } else {
            windows = fallbackWindows(dto)
        }

        let extraUsage: ClaudeExtraUsage?
        if let dtoExtra = dto.extraUsage {
            extraUsage = ClaudeExtraUsage(
                isEnabled: dtoExtra.isEnabled ?? false,
                monthlyLimit: dtoExtra.monthlyLimit,
                usedCredits: dtoExtra.usedCredits,
                utilizationPercent: dtoExtra.utilization,
                currency: dtoExtra.currency,
                spendPercent: dto.spend?.percent,
                spendSeverity: dto.spend?.severity
            )
        } else {
            extraUsage = nil
        }

        return UsageSnapshot(
            provider: .claude,
            fetchedAt: fetchedAt,
            windows: windows,
            extraUsage: extraUsage,
            resetCredits: nil
        )
    }

    /// Used only when `limits[]` is absent/empty. `five_hour`/`seven_day` carry no
    /// `severity`/`is_active` of their own, so those come back `nil` (unknown), not a
    /// guessed value.
    private static func fallbackWindows(_ dto: ResponseDTO) -> [LimitWindow] {
        var windows: [LimitWindow] = []
        if let fiveHour = dto.fiveHour {
            windows.append(
                LimitWindow(
                    windowKind: .session,
                    rawKind: "five_hour",
                    percent: fiveHour.utilization ?? 0,
                    resetsAt: fiveHour.resetsAt.flatMap(FlexibleISO8601.parse)
                )
            )
        }
        if let sevenDay = dto.sevenDay {
            windows.append(
                LimitWindow(
                    windowKind: .weekly,
                    rawKind: "seven_day",
                    percent: sevenDay.utilization ?? 0,
                    resetsAt: sevenDay.resetsAt.flatMap(FlexibleISO8601.parse)
                )
            )
        }
        return windows
    }

    /// `group` is the reliable classifier ("session"/"weekly"); `kind` is only
    /// sniffed as a last resort when `group` is missing or an unrecognized value.
    static func windowKind(fromGroup group: String?, kind: String?) -> LimitWindowKind {
        switch group {
        case "session":
            return .session
        case "weekly":
            return .weekly
        default:
            if kind == "session" { return .session }
            if let kind, kind.hasPrefix("weekly") { return .weekly }
            return .unknown
        }
    }

    // MARK: - Wire format (only the fields we use; everything else is ignored by
    // Codable automatically since it isn't declared in CodingKeys)

    struct ResponseDTO: Decodable {
        struct RootWindow: Decodable {
            let utilization: Double?
            let resetsAt: String?

            enum CodingKeys: String, CodingKey {
                case utilization
                case resetsAt = "resets_at"
            }
        }

        struct LimitEntry: Decodable {
            let kind: String?
            let group: String?
            let percent: Double?
            let severity: String?
            let resetsAt: String?
            let isActive: Bool?

            enum CodingKeys: String, CodingKey {
                case kind, group, percent, severity
                case resetsAt = "resets_at"
                case isActive = "is_active"
            }
        }

        struct ExtraUsageDTO: Decodable {
            let isEnabled: Bool?
            let monthlyLimit: Double?
            let usedCredits: Double?
            let utilization: Double?
            let currency: String?

            enum CodingKeys: String, CodingKey {
                case isEnabled = "is_enabled"
                case monthlyLimit = "monthly_limit"
                case usedCredits = "used_credits"
                case utilization, currency
            }
        }

        struct SpendDTO: Decodable {
            let percent: Double?
            let severity: String?
        }

        let fiveHour: RootWindow?
        let sevenDay: RootWindow?
        let limits: [LimitEntry]?
        let extraUsage: ExtraUsageDTO?
        let spend: SpendDTO?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case limits
            case extraUsage = "extra_usage"
            case spend
        }
    }
}
