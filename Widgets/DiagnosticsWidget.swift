import SwiftUI
import WidgetKit
import LimitsCore

/// T1.1 dérisquage widget: reads the three shared-data channels and shows, per
/// channel, either the fresh value or the precise reason it failed. No network, no
/// token — read-only against the App Group (rule 8, AGENTS.md). Supports
/// `.systemSmall` (home screen) and `.accessoryRectangular` (lock screen) — the two
/// contexts likely to matter for the sideload test, one per requirement in T1.1.
struct DiagnosticsWidget: Widget {
    let kind = "LimitsDiagnosticsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DiagnosticsProvider()) { entry in
            DiagnosticsWidgetView(entry: entry)
        }
        .configurationDisplayName("Diagnostic App Group")
        .description("T1.1 : montre si l'app et le widget partagent encore des données après re-signature.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct DiagnosticsEntry: TimelineEntry {
    let date: Date
    let readResults: [SharedChannel: DiagnosticResult<SharedPayload>]
}

struct DiagnosticsProvider: TimelineProvider {
    private let facade = SharedChannelsFacade()

    func placeholder(in context: Context) -> DiagnosticsEntry {
        DiagnosticsEntry(date: Date(), readResults: [:])
    }

    func getSnapshot(in context: Context, completion: @escaping (DiagnosticsEntry) -> Void) {
        completion(DiagnosticsEntry(date: Date(), readResults: facade.readAll()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DiagnosticsEntry>) -> Void) {
        let entry = DiagnosticsEntry(date: Date(), readResults: facade.readAll())
        // Refresh reasonably often while we're actively diagnosing (T1.1 only) — this
        // is not subject to PollingPolicy since it never touches the network, only
        // the local App Group container (rule 8, AGENTS.md §6 applies to network
        // fetches, not local timeline refresh cadence).
        let nextRefresh = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct DiagnosticsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DiagnosticsEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Diag App Group")
                    .font(.caption2)
                    .bold()
                ForEach(SharedChannel.allCases, id: \.self) { channel in
                    Text(summaryLine(for: channel))
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("Diagnostic")
                    .font(.headline)
                ForEach(SharedChannel.allCases, id: \.self) { channel in
                    Text(summaryLine(for: channel))
                        .font(.caption)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(8)
        }
    }

    private func summaryLine(for channel: SharedChannel) -> String {
        let label = shortLabel(for: channel)
        switch entry.readResults[channel] {
        case .none:
            return "\(label) : —"
        case .ok(let payload):
            return "\(label) : #\(payload.writeCount), \(payload.ageInSeconds())s"
        case .failure(let reason):
            return "\(label) : \(reason)"
        }
    }

    private func shortLabel(for channel: SharedChannel) -> String {
        switch channel {
        case .userDefaults: return "Defaults"
        case .file: return "Fichier"
        case .keychain: return "Keychain"
        }
    }
}
