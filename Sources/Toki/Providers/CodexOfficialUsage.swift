import Foundation

/// Live Codex quota figures, as reported by Codex itself.
struct CodexOfficialUsage: Sendable {
    let windows: [UsageWindow]
    let planType: String?
    let capturedAt: Date
}

/// Reads current Codex usage by asking `codex app-server`, the same JSON-RPC surface the
/// Codex TUI's `/usage` command uses.
///
/// Why this exists: the session logs Codex writes only carry a rate-limit snapshot from
/// the moment Codex last made a request, so as soon as usage happens anywhere else — the
/// desktop app, the web, another machine — the local figure freezes and drifts. A
/// 28-hour-old reading of "72% left" was observed while the account actually had 47%.
///
/// Why this route is cheap: `account/rateLimits/read` is a pure query. Unlike the Claude
/// path, which spends one real request per refresh, this consumes **no tokens and no
/// quota** — it reads counters the server already keeps.
///
/// Constrained the same way as the Claude reader:
/// * the executable comes from a fixed list of absolute paths, never `PATH`, the
///   environment, or the config file;
/// * arguments and both JSON-RPC payloads are compile-time literals, so nothing a caller
///   supplies can reach the child;
/// * no shell is involved, so there is nothing to quote or escape;
/// * stdout is capped, and the process is killed on timeout or as soon as the one reply
///   we came for arrives.
///
/// As with the Claude CLI, Toki never touches a credential: `codex app-server`
/// authenticates inside its own process and Toki only parses numbers out of its stdout.
enum CodexOfficialUsageReader {
    private static let outputByteLimit = 256 * 1024
    /// Short on purpose. This runs on the refresh cadence, so a wedged Codex install
    /// should fall back to the log snapshot quickly rather than stall the panel.
    private static let timeout: TimeInterval = 15

    /// Fixed, because exactly two requests are ever sent.
    private static let initializeID = 1
    private static let rateLimitsID = 2

    private static var candidateExecutables: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: ".local/bin/codex"),
            URL(filePath: "/opt/homebrew/bin/codex"),
            URL(filePath: "/usr/local/bin/codex"),
            URL(filePath: "/usr/bin/codex")
        ]
    }

    enum Outcome: Sendable {
        case usage(CodexOfficialUsage)
        case failure(String)
    }

    static func read(now: Date) -> Outcome {
        guard let executable = locateExecutable() else {
            return .failure("codex CLI 를 찾을 수 없습니다")
        }

        let run = query(executable: executable)
        guard let limits = run.limits else {
            return .failure(run.failure ?? "codex app-server 오류")
        }

        let windows = [limits.object("primary"), limits.object("secondary")]
            .enumerated()
            .compactMap { slot, payload in payload.flatMap { window(from: $0, slot: slot, now: now) } }

        guard !windows.isEmpty else {
            return .failure("응답에 사용률이 없습니다")
        }

        return .usage(
            CodexOfficialUsage(
                windows: windows,
                planType: limits["planType"] as? String,
                capturedAt: now
            )
        )
    }

    // MARK: - Process

    private static func locateExecutable() -> URL? {
        candidateExecutables.first { url in
            FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false))
        }
    }

    /// Collects stdout off the calling thread so the deadline holds even if the child
    /// never writes anything. `FileHandle.availableData` blocks until data or EOF, which
    /// on its own would hang past any timeout.
    private final class Transcript: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var found: [String: Any]?

        /// Returns true once there is nothing left worth reading.
        func append(_ chunk: Data) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            data.append(chunk)
            if let reply = Self.reply(withID: rateLimitsID, in: data) {
                found = reply
                return true
            }
            return data.count >= outputByteLimit
        }

        var result: [String: Any]? {
            lock.lock()
            defer { lock.unlock() }
            return found
        }

        /// Responses are newline-delimited JSON — not LSP-style `Content-Length` framing —
        /// and arrive interleaved with unsolicited notifications, so every line is parsed
        /// and matched on its id rather than assuming an order.
        private static func reply(withID id: Int, in data: Data) -> [String: Any]? {
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let object = (try? JSONSerialization.jsonObject(with: Data(line)))
                        as? [String: Any],
                      object.intValue("id") == id
                else { continue }
                return object.object("result")
            }
            return nil
        }
    }

    private static func query(executable: URL) -> (limits: [String: Any]?, failure: String?) {
        let process = Process()
        process.executableURL = executable
        // Compile-time literal, like the Claude reader's arguments.
        process.arguments = ["app-server"]
        // Same reasoning as `ClaudeOfficialUsageReader`: an app launched from Finder has
        // `/` as its working directory, and a child inheriting that can wander into
        // protected locations, raising permission prompts in Toki's name.
        process.currentDirectoryURL = FileManager.default.temporaryDirectory

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return (nil, "codex app-server 실행 실패")
        }

        guard writeRequests(to: input) else {
            process.terminate()
            return (nil, "codex app-server 요청 전송 실패")
        }

        let transcript = Transcript()
        let finished = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .utility).async {
            let handle = output.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }          // EOF
                if transcript.append(chunk) { break }
            }
            finished.signal()
        }

        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        // Terminated either way: this is a long-lived server process and we only ever
        // wanted one reply out of it.
        process.terminate()

        guard let result = transcript.result else {
            return (nil, timedOut ? "codex app-server 응답 시간 초과" : "사용률 응답을 받지 못했습니다")
        }
        guard let limits = result.object("rateLimits") else {
            return (nil, "응답에 rateLimits 가 없습니다")
        }
        return (limits, nil)
    }

    /// Both payloads are built here rather than assembled from anything external, so the
    /// bytes crossing into the child are fixed at compile time apart from Toki's own
    /// version string.
    private static func writeRequests(to pipe: Pipe) -> Bool {
        let requests: [[String: Any]] = [
            [
                "jsonrpc": "2.0",
                "id": initializeID,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "toki",
                        "title": "Toki",
                        "version": UpdateChecker.currentVersion
                    ]
                ]
            ],
            [
                "jsonrpc": "2.0",
                "id": rateLimitsID,
                "method": "account/rateLimits/read",
                "params": [String: Any]()
            ]
        ]

        var payload = Data()
        for request in requests {
            guard let line = try? JSONSerialization.data(withJSONObject: request) else { return false }
            payload.append(line)
            payload.append(UInt8(ascii: "\n"))
        }

        do {
            try pipe.fileHandleForWriting.write(contentsOf: payload)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Parsing

    /// The JSON-RPC surface spells these fields in camelCase; the session logs spell the
    /// same values in snake_case, which `CodexUsageProvider` parses.
    private static func window(from payload: [String: Any], slot: Int, now: Date) -> UsageWindow? {
        guard let percent = payload.doubleValue("usedPercent") else { return nil }
        let minutes = payload.intValue("windowDurationMins")

        return UsageWindow(
            id: "codex-window-\(slot)",
            label: minutes.map(CodexUsageProvider.label(forWindowMinutes:))
                ?? (slot == 0 ? "1차 한도" : "2차 한도"),
            fraction: min(1.0, max(0.0, percent / 100.0)),
            usedTokens: nil,
            limitTokens: nil,
            resetsAt: payload.doubleValue("resetsAt").map { Date(timeIntervalSince1970: $0) },
            isEstimated: false
        )
    }
}
