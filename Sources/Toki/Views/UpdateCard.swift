import AppKit
import SwiftUI

/// Shown in settings when a newer release exists.
///
/// Both buttons hand a hardcoded URL from `UpdateChecker` to the browser — Toki does
/// not download or install anything itself, so it can never overwrite its own bundle.
struct UpdateCard: View {
    let update: AvailableUpdate
    let currentVersion: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.leaf)
                Text("새 버전 \(update.version)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                Spacer(minLength: 4)
                Text("현재 \(currentVersion)")
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Text("다운로드하면 브라우저로 dmg 를 받습니다. 열어서 Toki 를 Applications 로 드래그하면 교체됩니다.")
                .font(.system(size: 8.5, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Button("다운로드") { NSWorkspace.shared.open(update.downloadURL) }
                    .buttonStyle(.glassProminent)
                Button("변경사항") { NSWorkspace.shared.open(update.releaseNotesURL) }
                    .buttonStyle(.glass)
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        // Untinted for the same reason as `ProviderCard`: a tinted surface changes colour
        // on the first click. The green download icon carries the signal.
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
}
