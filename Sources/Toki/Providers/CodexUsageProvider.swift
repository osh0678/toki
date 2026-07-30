import Foundation

/// Reads Codex CLI usage from the rate-limit snapshots Codex writes into its own
/// session logs. These percentages come from the Codex service, so unlike the
/// Claude provider they are reported as authoritative rather than estimated.
///
/// Security scope: this provider reads **only** `~/.codex/sessions`. Codex keeps its
/// OAuth tokens in `~/.codex/auth.json` and its settings in `~/.codex/config.toml`;
/// neither path is ever opened. Within a session log, only two numeric field groups
/// are extracted — `payload.rate_limits` and `payload.info.total_token_usage`. No
/// prompt text, tool output, or file content is read into the widget.
enum CodexUsageProvider {
    static let providerID = "codex"
    static let displayName = "Codex CLI"
    static let symbol = "hexagon.fill"

    private static let rateLimitNeedle = Array("rate_limits".utf8)
    private static let tokenUsageNeedle = Array("total_token_usage".utf8)
    /// How far back to look for the newest rate-limit snapshot.
    private static let snapshotLookbackDays = 7
    /// Cap on how many recent session files are probed for a snapshot.
    private static let maxProbedFiles = 8

    private static var sessionsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions")
    }

    static func read(now: Date) -> ProviderUsage {
        let root = sessionsRoot
        guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else {
            return .unavailable(
                id: providerID,
                displayName: displayName,
                symbol: symbol,
                reason: "~/.codex/sessions 를 찾을 수 없습니다"
            )
        }

        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -snapshotLookbackDays, to: now) ?? now
        let recentFiles = JSONLReader.sessionFiles(under: root, modifiedSince: cutoff)
        guard !recentFiles.isEmpty else {
            return .unavailable(
                id: providerID,
                displayName: displayName,
                symbol: symbol,
                reason: "최근 \(snapshotLookbackDays)일간 Codex 세션이 없습니다"
            )
        }

        guard let limits = latestRateLimits(in: recentFiles.prefix(maxProbedFiles)) else {
            return .unavailable(
                id: providerID,
                displayName: displayName,
                symbol: symbol,
                reason: "사용률 스냅샷을 찾지 못했습니다"
            )
        }

        let windows = [limits.object("primary"), limits.object("secondary")]
            .enumerated()
            .compactMap { slot, payload in payload.flatMap { window(from: $0, slot: slot, now: now) } }

        return ProviderUsage(
            id: providerID,
            displayName: displayName,
            symbol: symbol,
            planLabel: planLabel(limits["plan_type"] as? String),
            windows: windows,
            todayTokens: todayTokens(calendar: calendar, now: now),
            // Codex CLI usage is covered by a subscription, so a per-token figure
            // would be a fabricated number rather than a useful one.
            todayCostUSD: nil,
            note: windows.isEmpty
                ? "Codex 가 아직 사용률을 보고하지 않았습니다"
                : "Codex 서버가 보고한 공식 사용률입니다",
            failure: nil
        )
    }

    // MARK: - Snapshot lookup

    private static func latestRateLimits(in files: some Sequence<URL>) -> [String: Any]? {
        for file in files {
            guard let lines = try? JSONLReader.tailLines(of: file, containing: rateLimitNeedle) else { continue }
            // Newest record wins; a half-written trailing line simply fails to parse.
            for line in lines.reversed() {
                guard let root = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      let limits = root.object("payload")?.object("rate_limits")
                else { continue }
                return limits
            }
        }
        return nil
    }

    private static func window(from payload: [String: Any], slot: Int, now: Date) -> UsageWindow? {
        guard let percent = payload.doubleValue("used_percent") else { return nil }
        let minutes = payload.intValue("window_minutes")

        return UsageWindow(
            id: "codex-window-\(slot)",
            label: minutes.map(label(forWindowMinutes:)) ?? (slot == 0 ? "1차 한도" : "2차 한도"),
            fraction: min(1.0, max(0.0, percent / 100.0)),
            usedTokens: nil,
            limitTokens: nil,
            resetsAt: resetDate(from: payload, now: now),
            isEstimated: false
        )
    }

    private static func label(forWindowMinutes minutes: Int) -> String {
        switch minutes {
        case ..<60: "\(minutes)분"
        case 60: "1시간"
        case ..<1440: "\(minutes / 60)시간"
        case 1440: "일간"
        case 10080: "주간"
        default: "\(minutes / 1440)일"
        }
    }

    private static func resetDate(from payload: [String: Any], now: Date) -> Date? {
        if let epochSeconds = payload.doubleValue("resets_at") {
            return Date(timeIntervalSince1970: epochSeconds)
        }
        if let seconds = payload.doubleValue("resets_in_seconds") {
            return now.addingTimeInterval(seconds)
        }
        return nil
    }

    // MARK: - Token totals

    /// Sums each of today's sessions' final cumulative token count. Sessions that
    /// started yesterday and continued into today are counted in full, so treat this
    /// as "tokens across sessions touched today".
    private static func todayTokens(calendar: Calendar, now: Date) -> Int? {
        let today = calendar.startOfDay(for: now)
        var total = 0
        var sawAnything = false

        for file in JSONLReader.sessionFiles(under: sessionsRoot, modifiedSince: today) {
            guard let lines = try? JSONLReader.tailLines(of: file, containing: tokenUsageNeedle) else { continue }
            for line in lines.reversed() {
                guard let root = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      let usage = root.object("payload")?.object("info")?.object("total_token_usage"),
                      let tokens = usage.intValue("total_tokens")
                else { continue }
                total += tokens
                sawAnything = true
                break
            }
        }

        return sawAnything ? total : nil
    }

    // MARK: - Plan

    private static func planLabel(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "free": return "Free"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        default: return raw.capitalized
        }
    }
}
