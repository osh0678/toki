import AppKit
import SwiftUI

/// Shown in settings when a newer release exists.
///
/// Two modes, and which one applies is visible rather than implied:
/// * **manual** (the default) — both buttons hand a hardcoded URL from `UpdateChecker`
///   to the browser. Toki downloads nothing and never touches its own bundle.
/// * **automatic** — only when the user has switched auto-install on *and* a release
///   signing key is compiled in. The card then reports what the background install is
///   doing, and offers the restart rather than performing it unasked.
struct UpdateCard: View {
    let update: AvailableUpdate
    let currentVersion: String
    let install: UpdateInstallState
    let onRestart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            Text(explanation)
                .font(.system(size: 8.5, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        // Untinted for the same reason as `ProviderCard`: a tinted surface changes colour
        // on the first click. The icon carries the signal.
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(iconColour)
            Text("새 버전 \(update.version)")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            Spacer(minLength: 4)
            if isWorking {
                ProgressView().controlSize(.mini)
            }
            Text("현재 \(currentVersion)")
                .font(.system(size: 8.5, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            switch install {
            case .installed:
                Button("지금 재시작", action: onRestart)
                    .buttonStyle(.glassProminent)
            case .downloading, .verifying:
                // No download button while one is already in flight: pressing it would
                // start a second, unrelated copy in the browser.
                EmptyView()
            case .idle, .failed:
                Button("다운로드") { NSWorkspace.shared.open(update.downloadURL) }
                    .buttonStyle(.glassProminent)
            }

            Button("변경사항") { NSWorkspace.shared.open(update.releaseNotesURL) }
                .buttonStyle(.glass)
        }
        .font(.system(size: 9.5, weight: .medium, design: .rounded))
    }

    private var isWorking: Bool {
        switch install {
        case .downloading, .verifying: true
        default: false
        }
    }

    private var iconName: String {
        switch install {
        case .installed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "arrow.down.circle.fill"
        }
    }

    private var iconColour: Color {
        switch install {
        case .failed: Theme.amber
        default: Theme.leaf
        }
    }

    private var explanation: String {
        switch install {
        case .idle:
            "다운로드하면 브라우저로 dmg 를 받습니다. 열어서 Toki 를 Applications 로 드래그하면 교체됩니다."
        case .downloading:
            "백그라운드로 받는 중입니다. 서명을 확인하기 전에는 아무것도 교체하지 않습니다."
        case .verifying:
            "서명을 확인하는 중입니다. 확인에 실패하면 받은 파일은 그대로 버립니다."
        case .installed(let version):
            "\(version) 설치를 마쳤습니다. 지금 실행 중인 것은 아직 이전 버전이라, 다시 시작해야 적용됩니다."
        case .failed(let reason):
            "자동 설치에 실패했습니다 — \(reason). 아래에서 직접 받을 수 있습니다."
        }
    }
}
