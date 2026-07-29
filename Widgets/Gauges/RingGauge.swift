import SwiftUI
import WidgetKit
import LimitsCore

/// A circular percent gauge — used wherever a single number is the star of the show
/// (`accessoryCircular`, `systemSmall`'s headline window).
///
/// Color alone never carries the severity distinction: the lock-screen `accessory*`
/// families render in `.accented`/`.vibrant` mode, where the system collapses every
/// `.widgetAccentable()` color to a single user-chosen tint — the whole point of
/// `showsSeverityBadge` is the non-chromatic (symbol + short word) redundancy that
/// survives that collapse.
struct RingGauge: View {
    let percent: Double
    let severity: WindowSeverity
    var lineWidth: CGFloat = 6
    var showsPercentText: Bool = true
    var showsSeverityBadge: Bool = false

    private var clampedFraction: Double {
        min(max(percent, 0), 100) / 100
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.25), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clampedFraction)
                .stroke(severity.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()

            if showsPercentText {
                Text(percentLabel)
                    .font(.system(.callout, design: .rounded).bold())
                    .minimumScaleFactor(0.6)
            }

            if showsSeverityBadge {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: severity.symbolName)
                            .font(.system(size: 9))
                            .foregroundStyle(severity.color)
                            .widgetAccentable()
                    }
                }
            }
        }
        .accessibilityLabel("\(percentLabel), \(severity.shortLabel)")
    }

    private var percentLabel: String {
        "\(Int(percent.rounded()))%"
    }
}
