import SwiftUI

/// Visual constants shared across the widget, so spacing and colour decisions live
/// in one place rather than being sprinkled through the views.
enum Theme {
    static let panelWidth: CGFloat = 296
    /// Used only if SwiftUI reports no intrinsic height yet, so the panel can never
    /// end up as a zero-height (invisible) window.
    static let panelFallbackHeight: CGFloat = 240
    static let panelCornerRadius: CGFloat = 20
    static let cardCornerRadius: CGFloat = 15
    static let outerPadding: CGFloat = 11
    static let cardPadding: CGFloat = 9
    static let cardSpacing: CGFloat = 7
    static let barHeight: CGFloat = 6

    /// The usage meter is drawn as discrete segments rather than a filled bar: the
    /// gaps and the unlit segments stay transparent, so the glass behind the panel
    /// shows through the graph instead of being covered by a grey track.
    static let meterSegmentCount = 30
    static let meterSegmentSpacing: CGFloat = 2
    static let meterHeight: CGFloat = 13

    /// Used-fractions at which a window starts reading as "getting tight" / "nearly out".
    static let warningThreshold = 0.75
    static let criticalThreshold = 0.90

    /// The same two points expressed as *remaining* headroom, which is what the bars
    /// actually render.
    static let lowRemaining = 1 - warningThreshold
    static let criticalRemaining = 1 - criticalThreshold

    static let carrot = Color(red: 0.95, green: 0.52, blue: 0.26)
    static let mint = Color(red: 0.36, green: 0.80, blue: 0.74)
    static let leaf = Color(red: 0.42, green: 0.76, blue: 0.51)
    static let amber = Color(red: 0.97, green: 0.74, blue: 0.28)
    static let ember = Color(red: 0.93, green: 0.35, blue: 0.35)

    static func accent(forProvider id: String) -> Color {
        switch id {
        case ClaudeUsageProvider.providerID: carrot
        case CodexUsageProvider.providerID: mint
        default: leaf
        }
    }

    /// Bars shift warm as they fill, so a glance is enough to read the state.
    static func barColor(forFraction fraction: Double, accent: Color) -> Color {
        if fraction >= criticalThreshold { return ember }
        if fraction >= warningThreshold { return amber }
        return accent
    }

    /// Colour for a bar that renders remaining headroom: cool while there is plenty
    /// left, warming as it drains.
    static func barColor(forRemaining remaining: Double, accent: Color) -> Color {
        barColor(forFraction: 1 - remaining, accent: accent)
    }
}
