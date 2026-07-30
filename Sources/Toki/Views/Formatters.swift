import Foundation

/// Compact, glanceable string formatting. Everything here is presentation-only —
/// no identifiers, paths, or account details are ever formatted for display.
enum Display {
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        switch count {
        case ..<1_000: return "\(count)"
        case ..<1_000_000: return String(format: "%.1fK", value / 1_000)
        case ..<1_000_000_000: return String(format: "%.1fM", value / 1_000_000)
        default: return String(format: "%.2fB", value / 1_000_000_000)
        }
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func cost(_ usd: Double) -> String {
        usd >= 100 ? String(format: "$%.0f", usd) : String(format: "$%.2f", usd)
    }

    /// Coarse countdown such as "4일 2시간" or "2시간 14분".
    /// Returns nil once the target is effectively reached, so callers can omit the
    /// label entirely rather than render a stale "0분".
    static func remainingDuration(until target: Date, from now: Date) -> String? {
        let seconds = Int(target.timeIntervalSince(now))
        guard seconds > 0 else { return nil }

        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24

        if days > 0 { return "\(days)일 \(hours % 24)시간" }
        if hours > 0 { return "\(hours)시간 \(minutes % 60)분" }
        if minutes > 0 { return "\(minutes)분" }
        return "1분 미만"
    }

    static func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
