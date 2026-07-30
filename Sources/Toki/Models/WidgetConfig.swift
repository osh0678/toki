import Foundation

/// User-tunable settings, read from `~/.config/usage-widget/config.json`.
/// The file is optional — every field falls back to a default.
struct WidgetConfig: Sendable, Equatable {
    static let defaultRefreshSeconds = 60
    static let minRefreshSeconds = 10
    static let defaultLookbackDays = 14
    /// Official figures come from a `claude` CLI invocation, and each invocation
    /// counts as one request against the account — so this interval is deliberately
    /// much longer than the local log scan.
    static let defaultOfficialRefreshSeconds = 600
    static let minOfficialRefreshSeconds = 60
    /// Deliberately low: the point of the material is readability, not opacity.
    static let defaultPanelOpacity = 0.35

    /// How often the widget re-reads the logs.
    let refreshSeconds: Int
    /// How often official Claude figures are fetched via the CLI.
    let officialRefreshSeconds: Int
    /// Set false to skip the CLI entirely and fall back to local estimates.
    let useClaudeCLI: Bool
    /// Per-provider visibility. A hidden provider is not even read.
    let showClaude: Bool
    let showCodex: Bool
    /// Whether the menu bar shows the tightest remaining percentage next to the icon.
    let showMenuBarPercent: Bool
    /// 0 = bare glass (most transparent), 1 = fully opaque HUD material.
    let panelOpacity: Double
    /// How far back Claude session logs are scanned (bounds work on large histories).
    let lookbackDays: Int
    /// Explicit Claude 5-hour-window token limit. When nil, it is self-calibrated
    /// from the largest completed window observed in the lookback range.
    let claudeFiveHourTokenLimit: Int?
    /// Explicit Claude weekly token limit. Self-calibrated when nil.
    let claudeWeeklyTokenLimit: Int?

    static let fallback = WidgetConfig(
        refreshSeconds: defaultRefreshSeconds,
        officialRefreshSeconds: defaultOfficialRefreshSeconds,
        useClaudeCLI: true,
        showClaude: true,
        showCodex: true,
        showMenuBarPercent: true,
        panelOpacity: defaultPanelOpacity,
        lookbackDays: defaultLookbackDays,
        claudeFiveHourTokenLimit: nil,
        claudeWeeklyTokenLimit: nil
    )

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/toki/config.json")
    }

    /// Never throws — a missing or malformed config falls back to defaults so the
    /// widget always launches.
    ///
    /// The config deliberately exposes no path or URL fields: every location Toki
    /// reads is hardcoded relative to the home directory, so a tampered config
    /// cannot redirect it at an arbitrary file. Numeric values are clamped rather
    /// than trusted.
    static func load() -> WidgetConfig {
        guard let data = try? Data(contentsOf: configURL),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return .fallback }

        let claude = root.object("claude") ?? [:]
        let requested = root.intValue("refreshSeconds") ?? defaultRefreshSeconds
        let official = root.intValue("officialRefreshSeconds") ?? defaultOfficialRefreshSeconds
        let lookback = root.intValue("lookbackDays") ?? defaultLookbackDays

        return WidgetConfig(
            refreshSeconds: max(minRefreshSeconds, requested),
            officialRefreshSeconds: max(minOfficialRefreshSeconds, official),
            useClaudeCLI: root["useClaudeCLI"] as? Bool ?? true,
            showClaude: root["showClaude"] as? Bool ?? true,
            showCodex: root["showCodex"] as? Bool ?? true,
            showMenuBarPercent: root["showMenuBarPercent"] as? Bool ?? true,
            panelOpacity: min(1, max(0, (root["panelOpacity"] as? NSNumber)?.doubleValue
                ?? defaultPanelOpacity)),
            lookbackDays: max(1, min(90, lookback)),
            claudeFiveHourTokenLimit: claude.intValue("fiveHourTokenLimit").flatMap { $0 > 0 ? $0 : nil },
            claudeWeeklyTokenLimit: claude.intValue("weeklyTokenLimit").flatMap { $0 > 0 ? $0 : nil }
        )
    }
}
