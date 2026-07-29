import SwiftUI
import LimitsCore

/// T1.1 dérisquage screen. Shows, per shared-data channel, what was just written and
/// what reads back — independently, so a failure on one channel (e.g. Keychain) never
/// masks success on another (e.g. the file). This is the grid of information Tristan
/// reads off the sideloaded device to answer T1.1's real question: which channel (if
/// any) survives Sideloadly's re-signing.
struct DiagnosticsView: View {
    @StateObject private var model = DiagnosticsViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Identifiants") {
                    LabeledContent("App Group demandé", value: model.appGroupIdentifier)
                    LabeledContent("Entitlement lu à l'exécution", value: grantedGroupsText)
                }

                Section("Canaux") {
                    ForEach(SharedChannel.allCases, id: \.self) { channel in
                        ChannelRow(
                            channel: channel,
                            writeResult: model.writeResults[channel],
                            readResult: model.readResults[channel]
                        )
                    }
                }

                Section {
                    if let lastActionAt = model.lastActionAt {
                        LabeledContent("Dernière écriture", value: lastActionAt.formatted(date: .omitted, time: .standard))
                    }
                    LabeledContent("Compteur", value: "\(model.writeCount)")
                }

                Section {
                    Button("Écrire maintenant") {
                        model.writeNow()
                    }
                    Button("Recharger les timelines des widgets") {
                        model.reloadWidgets()
                    }
                }
            }
            .navigationTitle("Diagnostic App Group")
            .task {
                model.onAppear()
            }
        }
    }

    private var grantedGroupsText: String {
        guard let groups = model.grantedApplicationGroups, !groups.isEmpty else {
            return "aucun (entitlement absent ou illisible)"
        }
        return groups.joined(separator: ", ")
    }
}

private struct ChannelRow: View {
    let channel: SharedChannel
    let writeResult: DiagnosticResult<Void>?
    let readResult: DiagnosticResult<SharedPayload>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(channel.displayName)
                .font(.headline)

            statusLine(label: "Écriture", writeResult: writeResult)
            statusLine(label: "Lecture", readResult: readResult)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusLine(label: String, writeResult: DiagnosticResult<Void>?) -> some View {
        switch writeResult {
        case .none:
            Text("\(label) : pas encore tentée")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .ok:
            Label("\(label) : OK", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let reason):
            Label("\(label) : \(reason)", systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func statusLine(label: String, readResult: DiagnosticResult<SharedPayload>?) -> some View {
        switch readResult {
        case .none:
            Text("\(label) : pas encore tentée")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .ok(let payload):
            Label(
                "\(label) : OK — compteur \(payload.writeCount), il y a \(payload.ageInSeconds())s",
                systemImage: "checkmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.green)
        case .failure(let reason):
            Label("\(label) : \(reason)", systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
