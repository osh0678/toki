import SwiftUI

/// Settings pane shown inside the panel, in place of the provider cards.
///
/// Split per tool, because the two providers are not comparable: Claude needs a CLI
/// call to get official figures, while Codex already records them in its own logs and
/// has nothing to tune.
///
/// Edits apply to the running widget immediately; "저장" additionally writes them to
/// `~/.config/toki/config.json` so they survive a relaunch.
struct SettingsView: View {
    let store: UsageStore
    let onDone: () -> Void

    @State private var showClaude: Bool
    @State private var showCodex: Bool
    @State private var showMenuBarPercent: Bool
    @State private var panelOpacity: Double
    @State private var useCLI: Bool
    @State private var refreshSeconds: Int
    @State private var officialMinutes: Int
    @State private var lookbackDays: Int
    @State private var status: String?

    init(store: UsageStore, onDone: @escaping () -> Void) {
        self.store = store
        self.onDone = onDone
        let config = store.config
        _showClaude = State(initialValue: config.showClaude)
        _showCodex = State(initialValue: config.showCodex)
        _showMenuBarPercent = State(initialValue: config.showMenuBarPercent)
        _panelOpacity = State(initialValue: config.panelOpacity)
        _useCLI = State(initialValue: config.useClaudeCLI)
        _refreshSeconds = State(initialValue: config.refreshSeconds)
        _officialMinutes = State(initialValue: max(1, config.officialRefreshSeconds / 60))
        _lookbackDays = State(initialValue: config.lookbackDays)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.cardSpacing) {
            statusCard
            claudeCard
            codexCard
            commonCard

            if let status {
                Text(status)
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions
        }
        // Every control writes through as soon as it changes — there is no save button
        // to forget. The config file is tiny and written atomically, so doing it per
        // change is cheaper than the risk of losing a setting.
        .onChange(of: edited) { _, config in persist(config) }
    }

    // MARK: - Sections

    private var statusCard: some View {
        SettingsCard {
            sectionTitle("연동 상태")

            if store.snapshot.providers.isEmpty {
                Text("아직 읽는 중입니다")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.snapshot.providers) { provider in
                    VStack(alignment: .leading, spacing: 6) {
                        statusRow(for: provider)
                        // Only when the tool is missing — no point nagging about a
                        // provider that is already reporting.
                        if provider.failure != nil,
                           let guide = ToolInstallGuide.guide(forProvider: provider.id) {
                            InstallHelpCard(guide: guide)
                        }
                    }
                }
            }
        }
    }

    private var claudeCard: some View {
        SettingsCard {
            sectionTitle("Claude Code")

            toggleRow(
                title: "카드 표시",
                caption: "끄면 읽지도 않습니다",
                isOn: $showClaude
            )

            Divider().opacity(0.22)

            toggleRow(
                title: "공식 수치 사용",
                caption: "claude CLI 로 실제 잔량을 가져옵니다",
                isOn: $useCLI
            )
            .opacity(showClaude ? 1 : 0.4)
            .disabled(!showClaude)

            Divider().opacity(0.22)

            stepperRow(
                title: "공식 갱신",
                value: "\(officialMinutes)분",
                caption: "호출 1회마다 요청 1건이 소모됩니다"
            ) {
                Stepper("", value: $officialMinutes, in: 1...60, step: 1)
            }
            .opacity(showClaude && useCLI ? 1 : 0.4)
            .disabled(!showClaude || !useCLI)

            Divider().opacity(0.22)

            stepperRow(
                title: "로그 조회",
                value: "\(lookbackDays)일",
                caption: "토큰·비용 집계 범위"
            ) {
                Stepper("", value: $lookbackDays, in: 1...90, step: 1)
            }
            .opacity(showClaude ? 1 : 0.4)
            .disabled(!showClaude)
        }
    }

    private var codexCard: some View {
        SettingsCard {
            sectionTitle("Codex CLI")

            toggleRow(
                title: "카드 표시",
                caption: "끄면 읽지도 않습니다",
                isOn: $showCodex
            )

            Text("Codex 는 서버가 보고한 사용률을 세션 로그에 직접 기록하므로, 추가 호출이나 조정할 항목이 없습니다.")
                .font(.system(size: 8.5, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var commonCard: some View {
        SettingsCard {
            sectionTitle("공통")

            toggleRow(
                title: "메뉴바 퍼센트 표시",
                caption: "끄면 토끼 아이콘만 남고 색으로만 알립니다",
                isOn: $showMenuBarPercent
            )

            Divider().opacity(0.22)

            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("배경 불투명도")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        Text("\(Int((panelOpacity * 100).rounded()))%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.carrot)
                            .contentTransition(.numericText())
                    }
                    Text("왼쪽 끝은 유리만, 오른쪽으로 갈수록 진해집니다")
                        .font(.system(size: 8.5, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $panelOpacity, in: 0 ... 1)
                    .controlSize(.mini)
            }

            Divider().opacity(0.22)

            stepperRow(
                title: "로컬 갱신",
                value: "\(refreshSeconds)초",
                caption: "로그 재집계 주기 (요청 소모 없음)"
            ) {
                Stepper("", value: $refreshSeconds, in: 10...600, step: 10)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 7) {
            Text("변경하면 자동 저장됩니다")
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 4)
            Button("닫기", action: onDone)
                .buttonStyle(.glassProminent)
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
    }

    // MARK: - Rows

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }

    private func statusRow(for provider: ProviderUsage) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: provider.failure == nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(provider.failure == nil ? Theme.leaf : Theme.ember)

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                Text(statusText(for: provider))
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Extracted so the view builder stays cheap to type-check.
    private func statusText(for provider: ProviderUsage) -> String {
        if let failure = provider.failure { return failure }
        let hasOfficial = provider.windows.contains { !$0.isEstimated }
        return hasOfficial ? "공식 수치 연동됨" : "로컬 로그 기반 추정"
    }

    private func toggleRow(title: String, caption: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                Text(caption)
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    @ViewBuilder
    private func stepperRow(
        title: String,
        value: String,
        caption: String,
        @ViewBuilder control: () -> some View
    ) -> some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    Text(value)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.carrot)
                        .contentTransition(.numericText())
                }
                Text(caption)
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            control()
                .labelsHidden()
                .controlSize(.mini)
        }
    }

    // MARK: - Persistence

    private var edited: WidgetConfig {
        WidgetConfig(
            refreshSeconds: refreshSeconds,
            officialRefreshSeconds: officialMinutes * 60,
            useClaudeCLI: useCLI,
            showClaude: showClaude,
            showCodex: showCodex,
            showMenuBarPercent: showMenuBarPercent,
            panelOpacity: panelOpacity,
            lookbackDays: lookbackDays,
            claudeFiveHourTokenLimit: store.config.claudeFiveHourTokenLimit,
            claudeWeeklyTokenLimit: store.config.claudeWeeklyTokenLimit
        )
    }

    /// Applies to the running widget, then persists. A write failure is surfaced
    /// rather than swallowed, because the user would otherwise assume it stuck.
    private func persist(_ config: WidgetConfig) {
        store.apply(config)
        status = SettingsWriter.save(config) ?? "저장됨"
    }
}

/// Glass container used for each settings group.
private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
}
