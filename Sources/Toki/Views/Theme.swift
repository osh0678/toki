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

    /// Colour for a bar that renders remaining headroom: cool while there is plenty
    /// left, warming as it drains.
    ///
    /// `warningRemaining` is user-configurable while the critical point is not, so the
    /// two can end up in the wrong order — a warning set to 5% would otherwise turn red
    /// before it ever turned amber. Clamping critical to sit at or below the warning
    /// keeps the sequence honest at every setting.
    static func barColor(
        forRemaining remaining: Double,
        accent: Color,
        warningRemaining: Double = lowRemaining
    ) -> Color {
        if remaining <= min(criticalRemaining, warningRemaining) { return ember }
        if remaining <= warningRemaining { return amber }
        return accent
    }
}

/// Carries the configured warning point down to whatever draws a bar.
///
/// Passed through the environment rather than added to every initialiser: `UsageBar`
/// sits two levels below the only view that holds the config, and threading one Double
/// through `ProviderCard` purely to forward it would put the value in signatures that
/// have no other use for it.
extension EnvironmentValues {
    @Entry var warningRemaining: Double = Theme.lowRemaining
}
