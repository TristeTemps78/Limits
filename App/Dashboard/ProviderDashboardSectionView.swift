import SwiftUI
import LimitsCore

/// One provider's card on the dashboard — the actual state-machine rendering the
/// T2.4 brief calls the heart of this lot. Every branch below says something the
/// user can act on, per the brief's explicit requirement; none of them are silent.
struct ProviderDashboardSectionView: View {
    let title: String
    let state: AppProviderDashboardState
    let gaugeStyle: GaugeStyle
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            switch state {
            case .notConnected:
                Text("Non connecté. Va dans Réglages pour te connecter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Premier chargement…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .content(let snapshot, let freshnessSeconds):
                contentBody(snapshot: snapshot, freshnessSeconds: freshnessSeconds)

            case .staleContent(let snapshot, let freshnessSeconds, let reason, let retryAt):
                contentBody(snapshot: snapshot, freshnessSeconds: freshnessSeconds)
                staleBanner(reason: reason, retryAt: retryAt)

            case .blockedNoData(let reason, let retryAt):
                staleBanner(reason: reason, retryAt: retryAt)
                Text("Aucune donnée pour l'instant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .needsReconnect(let lastSnapshot, let freshnessSeconds):
                reconnectBanner
                if let lastSnapshot, let freshnessSeconds {
                    contentBody(snapshot: lastSnapshot, freshnessSeconds: freshnessSeconds)
                        .opacity(0.6)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Shared pieces

    @ViewBuilder
    private func contentBody(snapshot: UsageSnapshot, freshnessSeconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppFreshnessFormatter.label(ageSeconds: freshnessSeconds))
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                windowRow(window)
            }

            if let extraUsage = snapshot.extraUsage, extraUsage.isEnabled {
                extraUsageRow(extraUsage)
            }

            if let resetCredits = snapshot.resetCredits {
                Text("Crédits de reset disponibles : \(resetCredits.availableCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func windowRow(_ window: LimitWindow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            UsageGaugeView(percent: window.percent, style: gaugeStyle, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(windowLabel(window))
                    .font(.subheadline)
                resetLabel(window)
            }
            Spacer()
        }
    }

    private func windowLabel(_ window: LimitWindow) -> String {
        switch window.windowKind {
        case .session: return "Session (5 h)"
        case .weekly: return "Hebdomadaire"
        case .unknown: return window.rawKind ?? "Fenêtre"
        }
    }

    @ViewBuilder
    private func resetLabel(_ window: LimitWindow) -> some View {
        if let resetsAt = window.resetsAt {
            if resetsAt > Date() {
                (Text("Reset dans ") + Text(timerInterval: Date()...resetsAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Réinitialisation imminente")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Fenêtre inactive")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func extraUsageRow(_ extraUsage: ClaudeExtraUsage) -> some View {
        if let spendPercent = extraUsage.spendPercent {
            Text("Crédits supplémentaires : \(AppPercentFormatter.label(percent: spendPercent))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func staleBanner(reason: AppStaleReason, retryAt: Date) -> some View {
        Label(staleBannerText(reason: reason, retryAt: retryAt), systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private func staleBannerText(reason: AppStaleReason, retryAt: Date) -> String {
        let seconds = max(0, Int(retryAt.timeIntervalSinceNow))
        switch reason {
        case .rateLimited:
            return "Trop de requêtes envoyées — nouvelle tentative dans \(seconds) s."
        case .networkError:
            return "Erreur réseau — nouvelle tentative dans \(seconds) s."
        }
    }

    private var reconnectBanner: some View {
        Label("Reconnexion nécessaire — va dans Réglages pour te reconnecter.", systemImage: "person.crop.circle.badge.exclamationmark")
            .font(.caption)
            .foregroundStyle(.red)
    }
}
