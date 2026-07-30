import AppKit
import SwiftUI

/// Install help for a tool Toki could not find.
///
/// The two capabilities used here are both narrow and live only in this file:
/// * the pasteboard is **written** (never read), and only with a compile-time command
///   string from `ToolInstallGuide`;
/// * `NSWorkspace.open` receives only the hardcoded documentation URL — no string
///   interpolation, no value from config or logs.
///
/// Toki never executes the install command itself; the user runs it in their own shell.
struct InstallHelpCard: View {
    let guide: ToolInstallGuide

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(guide.title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))

            Text(guide.note)
                .font(.system(size: 8.5, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let command = guide.command {
                Text(command)
                    .font(.system(size: 9, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 6))
            }

            HStack(spacing: 6) {
                if let command = guide.command {
                    Button(didCopy ? "복사됨" : "명령 복사") { copy(command) }
                        .buttonStyle(.glass)
                }
                Button("공식 안내 열기") { NSWorkspace.shared.open(guide.documentation) }
                    .buttonStyle(.glass)
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 8))
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        didCopy = true
    }
}
