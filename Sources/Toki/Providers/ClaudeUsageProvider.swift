import Foundation

/// A single billable Claude Code assistant response, distilled from a session log.
struct ClaudeUsageEntry: Sendable {
    let timestamp: Date
    /// Stable identity used to drop records duplicated across resumed sessions.
    let dedupeKey: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheWrite5mTokens: Int
    let cacheWrite1hTokens: Int
    let cacheReadTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheWrite5mTokens + cacheWrite1hTokens + cacheReadTokens
    }

    var costUSD: Double {
        Pricing.costUSD(
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWrite5mTokens: cacheWrite5mTokens,
            cacheWrite1hTokens: cacheWrite1hTokens,
            cacheReadTokens: cacheReadTokens
        )
    }
}

/// Derives Claude Code usage from local session logs.
///
/// Claude does not publish numeric quota limits and does not record a usage
/// percentage locally, so the percentages here are self-calibrated: the ceiling
/// is either configured explicitly or taken from the heaviest window observed in
/// the lookback range. Every window this provider emits is marked estimated.
enum ClaudeUsageProvider {
    static let providerID = "claude"
    static let displayName = "Claude Code"
    static let sessionWindowDuration: TimeInterval = 5 * 60 * 60
    static let weeklyWindowDays = 7

    /// Only assistant records carry this field, so it is a cheap pre-filter that
    /// skips the vast majority of lines before any JSON parsing happens.
    private static let usageNeedle = Array("cache_read_input_tokens".utf8)

