import Foundation
import Observation

/// Owns the widget's state: holds the latest snapshot, schedules refreshes, and
/// keeps every log read and subprocess off the main actor so the panel never
/// stutters.
///
/// Two cadences, because the two data sources cost very different things:
/// * local log aggregation is free, so it runs on `refreshSeconds` (default 60s);
/// * official Claude figures come from a `claude` CLI invocation and each call
///   counts as one request against the account, so they run on
///   `officialRefreshSeconds` (default 600s) and are cached in between.
@MainActor
@Observable
final class UsageStore {
    /// How often the relative "resets in" labels are re-evaluated.
    private static let tickInterval = Duration.seconds(10)

    private(set) var snapshot: UsageSnapshot
    private(set) var isRefreshing = false
    /// Advances on a timer so countdowns stay current between full refreshes.
    private(set) var clock: Date
    /// Newer release, when one exists and update checks are enabled.
    private(set) var availableUpdate: AvailableUpdate?

    /// Once a day is plenty for a widget, and it keeps the single network request rare.
    private static let updateCheckInterval: TimeInterval = 86_400
    private var lastUpdateCheck: Date?

    /// Readable so the settings UI can seed its fields from the live configuration.
    private(set) var config: WidgetConfig
    private var official: ClaudeOfficialUsage?
    private var officialFailure: String?
    private var lastOfficialAttempt: Date?
    private var refreshTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    init(config: WidgetConfig = .load(), now: Date = Date()) {
        self.config = config
        self.snapshot = .placeholder(at: now)
        self.clock = now
    }

    var refreshSeconds: Int { config.refreshSeconds }
    var officialRefreshSeconds: Int { config.officialRefreshSeconds }

    /// Performs the first read and starts the periodic tick. Safe to call twice.
    func start() {
        guard tickTask == nil else { return }
        refresh()
        checkForUpdateIfDue()

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                guard let self, !Task.isCancelled else { return }
                self.clock = Date()
                if self.isLocalRefreshDue || self.isOfficialRefreshDue(at: self.clock) {
                    self.refresh()
                }
                self.checkForUpdateIfDue()
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// `force` bypasses the official-usage throttle — used by the manual refresh
    /// button and menu item, where the user has explicitly asked for fresh numbers.
    func refresh(force: Bool = false) {
        guard !isRefreshing else { return }
        isRefreshing = true

        let now = Date()
        let fetchOfficial = force || isOfficialRefreshDue(at: now)
        if fetchOfficial { lastOfficialAttempt = now }

        let config = self.config
        let cached = official

        refreshTask = Task { [weak self] in
            let collected = await Task.detached(priority: .utility) {
                Self.collect(config: config, cachedOfficial: cached, fetchOfficial: fetchOfficial)
            }.value

            guard let self else { return }
            self.isRefreshing = false
            guard !Task.isCancelled else { return }

            if collected.didFetchOfficial {
                self.official = collected.official
                self.officialFailure = collected.officialFailure
            }
            self.snapshot = collected.snapshot
            self.clock = collected.snapshot.capturedAt
        }
    }

    /// Applies settings edited in the UI straight away. Persisting them to disk is the
    /// caller's job, so an unsaved experiment can be tried without touching the file.
    func apply(_ updated: WidgetConfig) {
        config = updated
        // Clearing the throttle means a newly enabled CLI (or shortened interval) takes
        // effect on this refresh rather than up to ten minutes later.
        lastOfficialAttempt = nil
        // Re-check immediately so switching the setting on has a visible effect.
        lastUpdateCheck = nil
        refresh(force: updated.useClaudeCLI)
        checkForUpdateIfDue()
    }

    /// The one place Toki touches the network, and only when the user leaves it on.
    private func checkForUpdateIfDue() {
        guard config.checkForUpdates else {
            availableUpdate = nil
            return
        }
        if let lastUpdateCheck,
           Date().timeIntervalSince(lastUpdateCheck) < Self.updateCheckInterval {
            return
        }
        lastUpdateCheck = Date()

        Task { [weak self] in
            let found = await UpdateChecker.check(currentVersion: UpdateChecker.currentVersion)
            self?.availableUpdate = found
        }
    }

    /// Called when the panel opens, so opening it never shows stale figures.
    func refreshIfStale() {
        guard isLocalRefreshDue || isOfficialRefreshDue(at: Date()) else { return }
        refresh()
    }

    private var isLocalRefreshDue: Bool {
        clock.timeIntervalSince(snapshot.capturedAt) >= Double(config.refreshSeconds)
    }

    private func isOfficialRefreshDue(at now: Date) -> Bool {
        guard config.useClaudeCLI else { return false }
        guard let lastOfficialAttempt else { return true }
        return now.timeIntervalSince(lastOfficialAttempt) >= Double(config.officialRefreshSeconds)
    }

    private struct Collected: Sendable {
        let snapshot: UsageSnapshot
        let official: ClaudeOfficialUsage?
        let officialFailure: String?
        let didFetchOfficial: Bool
    }

    /// Runs off the main actor. Each provider swallows its own I/O failures and
    /// reports them as a per-card message, so one broken source never blanks the panel.
    private nonisolated static func collect(
        config: WidgetConfig,
        cachedOfficial: ClaudeOfficialUsage?,
        fetchOfficial: Bool
    ) -> Collected {
        let now = Date()
        var official = cachedOfficial
        var failure: String?

        if fetchOfficial {
            switch ClaudeOfficialUsageReader.read(now: now) {
            case .usage(let reading): official = reading
            case .failure(let reason): failure = reason
            }
        }

        // A provider switched off in settings is not read at all, so hiding it also
        // stops the work it would have cost.
        var providers: [ProviderUsage] = []
        if config.showClaude {
            providers.append(
                ClaudeUsageProvider.read(
                    config: config,
                    now: now,
                    official: official,
                    officialFailure: failure
                )
            )
        }
        if config.showCodex {
            providers.append(CodexUsageProvider.read(now: now))
        }

        let snapshot = UsageSnapshot(providers: providers, capturedAt: now)

        return Collected(
            snapshot: snapshot,
            official: official,
            officialFailure: failure,
            didFetchOfficial: fetchOfficial
        )
    }
}
