import Foundation

/// One rolling usage window grouped out of a stream of usage entries.
struct SessionWindow: Sendable {
    let start: Date
    let end: Date
    let totalTokens: Int
    let costUSD: Double

    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

/// Groups Claude usage entries into fixed-length windows, mirroring how Claude
/// Code's session limit behaves: a window opens on the first request (rounded
/// down to the hour) and lasts a fixed duration; a gap longer than that duration
/// starts a fresh window.
enum SessionWindows {
    /// `entries` must be sorted ascending by timestamp.
    static func windows(
        from entries: [ClaudeUsageEntry],
        duration: TimeInterval,
        calendar: Calendar
    ) -> [SessionWindow] {
        var windows: [SessionWindow] = []
        var start: Date?
        var lastSeen: Date?
        var tokens = 0
        var cost = 0.0

        func closeWindow() {
            guard let start else { return }
            windows.append(
                SessionWindow(
                    start: start,
                    end: start.addingTimeInterval(duration),
                    totalTokens: tokens,
                    costUSD: cost
                )
            )
        }

        for entry in entries {
            let isContinuation = start.map { openedAt in
                entry.timestamp < openedAt.addingTimeInterval(duration)
                    && entry.timestamp.timeIntervalSince(lastSeen ?? openedAt) <= duration
            } ?? false

            if !isContinuation {
                closeWindow()
                start = floorToHour(entry.timestamp, calendar: calendar)
                tokens = 0
                cost = 0
            }

            tokens += entry.totalTokens
            cost += entry.costUSD
            lastSeen = entry.timestamp
        }

        closeWindow()
        return windows
    }

    /// Largest sum of `windowDays` consecutive calendar days. Used to calibrate a
    /// weekly ceiling from observed history when no explicit limit is configured.
    static func rollingMaximum(
        dailyTotals: [Date: Int],
        windowDays: Int,
        calendar: Calendar
    ) -> Int {
        guard windowDays > 0, !dailyTotals.isEmpty else { return 0 }

        var best = 0
        for anchor in dailyTotals.keys {
            guard let limit = calendar.date(byAdding: .day, value: windowDays, to: anchor) else { continue }
            let sum = dailyTotals
                .filter { $0.key >= anchor && $0.key < limit }
                .values
                .reduce(0, +)
            best = max(best, sum)
        }
        return best
    }

    static func dailyTotals(
        from entries: [ClaudeUsageEntry],
        calendar: Calendar
    ) -> [Date: Int] {
        entries.reduce(into: [:]) { totals, entry in
            let day = calendar.startOfDay(for: entry.timestamp)
            totals[day, default: 0] += entry.totalTokens
        }
    }

    private static func floorToHour(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }
}
