import SwiftUI
import LimitsCore

/// The dashboard tab. Freshness ages and countdowns need to visibly move without the
/// view model publishing a change every second — `TimelineView` recomputes the
/// presentation state (`AppProviderDashboardStateBuilder.build`, a pure LimitsCore
/// function) against a live `now` every 60s, which is exactly what
/// `AppFreshnessFormatter`'s coarse-grained buckets need and no more.
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
                            if model.lastSnapshotWriteSucceeded == false {
                                appGroupWarningBanner
                            }

                            if model.claudeConnected {
                                ProviderDashboardSectionView(
                                    title: "Claude",
                                    state: claudeState(now: context.date),
                                    gaugeStyle: settings.gaugeStyle,
                                    tint: .orange
                                )
                            }

                            if model.codexConnected {
                                ProviderDashboardSectionView(
                                    title: "Codex",
                                    state: codexState(now: context.date),
                                    gaugeStyle: settings.gaugeStyle,
                                    tint: .teal
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
            model.refreshConnectionStatus()
            await model.fetchAllIfNeeded(trigger: .scheduled)
        }
        .onReceive(NotificationCenter.default.publisher(for: .limitsProviderConnectionChanged)) { _ in
            model.refreshConnectionStatus()
            Task { await model.fetchAllIfNeeded(trigger: .manualRefresh) }
        }
    }

    private func claudeState(now: Date) -> AppProviderDashboardState {
        AppProviderDashboardStateBuilder.build(
            isConnected: model.claudeConnected,
            lastSnapshot: model.claudeRuntime.lastSnapshot,
            pollingState: model.claudeRuntime.pollingState,
            lastOutcome: model.claudeRuntime.lastOutcome,
            now: now
        )
    }

    private func codexState(now: Date) -> AppProviderDashboardState {
        AppProviderDashboardStateBuilder.build(
            isConnected: model.codexConnected,
            lastSnapshot: model.codexRuntime.lastSnapshot,
            pollingState: model.codexRuntime.pollingState,
            lastOutcome: model.codexRuntime.lastOutcome,
            now: now
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

    private var appGroupWarningBanner: some View {
        Label(
            "Les widgets ne recevront pas de données à jour (App Group indisponible). L'app reste utilisable.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(.orange)
    }
}
