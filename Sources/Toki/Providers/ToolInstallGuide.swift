import Foundation

/// What to tell the user when a tool Toki depends on is not installed.
///
/// Toki deliberately does **not** run installers. Executing `brew`, `npm`, or a piped
/// shell script on the user's behalf would turn a read-only widget into an
/// arbitrary-code-execution path and void the subprocess guarantee in SECURITY.md.
/// So this offers a command to copy and a link to the official instructions, and lets
/// the user run it themselves in a terminal they control.
///
/// Commands are only stated when they can be stated with confidence — a wrong install
/// command is worse than no command at all.
struct ToolInstallGuide: Sendable {
    let title: String
    /// Copyable shell command, or nil when the official path is docs-only.
    let command: String?
    let documentation: URL
    let note: String

    static func guide(forProvider id: String) -> ToolInstallGuide? {
        switch id {
        case ClaudeUsageProvider.providerID: claudeCode
        case CodexUsageProvider.providerID: codexCLI
        default: nil
        }
    }

    /// Claude Code ships its own native installer whose script URL is not restated
    /// here — pointing at the official page avoids handing the user a stale one-liner.
    private static let claudeCode = ToolInstallGuide(
        title: "Claude Code 설치",
        command: nil,
        documentation: URL(string: "https://code.claude.com/docs")!,
        note: "공식 안내의 설치 방법을 따른 뒤 `claude` 를 한 번 실행해 로그인까지 마치면 됩니다."
    )

    private static let codexCLI = ToolInstallGuide(
        title: "Codex CLI 설치",
        command: "npm install -g @openai/codex",
        documentation: URL(string: "https://www.npmjs.com/package/@openai/codex")!,
        note: "설치 후 `codex` 를 한 번 실행해 세션을 만들면 사용률이 보입니다."
    )
}
