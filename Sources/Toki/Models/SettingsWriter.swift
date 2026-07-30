import Foundation

/// Persists user settings back to `~/.config/toki/config.json`.
///
/// This is the **only** write Toki performs anywhere on disk. The destination is
/// `WidgetConfig.configURL`, which is hardcoded — no caller supplies a path — and the
/// payload is nothing but the handful of integers and one flag shown in the settings
/// UI. No credential, token, identifier, or log content is ever written.
enum SettingsWriter {
    /// Returns `nil` on success, or a short human-readable reason it failed.
    static func save(_ config: WidgetConfig) -> String? {
        let target = WidgetConfig.configURL

        var claude: [String: Any] = [:]
        if let fiveHour = config.claudeFiveHourTokenLimit { claude["fiveHourTokenLimit"] = fiveHour }
        if let weekly = config.claudeWeeklyTokenLimit { claude["weeklyTokenLimit"] = weekly }

        let payload: [String: Any] = [
            "refreshSeconds": config.refreshSeconds,
            "officialRefreshSeconds": config.officialRefreshSeconds,
            "useClaudeCLI": config.useClaudeCLI,
            "showClaude": config.showClaude,
            "showCodex": config.showCodex,
            "showMenuBarPercent": config.showMenuBarPercent,
            "panelOpacity": config.panelOpacity,
            "warningRemainingPercent": config.warningRemainingPercent,
            "checkForUpdates": config.checkForUpdates,
            "autoInstallUpdates": config.autoInstallUpdates,
            "lookbackDays": config.lookbackDays,
            "claude": claude
        ]

        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
            // Atomic, so an interrupted save cannot leave a truncated config that would
            // silently reset every setting on the next launch.
            try data.write(to: target, options: [.atomic])
            return nil
        } catch {
            return "설정을 저장하지 못했습니다"
        }
    }
}