    private static var projectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects")
    }

    private static var accountFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude.json")
    }

    /// `official` — when present, its windows replace the locally estimated ones;
    /// token totals and cost always come from the local logs, which the CLI does not
    /// report. `officialFailure` is surfaced only when there is no official reading.
    static func read(
        config: WidgetConfig,
        now: Date,
        official: ClaudeOfficialUsage?,
        officialFailure: String?
    ) -> ProviderUsage {
        let root = projectsRoot
        guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else {
            return .unavailable(
                id: providerID,
                displayName: displayName,
                symbol: "sparkle",
                reason: "~/.claude/projects 를 찾을 수 없습니다"
            )
        }

        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -config.lookbackDays, to: now) else {
            return .unavailable(
                id: providerID,
                displayName: displayName,
                symbol: "sparkle",
                reason: "조회 기간을 계산할 수 없습니다"
            )
        }

        let entries = loadEntries(under: root, since: cutoff)
        guard !entries.isEmpty || official != nil else {
            return .unavailable(
                id: providerID,
                displayName: displayName,
                symbol: "sparkle",
                reason: officialFailure ?? "최근 \(config.lookbackDays)일간 사용 기록이 없습니다"
            )
        }

        return assemble(
            entries: entries,
            config: config,
            now: now,
            calendar: calendar,
            official: official,
            officialFailure: officialFailure
        )
    }

    // MARK: - Log loading

    private static func loadEntries(under root: URL, since cutoff: Date) -> [ClaudeUsageEntry] {
        let parser = TimestampParser()
        var byKey: [String: ClaudeUsageEntry] = [:]

        for file in JSONLReader.sessionFiles(under: root, modifiedSince: cutoff) {
            // A read failure on one session log must not blank the whole widget.
            try? JSONLReader.forEachLine(of: file, containing: usageNeedle) { line in
                guard let entry = parse(line: line, parser: parser), entry.timestamp >= cutoff else { return }
                byKey[entry.dedupeKey] = entry
            }
        }

        return byKey.values.sorted { $0.timestamp < $1.timestamp }
    }

    private static func parse(line: Data, parser: TimestampParser) -> ClaudeUsageEntry? {
        guard let root = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              root["type"] as? String == "assistant",
              let message = root.object("message"),
              let usage = message.object("usage"),
              let timestampText = root["timestamp"] as? String,
              let timestamp = parser.date(from: timestampText)
        else { return nil }

        let write5m: Int
        let write1h: Int
        if let cacheCreation = usage.object("cache_creation") {
            write5m = cacheCreation.intValue("ephemeral_5m_input_tokens") ?? 0
            write1h = cacheCreation.intValue("ephemeral_1h_input_tokens") ?? 0
        } else {
            // Older logs only carry the aggregate field; treat it as 5-minute cache.
            write5m = usage.intValue("cache_creation_input_tokens") ?? 0
            write1h = 0
        }

        let outputTokens = usage.intValue("output_tokens") ?? 0
        let dedupeKey = (root["requestId"] as? String)
            ?? (root["uuid"] as? String)
            ?? "\(timestampText)#\(outputTokens)"

        return ClaudeUsageEntry(
            timestamp: timestamp,
            dedupeKey: dedupeKey,
            model: message["model"] as? String ?? "unknown",
            inputTokens: usage.intValue("input_tokens") ?? 0,
            outputTokens: outputTokens,
            cacheWrite5mTokens: write5m,
            cacheWrite1hTokens: write1h,
            cacheReadTokens: usage.intValue("cache_read_input_tokens") ?? 0
        )
    }

    // MARK: - Aggregation

    private static func assemble(
        entries: [ClaudeUsageEntry],
        config: WidgetConfig,
        now: Date,
        calendar: Calendar,
        official: ClaudeOfficialUsage?,
        officialFailure: String?
    ) -> ProviderUsage {
        let allWindows = SessionWindows.windows(
            from: entries,
            duration: sessionWindowDuration,
            calendar: calendar
        )
        let activeWindow = allWindows.last { $0.contains(now) }
        let completedWindows = allWindows.filter { !$0.contains(now) }

        let sessionLimit = config.claudeFiveHourTokenLimit
            ?? max(completedWindows.map(\.totalTokens).max() ?? 0, activeWindow?.totalTokens ?? 0)

        let dailyTotals = SessionWindows.dailyTotals(from: entries, calendar: calendar)
        let weekStart = calendar.date(byAdding: .day, value: -weeklyWindowDays, to: now) ?? now
        let weekTokens = entries.filter { $0.timestamp >= weekStart }.reduce(0) { $0 + $1.totalTokens }
        let weeklyLimit = config.claudeWeeklyTokenLimit
            ?? max(
                SessionWindows.rollingMaximum(
                    dailyTotals: dailyTotals,
                    windowDays: weeklyWindowDays,
                    calendar: calendar
                ),
                weekTokens
            )

        let today = calendar.startOfDay(for: now)
        let todayEntries = entries.filter { $0.timestamp >= today }

        return ProviderUsage(
            id: providerID,
            displayName: displayName,
            symbol: "sparkle",
            planLabel: planLabel(),
            windows: official?.windows ?? [
                window(
                    id: "claude-session",
                    label: "5시간",
                    used: activeWindow?.totalTokens ?? 0,
                    limit: sessionLimit,
                    resetsAt: activeWindow?.end
                ),
                window(
                    id: "claude-weekly",
                    label: "주간",
                    used: weekTokens,
                    limit: weeklyLimit,
                    resetsAt: nil
                )
            ],
            todayTokens: todayEntries.reduce(0) { $0 + $1.totalTokens },
            todayCostUSD: todayEntries.reduce(0.0) { $0 + $1.costUSD },
            note: note(official: official, officialFailure: officialFailure, config: config),
            failure: nil
        )
    }

    private static func note(
        official: ClaudeOfficialUsage?,
        officialFailure: String?,
        config: WidgetConfig
    ) -> String {
        guard official == nil else {
            return "비율은 claude CLI 가 보고한 공식 수치입니다 (토큰·비용은 로컬 로그 집계)"
        }
        let base = "비율은 최근 \(config.lookbackDays)일 로그로 자체 보정한 추정값입니다"
        guard let officialFailure else { return base }
        return "\(base) · 공식 수치 실패: \(officialFailure)"
    }

    private static func window(
        id: String,
        label: String,
        used: Int,
        limit: Int,
        resetsAt: Date?
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            label: label,
            fraction: limit > 0 ? min(1.0, Double(used) / Double(limit)) : nil,
            usedTokens: used,
            limitTokens: limit > 0 ? limit : nil,
            resetsAt: resetsAt,
            isEstimated: true
        )
    }

    // MARK: - Plan

    private static func planLabel() -> String? {
        guard let data = try? Data(contentsOf: accountFile),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let account = root.object("oauthAccount"),
              let tier = account["organizationRateLimitTier"] as? String
                ?? account["userRateLimitTier"] as? String
        else { return nil }

        let normalized = tier.lowercased()
        if normalized.contains("max_20x") { return "Max 20x" }
        if normalized.contains("max_5x") { return "Max 5x" }
        if normalized.contains("team") { return "Team" }
        if normalized.contains("enterprise") { return "Enterprise" }
        if normalized.contains("pro") { return "Pro" }
        if normalized.contains("free") { return "Free" }
        return nil
    }
}
