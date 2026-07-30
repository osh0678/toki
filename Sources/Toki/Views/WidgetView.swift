import SwiftUI

/// Root layout of the panel: title bar, then either the provider cards or settings.
///
/// Everything is built out of Liquid Glass layers — a glass shell, glass cards inside
/// it, glass bar tracks, and glass controls. There is deliberately **no** AppKit
/// backdrop behind the shell: `glassEffect` samples whatever is behind a transparent
/// window itself, and layering a `NSVisualEffectView` under it just hides the
/// refraction that makes the material read as glass.
struct WidgetView: View {
    let store: UsageStore
    /// Hides the panel; the app keeps running in the menu bar.
    let onClose: () -> Void
    let onQuit: () -> Void

    @State private var showingSettings = false
    @Namespace private var glassNamespace

    /// Providers that actually have data. A provider whose source is missing is not
    /// rendered as a broken card — its reason belongs in settings.
    private var connected: [ProviderUsage] {
        store.snapshot.providers.filter { $0.failure == nil }
    }

    private var hasLoaded: Bool { !store.snapshot.providers.isEmpty }

    var body: some View {
        GlassEffectContainer(spacing: Theme.cardSpacing) {
            VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                TitleBar(
                    isRefreshing: store.isRefreshing,
                    showingSettings: showingSettings,
                    // Explicit user action, so bypass the official-usage throttle.
                    onRefresh: { store.refresh(force: true) },
                    onToggleSettings: { toggleSettings() },
                    onClose: onClose
                )

                if showingSettings {
                    SettingsView(store: store) {
                        withAnimation(.smooth(duration: 0.3)) { showingSettings = false }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                } else {
                    cards
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }

                footer
            }
            .padding(Theme.outerPadding)
        }
        .frame(width: Theme.panelWidth)
        // The AppKit material supplies density; the cards above it supply the glass.
        // Stacking a shell-level `glassEffect` on top of this washed both out.
        .background(
            VisualEffectBackdrop(cornerRadius: Theme.panelCornerRadius)
                .opacity(store.config.panelOpacity)
        )
        .clipShape(.rect(cornerRadius: Theme.panelCornerRadius))
        .overlay {
            // Thin bright rim: what reads as the edge of the glass.
            RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.32), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        }
        .onChange(of: connected.isEmpty) { _, nothingConnected in
            // Nothing to show means the useful screen is settings, where the reason is.
            if nothingConnected, hasLoaded { showingSettings = true }
        }
        .contextMenu {
            Button("새로고침") { store.refresh(force: true) }
            Button(showingSettings ? "사용량 보기" : "설정") { toggleSettings() }
            Button("패널 닫기", action: onClose)
                .keyboardShortcut("w")
            Divider()
            Button("Toki 종료", action: onQuit)
        }
        // The panel is not key when it opens — this accessory app does not reliably
        // activate — so SwiftUI drew the whole hierarchy in its inactive appearance and
        // switched to the active one on the first click. That switch is the colour that
        // "arrived". Pinning the control state removes the delta: the panel always
        // renders active, whether or not it actually holds key.
        .environment(\.controlActiveState, .key)
    }

    private func toggleSettings() {
        withAnimation(.smooth(duration: 0.3)) { showingSettings.toggle() }
    }

    @ViewBuilder
    private var cards: some View {
        if !hasLoaded {
            LoadingCard()
        } else if connected.isEmpty {
            NotConnectedCard { withAnimation(.smooth(duration: 0.3)) { showingSettings = true } }
        } else {
            ForEach(connected) { provider in
                ProviderCard(provider: provider, now: store.clock)
                    .glassEffectID(provider.id, in: glassNamespace)
            }
        }
    }

    private var footer: some View {
        Text(footerText)
            .font(.system(size: 8.5, design: .rounded))
            .foregroundStyle(.tertiary)
    }

    private var footerText: String {
        if showingSettings {
            return "변경은 즉시 적용 · 저장하면 다음 실행에도 유지"
        }
        let stamp = Display.clockTime(store.snapshot.capturedAt)
        return "\(stamp) 기준 · 로컬 \(store.refreshSeconds)초 · 공식 \(store.officialRefreshSeconds / 60)분"
    }
}

private struct TitleBar: View {
    let isRefreshing: Bool
    let showingSettings: Bool
    let onRefresh: () -> Void
    let onToggleSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("🐰").font(.system(size: 13))
            Text("Toki")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Spacer(minLength: 6)

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: isRefreshing
                    )
            }
            .buttonStyle(.glass)
            .keyboardShortcut("r")
            .help("새로고침")

            Button(action: onToggleSettings) {
                Image(systemName: showingSettings ? "chart.bar.fill" : "gearshape.fill")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.glass)
            .keyboardShortcut(",")
            .help(showingSettings ? "사용량 보기" : "설정")
        }
    }
}

private struct LoadingCard: View {
    var body: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.small)
            Text("당근 세는 중…")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .padding(Theme.cardPadding)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
}

/// Shown when neither provider has a usable source.
private struct NotConnectedCard: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                Text("연동된 도구가 없습니다")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            Text("설정에서 연동 상태와 원인을 확인하세요")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.secondary)
            Button("설정 열기", action: onOpenSettings)
                .buttonStyle(.glassProminent)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        // Untinted for the same reason as `ProviderCard`: a tinted surface changes colour
        // on the first click. The amber warning icon carries the signal.
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
}
