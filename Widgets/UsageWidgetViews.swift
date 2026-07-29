import SwiftUI
import WidgetKit
import LimitsCore

/// Dispatches on `WidgetFamily` and `WidgetContentState`. Every branch below is pure
/// formatting — the state itself (which placeholder, which window, when to show a
/// countdown vs. "réinitialisation attendue") was already decided in `LimitsCore`.
struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageWidgetEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case .readFailed(let error):
            PlaceholderView(message: error.widgetDiagnosticMessage, systemImage: "externaldrive.badge.exclamationmark")
        case .notConnected:
            PlaceholderView(message: "Non connecté", systemImage: "person.crop.circle.badge.questionmark")
        case .unexpectedPayload:
            // Formulation qui distingue explicitement ce cas de « non connecté » : ici,
            // se reconnecter ne servirait à rien. Court, la place est comptée.
            PlaceholderView(message: "Format d'API inattendu — mise à jour requise", systemImage: "exclamationmark.bubble")
        case .ready(let snapshots, let freshness, let reconnectNeeded):
            switch family {
            case .accessoryInline:
                InlineUsageView(entryDate: entry.date, snapshots: snapshots, reconnectNeeded: reconnectNeeded)
            case .accessoryCircular:
                CircularUsageView(entryDate: entry.date, snapshots: snapshots)
            case .accessoryRectangular:
                RectangularUsageView(entryDate: entry.date, snapshots: snapshots, reconnectNeeded: reconnectNeeded)
            case .systemMedium:
                MediumUsageView(entryDate: entry.date, snapshots: snapshots, freshness: freshness, reconnectNeeded: reconnectNeeded)
            case .systemLarge:
                LargeUsageView(entryDate: entry.date, snapshots: snapshots, freshness: freshness, reconnectNeeded: reconnectNeeded)
            default: // .systemSmall and any future family
                SmallUsageView(entryDate: entry.date, snapshots: snapshots, freshness: freshness, reconnectNeeded: reconnectNeeded)
            }
        }
    }
}

/// The "App Group indisponible" / "jamais connecté" placeholders — an empty widget is a
/// widget the brief says users will remove, so every family gets an explicit message
/// rather than blank space.
private struct PlaceholderView: View {
    @Environment(\.widgetFamily) private var family
    let message: String
    let systemImage: String

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(message, systemImage: systemImage)
        case .accessoryCircular:
            Image(systemName: systemImage)
                .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Limits", systemImage: systemImage)
                    .font(.caption2.bold())
                Text(message)
                    .font(.caption2)
                    .lineLimit(2)
            }
        default:
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

// MARK: - accessoryInline (single line)

private struct InlineUsageView: View {
    let entryDate: Date
    let snapshots: SharedUsageSnapshots
    let reconnectNeeded: [ProviderKind]

    var body: some View {
        if let provider = reconnectNeeded.first {
            Label("\(provider.displayName) : reconnexion requise", systemImage: "person.crop.circle.badge.exclamationmark")
        } else if let selection = WindowSelector.mostUrgent(in: snapshots) {
            let severity = WindowSeverity.classify(selection.window)
            Label {
                Text("\(selection.provider.displayName) \(selection.window.windowKind.shortLabel) \(selection.window.percent.roundedPercentText)\(severityWordSuffix(severity)) · ")
                    + ResetCountdown.text(for: selection.window, now: entryDate)
            } icon: {
                Image(systemName: severity.symbolName)
            }
        } else {
            Label("Limits : aucune donnée", systemImage: "questionmark.circle")
        }
    }

    /// The non-chromatic word half of the severity redundancy (`RingGauge`/`BarGauge`
    /// already carry it via their own badge/glyph parameters). `accessoryInline` is a
    /// single line at lock-screen size — the family where a triangle and an octagon
    /// are least distinguishable — so it needs this too, but the line is already
    /// crowded (provider + window + percent + a live countdown), so the word is only
    /// appended when it actually adds information: `.normal` already reads
    /// unambiguously from a plain checkmark, so it's omitted there to keep the common
    /// case short; `.warning`/`.critical`/`.unknown` are exactly the cases the symbol
    /// alone risks being misread, so they get the word.
    private func severityWordSuffix(_ severity: WindowSeverity) -> String {
        severity == .normal ? "" : " \(severity.shortLabel)"
    }
}

// MARK: - accessoryCircular (one ring)

private struct CircularUsageView: View {
    let entryDate: Date
    let snapshots: SharedUsageSnapshots

    var body: some View {
        if let selection = WindowSelector.mostUrgent(in: snapshots) {
            RingGauge(
                percent: selection.window.percent,
                severity: WindowSeverity.classify(selection.window),
                lineWidth: 4,
                showsPercentText: true,
                showsSeverityBadge: true
            )
        } else {
            Image(systemName: "questionmark.circle")
                .widgetAccentable()
        }
    }
}

// MARK: - accessoryRectangular (compact list)

private struct RectangularUsageView: View {
    let entryDate: Date
    let snapshots: SharedUsageSnapshots
    let reconnectNeeded: [ProviderKind]

