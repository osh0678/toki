import SwiftUI

/// One quota window, drawn as an instrument rather than a progress bar.
///
/// Two deliberate choices:
/// * it reports **headroom left**, because a widget answers "can I keep working?";
/// * the meter is segmented, and consumed segments are left *empty* rather than
///   filled with grey — so the glass behind the panel shows through the graph. A
///   solid track would cover exactly the area the material is supposed to reveal.
///
/// No gradients, gloss overlays, or coloured shadows: the only colour is the lit
/// segments and the numeral, and it shifts warm only as the reserve drains.
struct UsageBar: View {
    let window: UsageWindow
    let accent: Color
    let now: Date

    @Environment(\.warningRemaining) private var warningRemaining

    private var used: Double { window.fraction ?? 0 }
    private var remaining: Double { max(0, 1 - used) }
    private var tint: Color {
        Theme.barColor(forRemaining: remaining, accent: accent, warningRemaining: warningRemaining)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            meter
            if let detail {
                Text(detail)
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(window.label)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if window.fraction == nil {
                Text("—")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int((remaining * 100).rounded()))")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(tint.opacity(0.7))
                        .baselineOffset(1)
                }
            }
        }
    }

    private var meter: some View {
        GeometryReader { geometry in
            segments(across: geometry.size.width)
        }
        .frame(height: Theme.meterHeight)
        .animation(.smooth(duration: 0.5), value: remaining)
    }

    private func segments(across width: CGFloat) -> some View {
        let count = Theme.meterSegmentCount
        let spacing = Theme.meterSegmentSpacing
        let segmentWidth = max(1.5, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
        let lit = window.fraction == nil ? 0 : Int((remaining * Double(count)).rounded())

        return HStack(spacing: spacing) {
            ForEach(0 ..< count, id: \.self) { index in
                RoundedRectangle(cornerRadius: segmentWidth / 2, style: .continuous)
                    .fill(fill(forSegment: index, lit: lit))
                    .frame(width: segmentWidth)
            }
        }
        .frame(height: Theme.meterHeight)
    }

    /// The final lit segment is softened so the reserve tapers off instead of ending
    /// on a hard edge, and unlit segments stay almost transparent.
    private func fill(forSegment index: Int, lit: Int) -> Color {
        guard index < lit else { return Color.primary.opacity(0.07) }
        return index == lit - 1 ? tint.opacity(0.55) : tint
    }

    private var detail: String? {
        var parts: [String] = []

        if let resetsAt = window.resetsAt,
           let countdown = Display.remainingDuration(until: resetsAt, from: now) {
            parts.append("\(countdown) 후 초기화")
        }
        if let usedTokens = window.usedTokens, let limit = window.limitTokens {
            parts.append("\(Display.tokens(usedTokens))/\(Display.tokens(limit))")
        }
        parts.append(window.isEstimated ? "추정" : "공식")

        return parts.isEmpty ? nil : parts.joined(separator: "   ")
    }
}
