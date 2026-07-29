import SwiftUI
import LimitsCore

/// Claude's onboarding card. This is an unusual flow (no redirect back into the
/// app), so the copy is explicit about what to do at each step rather than assuming
/// the user will guess it — per the T2.4 brief.
struct ClaudeConnectView: View {
    @StateObject private var model = ClaudeConnectViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claude")
                    .font(.headline)
                Spacer()
                statusBadge
            }

            switch model.state {
            case .notConnected, .failed:
                Text("Connecte ton compte Claude Pro/Max pour voir tes limites d'usage.")
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
                Text("1. Termine la connexion dans la fenêtre qui s'est ouverte.")
                Text("2. La page finale affiche un code au format « xxxx#yyyy » : copie-le en entier.")
                Text("3. Colle-le ci-dessous.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Colle le code ici (xxxx#yyyy)", text: $model.pastedCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Valider le code") {
                        model.submitPastedCode()
                    }
                    .disabled(model.pastedCode.isEmpty)
                    Button("Annuler", role: .cancel) {
                        model.cancel()
                    }
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