    var body: some View {
        let ranked = WindowSelector.ranked(in: snapshots)
        VStack(alignment: .leading, spacing: 3) {
            if let provider = reconnectNeeded.first {
                Label("\(provider.displayName) : reconnecter", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.caption2.bold())
            } else {
                Text("Limits")
                    .font(.caption2.bold())
            }
            ForEach(Array(ranked.prefix(2).enumerated()), id: \.offset) { _, selection in
                BarGauge(
                    title: "\(selection.provider.displayName) \(selection.window.windowKind.shortLabel)",
                    percent: selection.window.percent,
                    severity: WindowSeverity.classify(selection.window),
                    showsSeverityGlyph: true
                )
            }
            if ranked.isEmpty {
                Text("Aucune donnée")
                    .font(.caption2)
            }
        }
    }
}

// MARK: - systemSmall (one headline gauge)

private struct SmallUsageView: View {
    let entryDate: Date
    let snapshots: SharedUsageSnapshots
    let freshness: SnapshotFreshnessLevel
    let reconnectNeeded: [ProviderKind]

    var body: some View {
        VStack(spacing: 4) {
            if let selection = WindowSelector.mostUrgent(in: snapshots) {
                RingGauge(
                    percent: selection.window.percent,
                    severity: WindowSeverity.classify(selection.window),
                    lineWidth: 7
                )
                .frame(maxWidth: 72, maxHeight: 72)

                Text("\(selection.provider.displayName) · \(selection.window.windowKind.shortLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ResetCountdownText(window: selection.window, now: entryDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Aucune donnée")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !reconnectNeeded.isEmpty {
                ReconnectBanner(providers: reconnectNeeded)
            }

            FreshnessFooter(updatedAt: snapshots.updatedAt, freshness: freshness)
        }
        .padding(8)
    }
}

// MARK: - systemMedium (both providers, compact)

private struct MediumUsageView: View {
    let entryDate: Date
    let snapshots: SharedUsageSnapshots
    let freshness: SnapshotFreshnessLevel
    let reconnectNeeded: [ProviderKind]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 16) {
                ProviderColumn(provider: .claude, snapshot: snapshots.claude, entryDate: entryDate)
                Divider()
                ProviderColumn(provider: .codex, snapshot: snapshots.codex, entryDate: entryDate)
            }
            if !reconnectNeeded.isEmpty {
                ReconnectBanner(providers: reconnectNeeded)
            }
            FreshnessFooter(updatedAt: snapshots.updatedAt, freshness: freshness)
        }
        .padding(12)
    }
}

private struct ProviderColumn: View {
    let provider: ProviderKind
    let snapshot: UsageSnapshot?
    let entryDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(provider.displayName)
                .font(.caption.bold())
            if let windows = snapshot?.windows, !windows.isEmpty {
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    BarGauge(
                        title: window.windowKind.shortLabel,
                        percent: window.percent,
                        severity: WindowSeverity.classify(window),
                        showsSeverityGlyph: true
                    )
                }
            } else {
                Text("Non connecté")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - systemLarge (full detail)

private struct LargeUsageView: View {
    let entryDate: Date
    let snapshots: SharedUsageSnapshots
    let freshness: SnapshotFreshnessLevel
    let reconnectNeeded: [ProviderKind]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Limits")
                .font(.headline)

            ProviderDetailSection(provider: .claude, snapshot: snapshots.claude, entryDate: entryDate)
            Divider()
            ProviderDetailSection(provider: .codex, snapshot: snapshots.codex, entryDate: entryDate)

            Spacer(minLength: 0)

            if !reconnectNeeded.isEmpty {
                ReconnectBanner(providers: reconnectNeeded)
            }
            FreshnessFooter(updatedAt: snapshots.updatedAt, freshness: freshness)
        }
        .padding(16)
    }
}

private struct ProviderDetailSection: View {
    let provider: ProviderKind
    let snapshot: UsageSnapshot?
    let entryDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(provider.displayName)
                .font(.subheadline.bold())

            if let windows = snapshot?.windows, !windows.isEmpty {
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    VStack(alignment: .leading, spacing: 1) {
                        BarGauge(
                            title: window.windowKind.displayName,
                            percent: window.percent,
                            severity: WindowSeverity.classify(window),
                            showsSeverityGlyph: true,
                            barHeight: 8
                        )
                        ResetCountdownText(window: window, now: entryDate)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let extraUsage = snapshot?.extraUsage, extraUsage.isEnabled == false, let spendPercent = extraUsage.spendPercent {
                    Text("Crédits complémentaires : \(spendPercent.roundedPercentText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let resetCredits = snapshot?.resetCredits {
                    Text("Crédits de reset disponibles : \(resetCredits.availableCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Non connecté")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared footer/banner pieces

private struct FreshnessFooter: View {
    let updatedAt: Date
    let freshness: SnapshotFreshnessLevel

    var body: some View {
        HStack(spacing: 4) {
            if let banner = freshness.widgetBannerMessage {
                Image(systemName: "clock.badge.exclamationmark")
                Text(banner)
            }
            Spacer(minLength: 0)
            // Native, auto-updating relative text — costs no timeline-reload budget,
            // unlike recomputing a string on a schedule would (see
            // `SnapshotFreshness.relativeLabel`'s doc comment).
            Text("à jour ") + Text(updatedAt, style: .relative)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private struct ReconnectBanner: View {
    let providers: [ProviderKind]

    var body: some View {
        Label(
            "Reconnecter \(providers.map(\.displayName).joined(separator: ", "))",
            systemImage: "person.crop.circle.badge.exclamationmark"
        )
        .font(.caption2.bold())
        .foregroundStyle(.orange)
        .widgetAccentable()
    }
}
