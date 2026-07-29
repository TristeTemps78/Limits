import SwiftUI
import LimitsCore

/// Codex's onboarding card. Unlike Claude, this flow completes itself (local
/// callback server + browser redirect) — the user just waits.
struct CodexConnectView: View {
    @StateObject private var model = CodexConnectViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Codex")
                    .font(.headline)
                Spacer()
                statusBadge
            }

            switch model.state {
            case .notConnected, .failed:
                Text("Connecte ton compte ChatGPT (Plus/Pro) pour voir tes limites Codex.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .failed(let message) = model.state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("Se connecter") {
                    model.startLogin()
                }

            case .connecting:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("En attente de la connexion dans le navigateur…")
                        .font(.caption)
                }
                Button("Annuler", role: .cancel) {
                    model.cancel()
                }

            case .exchangingToken:
                ProgressView("Connexion en cours…")

            case .connected:
                Text("Compte connecté.")
                    .font(.caption)
                    .foregroundStyle(.green)
                Button("Déconnecter", role: .destructive) {
                    model.disconnect()
                }
            }
        }
        .padding(.vertical, 4)
        .onDisappear {
            // The user navigated away mid-attempt (e.g. switched tabs) — same
            // cleanup as an explicit cancel, so the loopback listener never lingers
            // open for a screen that isn't visible anymore.
            if case .connecting = model.state {
                model.cancel()
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch model.state {
        case .connected:
            Label("Connecté", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .notConnected, .failed:
            Label("Non connecté", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .connecting, .exchangingToken:
            Label("En cours…", systemImage: "hourglass")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
