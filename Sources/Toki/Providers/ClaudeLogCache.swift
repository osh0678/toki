import Foundation

/// Remembers what each Claude session log parsed to, so a refresh only re-reads the
/// files that actually changed.
///
/// Why this exists: the logs are append-only and the default 14-day lookback covers a
/// couple of thousand files, while the records Toki wants out of them number in the
/// low thousands of lines. Without a cache every refresh re-read and re-parsed the whole
/// history — measured at 236 MB per pass on a two-week-old log tree, repeated every 60
/// seconds. Keyed on `(size, modification date)`, an untouched file now costs the `stat`
/// the directory walk already performs and nothing more.
///
/// Any difference in either key is a miss, so a file that grew, shrank, or was rewritten
/// in place is re-read in full rather than trusted. Append-only is the normal case, not a
/// guarantee, and a rewritten log must not keep serving records that are no longer in it.
final class ClaudeLogCache: @unchecked Sendable {
    /// Shared, because parsing runs off the main actor on a detached task. The lock —
    /// not the actor system — is what keeps this consistent.
    static let shared = ClaudeLogCache()

    private struct CachedFile {
        let byteSize: Int
        let modified: Date
        /// Every entry in the file, deliberately *unfiltered* by the lookback cutoff:
        /// the cutoff moves forward on every refresh, so a pre-filtered list would be
        /// wrong the moment it was reused.
        let entries: [ClaudeUsageEntry]
    }

    private let lock = NSLock()
    private var byPath: [String: CachedFile] = [:]

    /// Parsed entries for `file`, or `nil` when it is new or has changed since it was
    /// last read.
    func entries(for file: JSONLReader.SessionFile) -> [ClaudeUsageEntry]? {
        lock.lock()
        defer { lock.unlock() }
        guard let cached = byPath[file.path],
              cached.byteSize == file.byteSize,
              cached.modified == file.modified
        else { return nil }
        return cached.entries
    }

    func store(_ entries: [ClaudeUsageEntry], for file: JSONLReader.SessionFile) {
        lock.lock()
        defer { lock.unlock() }
        byPath[file.path] = CachedFile(
            byteSize: file.byteSize,
            modified: file.modified,
            entries: entries
        )
    }

    /// Drops every path outside `liveFiles`.
    ///
    /// This is what bounds the cache. `liveFiles` is the set the directory walk just
    /// returned, which is itself bounded by the lookback window — so a log that ages out
    /// of that window, or is deleted, is evicted on the very next refresh rather than
    /// held until the process exits. There is no separate expiry to tune: the cache can
    /// never describe more files than the window currently contains.
    func prune(to liveFiles: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        byPath = byPath.filter { liveFiles.contains($0.key) }
    }
}
