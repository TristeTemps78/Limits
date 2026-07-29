import SwiftUI
import LimitsCore

/// Which visual the dashboard uses for a usage window — the "style de jauge" setting
/// from the T2.4 brief. Kept in the App target (not `LimitsCore`): this is a pure
/// rendering choice with no logic to test, so putting it in `LimitsCore` would just
/// be process overhead for AGENTS.md rule 4's sake without any real benefit.
enum GaugeStyle: String, CaseIterable, Identifiable {
    case ring
    case bar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ring: return "Anneau"
        case .bar: return "Barre"
        }
    }
}

/// Renders one window's percent as either a ring or a bar, per `GaugeStyle`. Purely
/// presentational. The percent *text* comes from `Double.roundedPercentText`
/// (`LimitsCore/PercentFormatting.swift`) — the one rounding rule shared with the
/// widget (T2.3), so the same fetch never reads "8%" on one and "9%" on the other.
/// The 0-1 fill fraction below is drawing-only, not displayed text, so it's computed
/// locally the same way `Widgets/Gauges/RingGauge.swift`/`BarGauge.swift` do (there's
/// nothing to disagree about here — clamping a value already known to be 0-100).
struct UsageGaugeView: View {
    let percent: Double
    let style: GaugeStyle
    let tint: Color

    private var clampedFraction: Double {
        min(max(percent, 0), 100) / 100
    }

    var body: some View {
        switch style {
        case .ring:
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: clampedFraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(percent.roundedPercentText)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .frame(width: 48, height: 48)

        case .bar:
            VStack(alignment: .leading, spacing: 2) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tint.opacity(0.2))
                        Capsule()
                            .fill(tint)
                            .frame(width: geometry.size.width * clampedFraction)
                    }
                }
                .frame(height: 8)
                Text(percent.roundedPercentText)
                    .font(.caption2)
            }
        }
    }
}
