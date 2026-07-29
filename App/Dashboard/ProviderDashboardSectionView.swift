import SwiftUI
import LimitsCore

/// One provider's card on the dashboard — the actual state-machine rendering the
/// T2.4 brief calls the heart of this lot. Every branch below says something the
/// user can act on, per the brief's explicit requirement; none of them are silent.
///
/// Freshness, per-window reset display, and severity color/symbol all come from
/// `LimitsCore` (`SnapshotFreshness`, `WindowPresentation`, `WindowSeverity` — T2.3),
/// the same types the widget uses, so a percent or an age never disagrees between
/// the app and the widget for the same underlying data.
struct ProviderDashboardSectionView: View {
    /// Le provider, et non seulement son titre : certains messages doivent le nommer
    /// (cf. `UnexpectedPayloadDetector.userFacingMessage`), et le libelle affiche vient
    /// de `ProviderKind.displayName` (LimitsCore) plutot que d'une chaine recopiee.
    let provider: ProviderKind
    let state: AppProviderDashboardState
    let gaugeStyle: GaugeStyle
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(provider.displayName)
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

            case .content(let snapshot):
                contentBody(snapshot: snapshot)

            case .unexpectedPayload:
                // Message explicite « inutile de te reconnecter » : c'est le contresens que
                // cet état existe pour éviter (le parsing tolérant échoue en silence).
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.bubble")
                        .foregroundStyle(.orange)
                    Text(UnexpectedPayloadDetector.userFacingMessage(for: provider))
                        .font(.caption)
                }

            case .staleContent(let snapshot, let reason, let retryAt):
                contentBody(snapshot: snapshot)
                staleBanner(reason: reason, retryAt: retryAt)

            case .blockedNoData(let reason, let retryAt):
                staleBanner(reason: reason, retryAt: retryAt)
                Text("Aucune donnée pour l'instant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .needsReconnect(let lastSnapshot):
                reconnectBanner
                if let lastSnapshot {
                    contentBody(snapshot: lastSnapshot)
                        .opacity(0.6)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Shared pieces

    @ViewBuilder
    private func contentBody(snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            freshnessRow(fetchedAt: snapshot.fetchedAt)

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
    private func freshnessRow(fetchedAt: Date) -> some View {
        // "à jour il y a X" is first-class per the T2.4 brief, not a small mention —
        // `SnapshotFreshness.relativeLabel` is the exact same formatting the widget
        // uses (T2.3).
        let level = SnapshotFreshness.level(fetchedAt: fetchedAt, now: now)
        HStack(spacing: 6) {
            Text("à jour \(SnapshotFreshness.relativeLabel(fetchedAt: fetchedAt, now: now))")
                .font(.caption)
                .foregroundStyle(level == .fresh ? Color.secondary : Color.orange)
            if let bannerMessage = level.widgetBannerMessage {
                Text("· \(bannerMessage)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func windowRow(_ window: LimitWindow) -> some View {
        let severity = WindowSeverity.classify(window)
        HStack(alignment: .center, spacing: 12) {
            UsageGaugeView(percent: window.percent, style: gaugeStyle, tint: severity.color)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: severity.symbolName)
                        .foregroundStyle(severity.color)
                        .font(.caption2)
                    Text(window.windowKind.displayName)
                        .font(.subheadline)
                }
                resetLabel(window)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func resetLabel(_ window: LimitWindow) -> some View {
        switch WindowPresentation.displayState(for: window, now: now) {
        case .inactive:
            Text("Fenêtre inactive")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .counting(let resetsAt):
            // Decision carried over from the widget (T2.3), for consistency: a
            // countdown further out than 24h reads as a relative label ("dans 6 j"),
            // not a live-ticking minute/second countdown that would be noise at that
            // distance; under 24h it ticks live via `Text(timerInterval:)`.
            if resetsAt.timeIntervalSince(now) > 24 * 60 * 60 {
                Text("Reset \(relativeCountdown(to: resetsAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                (Text("Reset dans ") + Text(timerInterval: now...resetsAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .awaitingRefresh:
            Text("Réinitialisation attendue")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func relativeCountdown(to resetsAt: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: resetsAt, relativeTo: now)
    }

    @ViewBuilder
    private func extraUsageRow(_ extraUsage: ClaudeExtraUsage) -> some View {
        if let spendPercent = extraUsage.spendPercent {
            Text("Crédits supplémentaires : \(spendPercent.roundedPercentText)")
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
        let seconds = max(0, Int(retryAt.timeIntervalSince(now)))
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
