import SwiftUI

/// One provider rendered as a Liquid Glass card.
///
/// Only aggregate numbers reach this view. Account identifiers, e-mail addresses,
/// file paths, and log contents are never passed into the UI layer.
struct ProviderCard: View {
    let provider: ProviderUsage
    let now: Date

    private var accent: Color { Theme.accent(forProvider: provider.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if let failure = provider.failure {
                Text(failure)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(provider.windows) { window in
                    UsageBar(window: window, accent: accent, now: now)
                }
                footer
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Untinted on purpose. A tinted glass surface only picks up its tint once the
        // panel is interacted with, so the cards visibly turned orange and blue on the
        // first click. Provider identity is carried by the header icon, the plan badge,
        // and the meter instead — none of which shift with the panel's state.
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .overlay {
            // Rim light, so each card reads as a separate pane of glass rather than a
            // flat tinted rectangle.
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.7
                )
        }
        .help(provider.note ?? "")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: provider.symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accent)
            Text(provider.displayName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.2)
            Spacer(minLength: 4)
            if let plan = provider.planLabel {
                PlanBadge(text: plan, accent: accent)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        let stats = [
            provider.todayTokens.map { "오늘 \(Display.tokens($0)) 토큰" },
            provider.todayCostUSD.map { "API 환산 \(Display.cost($0))" }
        ].compactMap(\.self)

        if !stats.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
                Text(stats.joined(separator: "   "))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Subscription tier, outlined rather than filled — a filled pill competes with the
/// meter for attention, and the tier is reference information, not a reading.
private struct PlanBadge: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
            .tracking(0.3)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .foregroundStyle(accent.opacity(0.9))
            .overlay(
                Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 0.7)
            )
    }
}
