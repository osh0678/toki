import Foundation

/// Official Claude Code quota figures, as reported by the `claude` CLI itself.
struct ClaudeOfficialUsage: Sendable {
    let windows: [UsageWindow]
    let capturedAt: Date
}

/// Reads official usage by asking the locally installed `claude` CLI.
///
/// Why this route: Anthropic publishes no API for subscription window limits, and
/// the only endpoint that reports them is internal. Delegating to the CLI means
/// **Toki never touches a credential and never opens a socket** — the CLI performs
/// its own authentication in its own process, and Toki only parses numbers out of
/// its stdout.
///
/// The cost is one allow-listed subprocess. It is constrained hard:
/// * the executable is resolved from a fixed list of absolute paths, never from
///   `PATH`, the environment, or the config file;
/// * arguments are compile-time literals, so no caller input can reach them;
/// * no shell is involved, so there is nothing to quote or escape;
/// * stdin is `/dev/null`, stdout is capped, and the process is killed on timeout.
///
/// Each invocation counts as one request against the account, so the caller
/// throttles it (see `WidgetConfig.officialRefreshSeconds`).
enum ClaudeOfficialUsageReader {
    /// Maximum stdout we will buffer, to bound memory if the CLI misbehaves.
    private static let outputByteLimit = 256 * 1024
    private static let timeout: TimeInterval = 30

    /// Absolute locations we are willing to execute. Nothing extends this list at
    /// runtime — a hijacked `PATH` cannot redirect Toki to another binary.
    private static var candidateExecutables: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: ".local/bin/claude"),
            URL(filePath: "/opt/homebrew/bin/claude"),
            URL(filePath: "/usr/local/bin/claude"),
            URL(filePath: "/usr/bin/claude")
        ]
    }

    /// Either a parsed reading, or a short human-readable reason it is missing.
    enum Outcome: Sendable {
        case usage(ClaudeOfficialUsage)
        case failure(String)
    }

    static func read(now: Date) -> Outcome {
        guard let executable = locateExecutable() else {
            return .failure("claude CLI 를 찾을 수 없습니다")
        }

        let run = runCLI(executable: executable)
        guard let output = run.text else {
            return .failure(run.failure ?? "claude CLI 오류")
        }

        guard let report = extractReport(from: output) else {
            return .failure("CLI 응답을 해석하지 못했습니다")
        }

        let windows = parseWindows(from: report, now: now)
        guard !windows.isEmpty else {
            return .failure("CLI 응답에 사용률이 없습니다")
        }

        return .usage(ClaudeOfficialUsage(windows: windows, capturedAt: now))
    }

    // MARK: - Process

    private static func locateExecutable() -> URL? {
        candidateExecutables.first { url in
            FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false))
        }
    }

    private static func runCLI(executable: URL) -> (text: String?, failure: String?) {
        let process = Process()
        process.executableURL = executable
        // Compile-time literals only — nothing here is caller-controlled.
        process.arguments = ["-p", "/usage", "--output-format", "json"]
        process.standardInput = FileHandle.nullDevice

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return (nil, "claude CLI 실행 실패")
        }

        // Read before waiting, so a large response cannot deadlock on a full pipe.
        let data = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            return (nil, "claude CLI 응답 시간 초과")
        }
        guard process.terminationStatus == 0 else {
            return (nil, "claude CLI 오류 (exit \(process.terminationStatus))")
        }

        guard let text = String(data: data.prefix(outputByteLimit), encoding: .utf8) else {
            return (nil, "CLI 출력을 읽지 못했습니다")
        }
        return (text, nil)
    }

    /// `--output-format json` wraps the human-readable report in `result`.
    private static func extractReport(from output: String) -> String? {
        guard let data = output.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let result = root["result"] as? String
        else { return nil }
        return result
    }

    // MARK: - Parsing

    /// Matches lines such as:
    /// `Current session: 98% used · resets Jul 30 at 4pm (Asia/Seoul)`
    /// `Current week (all models): 28% used · resets Jul 31 at 3:59pm (Asia/Seoul)`
    ///
    /// The minutes are **optional**: the CLI omits them on the hour, printing `4pm`
    /// rather than `4:00pm`. Requiring them made the reset group fail to match, which
    /// dropped the countdown while still parsing the percentage — a silent partial
    /// match, so the card looked fine apart from the missing text.
    private static func pattern(forLabel label: String) -> String {
        "\(label):\\s*(\\d+)%\\s*used(?:[^\\n]*?resets\\s+([A-Za-z]{3}\\s+\\d{1,2}\\s+at\\s+\\d{1,2}(?::\\d{2})?[ap]m)\\s*\\(([^)]+)\\))?"
    }

    private static func parseWindows(from report: String, now: Date) -> [UsageWindow] {
        var windows: [UsageWindow] = []

        if let session = match(pattern(forLabel: "Current session"), in: report) {
            windows.append(
                window(
                    id: "claude-session",
                    label: "5시간",
                    percent: session.percent,
                    resetsAt: resetDate(from: session, now: now)
                )
            )
        }

        if let weekly = match(pattern(forLabel: "Current week \\(all models\\)"), in: report) {
            windows.append(
                window(
                    id: "claude-weekly",
                    label: "주간",
                    percent: weekly.percent,
                    resetsAt: resetDate(from: weekly, now: now)
                )
            )
        }

        // Only surfaced once it is actually in use, to keep the card uncluttered.
        if let fable = match(pattern(forLabel: "Current week \\(Fable\\)"), in: report), fable.percent > 0 {
            windows.append(
                window(
                    id: "claude-weekly-fable",
                    label: "주간 (Fable)",
                    percent: fable.percent,
                    resetsAt: resetDate(from: fable, now: now)
                )
            )
        }

        return windows
    }

    private static func window(id: String, label: String, percent: Int, resetsAt: Date?) -> UsageWindow {
        UsageWindow(
            id: id,
            label: label,
            fraction: min(1.0, max(0.0, Double(percent) / 100.0)),
            usedTokens: nil,
            limitTokens: nil,
            resetsAt: resetsAt,
            isEstimated: false
        )
    }

    private struct Reading {
        let percent: Int
        let resetText: String?
        let timeZoneID: String?
    }

    private static func match(_ pattern: String, in text: String) -> Reading? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let hit = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let percentRange = Range(hit.range(at: 1), in: text),
              let percent = Int(text[percentRange])
        else { return nil }

        let resetText = Range(hit.range(at: 2), in: text).map { String(text[$0]) }
        let zone = Range(hit.range(at: 3), in: text).map { String(text[$0]) }
        return Reading(percent: percent, resetText: resetText, timeZoneID: zone)
    }

    /// The CLI omits the year, so the current year is assumed and rolled forward if
    /// that would place the reset in the past.
    private static func resetDate(from reading: Reading, now: Date) -> Date? {
        guard let text = reading.resetText else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy MMM d 'at' h:mma"
        formatter.timeZone = reading.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        let year = calendar.component(.year, from: now)

        guard let parsed = formatter.date(from: "\(year) \(text)") else { return nil }
        if parsed.timeIntervalSince(now) < -86_400,
           let rolled = formatter.date(from: "\(year + 1) \(text)") {
            return rolled
        }
        return parsed
    }
}
