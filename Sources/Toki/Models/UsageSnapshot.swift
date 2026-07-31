import Foundation

/// A single quota window reported by a provider (e.g. a 5-hour session window,
/// or a rolling weekly window).
struct UsageWindow: Identifiable, Sendable, Equatable {
    let id: String
    /// Short label shown next to the bar, e.g. "5시간" / "주간".
    let label: String
    /// 0...1. `nil` when the provider gives no usable percentage.
    let fraction: Double?
    let usedTokens: Int?
    let limitTokens: Int?
    let resetsAt: Date?
    /// True when `fraction` is derived locally rather than reported by the provider.
    let isEstimated: Bool

    static func == (lhs: UsageWindow, rhs: UsageWindow) -> Bool { lhs.id == rhs.id }
}

/// Everything the widget knows about one provider (Claude Code or Codex CLI).
struct ProviderUsage: Identifiable, Sendable {
    let id: String
    let displayName: String
    let symbol: String
    let planLabel: String?
    let windows: [UsageWindow]
    let todayTokens: Int?
    /// `nil` for subscription-only providers where per-token cost is not meaningful.
    let todayCostUSD: Double?
    /// Short caveat rendered under the card, or `nil`.
    let note: String?
    /// Non-fatal problem encountered while reading this provider's data.
    let failure: String?

    static func unavailable(
        id: String,
        displayName: String,
        symbol: String,
        reason: String
    ) -> ProviderUsage {
        ProviderUsage(
            id: id,
            displayName: displayName,
            symbol: symbol,
            planLabel: nil,
            windows: [],
            todayTokens: nil,
            todayCostUSD: nil,
            note: nil,
            failure: reason
        )
    }
}

/// One complete read of every provider.
struct UsageSnapshot: Sendable {
    let providers: [ProviderUsage]
    let capturedAt: Date

    static func placeholder(at date: Date) -> UsageSnapshot {
        UsageSnapshot(providers: [], capturedAt: date)
    }

    /// Highest usage fraction across every provider window — the single number the
    /// menu bar shows, so "am I about to run out?" is answerable at a glance.
    var peakFraction: Double? {
        providers.flatMap(\.windows).compactMap(\.fraction).max()
    }

    /// What the menu bar should show.
    ///
    /// Falls back to the tightest window whenever the chosen one is absent — the provider
    /// may be switched off, not installed, or simply not reporting that window yet (Codex
    /// often reports only a weekly limit). Showing the tightest figure is a better failure
    /// than showing nothing, and it is what the setting defaults to anyway.
    func menuBarFraction(preferring windowID: String?) -> Double? {
        guard let windowID,
              let chosen = providers.flatMap(\.windows).first(where: { $0.id == windowID }),
              let fraction = chosen.fraction
        else { return peakFraction }
        return fraction
    }

    /// Windows currently available to represent the menu bar, paired with the provider
    /// they belong to so settings can label them unambiguously.
    var selectableWindows: [(providerName: String, window: UsageWindow)] {
        providers.flatMap { provider in
            provider.windows.map { (provider.displayName, $0) }
        }
    }
}
