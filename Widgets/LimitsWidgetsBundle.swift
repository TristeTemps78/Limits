import SwiftUI
import WidgetKit

/// Entry point of the LimitsWidgets extension.
///
/// This is a minimal scaffold (T0.2): a single trivial `StaticConfiguration` widget,
/// just enough to prove the extension target compiles, archives, and embeds correctly
/// into `Limits.app/PlugIns/`. The real TimelineProvider (reading the App Group
/// snapshot) and gauge views land in T2.3.
@main
struct LimitsWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LimitsPlaceholderWidget()
    }
}

struct LimitsPlaceholderWidget: Widget {
    let kind: String = "LimitsPlaceholderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LimitsPlaceholderProvider()) { entry in
            LimitsPlaceholderView(entry: entry)
        }
        .configurationDisplayName("Limits")
        .description("Scaffold placeholder — real content lands in T2.3.")
        .supportedFamilies([.systemSmall])
    }
}

struct LimitsPlaceholderEntry: TimelineEntry {
    let date: Date
}

struct LimitsPlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> LimitsPlaceholderEntry {
        LimitsPlaceholderEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (LimitsPlaceholderEntry) -> Void) {
        completion(LimitsPlaceholderEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LimitsPlaceholderEntry>) -> Void) {
        let entry = LimitsPlaceholderEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct LimitsPlaceholderView: View {
    let entry: LimitsPlaceholderEntry

    var body: some View {
        Text("Limits")
    }
}
