import SwiftUI
import WidgetKit
import LimitsCore

/// A horizontal percent bar with a label row above it — used to list several windows
/// at once (`systemMedium`/`systemLarge`, one row per session/weekly window;
/// `accessoryRectangular`, compact).
///
/// Same non-chromatic-redundancy rule as `RingGauge`: `showsSeverityGlyph` adds the SF
/// Symbol next to the label so the severity distinction survives lock-screen
/// `.accented`/`.vibrant` rendering, which flattens `.widgetAccentable()` colors to one
/// tint.
struct BarGauge: View {
    let title: String
    let percent: Double
    let severity: WindowSeverity
    var showsSeverityGlyph: Bool = false
    var barHeight: CGFloat = 6

    private var clampedFraction: Double {
        min(max(percent, 0), 100) / 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if showsSeverityGlyph {
                    Image(systemName: severity.symbolName)
                        .font(.system(size: 9))
                        .foregroundStyle(severity.color)
                        .widgetAccentable()
                }
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(percentLabel)
                    .font(.caption2.bold())
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.25))
                    Capsule()
                        .fill(severity.color)
                        .widgetAccentable()
                        .frame(width: geometry.size.width * clampedFraction)
                }
            }
            .frame(height: barHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(percentLabel), \(severity.shortLabel)")
    }

    private var percentLabel: String {
        "\(Int(percent.rounded()))%"
    }
}
