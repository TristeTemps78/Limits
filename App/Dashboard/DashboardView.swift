import SwiftUI
import LimitsCore

/// The dashboard tab. Freshness ages and countdowns need to visibly move without the
/// view model publishing a change every second — `TimelineView` supplies a live `now`
/// every 60s, which `ProviderDashboardSectionView` feeds into `SnapshotFreshness`/
/// `WindowPresentation` (both `LimitsCore`, shared with the widget — T2.3) to render
/// freshness labels and reset countdowns identically to how the widget renders them.
struct DashboardView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var model = DashboardViewModel()

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView {
                    if model.claudeConnected == false && model.codexConnected == false {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            if let snapshotError = model.lastSnapshotError {
                                appGroupWarningBanner(message: snapshotError.widgetDiagnosticMessage)
                            }

                            if model.claudeConnected {
                                ProviderDashboardSectionView(
                                    title: "Claude",
                                    state: claudeState,
                                    gaugeStyle: settings.gaugeStyle,
                                    now: context.date
                                )
                            }

                            if model.codexConnected {
                                ProviderDashboardSectionView(
                                    title: "Codex",
                                    state: codexState,
                                    gaugeStyle: settings.gaugeStyle,
                                    now: context.date
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .refreshable {
                await manualRefresh()
            }
            .navigationTitle("Limits")
            .alert(
                "Rafraîchissement",
                isPresented: Binding(
                    get: { model.refreshNotice != nil },
                    set: { if !$0 { model.refreshNotice = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.refreshNotice ?? "")
            }
        }
        .task {
            // Les seuils viennent des réglages : le premier plan doit programmer les mêmes
            // notifications que la tâche de fond, sinon un franchissement constaté à
            // l'écran ne serait jamais annoncé.
            model.notificationThresholds = [settings.warningThresholdPercent, settings.criticalThresholdPercent]
            model.refreshConnectionStatus()
            await model.fetchAllIfNeeded(trigger: .scheduled)
        }
        .onChange(of: settings.warningThresholdPercent) { _, newValue in
            model.notificationThresholds = [newValue, settings.criticalThresholdPercent]
        }
        .onChange(of: settings.criticalThresholdPercent) { _, newValue in
            model.notificationThresholds = [settings.warningThresholdPercent, newValue]
        }
        .onReceive(NotificationCenter.default.publisher(for: .limitsProviderConnectionChanged)) { _ in
            model.refreshConnectionStatus()
            Task { await model.fetchAllIfNeeded(trigger: .manualRefresh) }
        }
    }

    private var claudeState: AppProviderDashboardState {
        AppProviderDashboardStateBuilder.build(
            isConnected: model.claudeConnected,
            lastSnapshot: model.claudeRuntime.lastSnapshot,
            pollingState: model.claudeRuntime.pollingState,
            lastOutcome: model.claudeRuntime.lastOutcome
        )
    }

    private var codexState: AppProviderDashboardState {
        AppProviderDashboardStateBuilder.build(
            isConnected: model.codexConnected,
            lastSnapshot: model.codexRuntime.lastSnapshot,
            pollingState: model.codexRuntime.pollingState,
            lastOutcome: model.codexRuntime.lastOutcome
        )
    }

    private func manualRefresh() async {
        await model.fetchAllIfNeeded(trigger: .manualRefresh)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Aucun compte connecté")
                .font(.headline)
            Text("Connecte Claude et/ou Codex pour voir tes limites d'usage ici.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ClaudeConnectView()
            Divider()
            CodexConnectView()
        }
        .padding()
    }

    /// `message` reuses `SnapshotStoreError.widgetDiagnosticMessage` (`WidgetCopy.swift`,
    /// T2.3) so the wording matches whatever the widget itself would show for the
    /// same underlying failure — e.g. "App Group indisponible" vs "Mets à jour l'app"
    /// are genuinely different situations (see that type's own doc comment) and
    /// deserve different, but consistently-worded, messages.
    private func appGroupWarningBanner(message: String) -> some View {
        Label(
            "Les widgets ne recevront pas de données à jour (\(message)). L'app reste utilisable.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(.orange)
    }
}
