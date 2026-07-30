import Foundation

/// Read-only helpers for append-only JSONL logs. Lines are handled as raw bytes
/// so multi-megabyte session logs never become multi-megabyte Swift strings.
enum JSONLReader {
    /// How much of a file's tail is read when only the newest records matter.
    static let defaultTailBytes = 512 * 1024

    private static let newline: UInt8 = 0x0A

    /// Calls `body` for every line of `url` whose bytes contain `needle`.
    /// Memory-maps the file when safe, so resident memory stays flat.
    static func forEachLine(
        of url: URL,
        containing needle: [UInt8],
        _ body: (Data) -> Void
    ) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        forEachLine(in: data, containing: needle, body)
    }

    /// Every line in the file's tail containing `needle`, in file order.
    /// The caller should walk the result in reverse: the newest record wins, and
    /// a half-written final line simply fails to parse.
    static func tailLines(
        of url: URL,
        containing needle: [UInt8],
        tailBytes: Int = defaultTailBytes
    ) throws -> [Data] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let offset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try handle.seek(toOffset: offset)
        guard let data = try handle.readToEnd() else { return [] }

        var matches: [Data] = []
        forEachLine(in: data, containing: needle) { matches.append(Data($0)) }
        return matches
    }

    /// `*.jsonl` files under `root` modified at or after `since`, newest first.
    ///
    /// Symlinks are skipped and every candidate is re-checked to still resolve
    /// inside `root`, so a symlinked directory planted in the log tree cannot make
    /// Toki open a file elsewhere on the disk.
    static func sessionFiles(under root: URL, modifiedSince since: Date) -> [URL] {
        let keys: [URLResourceKey] = [
            .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey
        ]
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let rootPath = canonicalPath(of: root)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        var found: [(url: URL, modified: Date)] = []
        for case let url as URL in walker {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true,
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= since,
                  canonicalPath(of: url).hasPrefix(rootPrefix)
            else { continue }
            found.append((url, modified))
        }

        return found.sorted { $0.modified > $1.modified }.map(\.url)
    }

    private static func canonicalPath(of url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
    }

    private static func forEachLine(
        in data: Data,
        containing needle: [UInt8],
        _ body: (Data) -> Void
    ) {
        var cursor = data.startIndex
        while cursor < data.endIndex {
            let lineEnd = data[cursor...].firstIndex(of: newline) ?? data.endIndex
            if lineEnd > cursor {
                let line = data[cursor..<lineEnd]
                if line.firstRange(of: needle) != nil { body(line) }
            }
            guard lineEnd < data.endIndex else { return }
            cursor = data.index(after: lineEnd)
        }
    }
}

/// ISO 8601 timestamps in these logs sometimes carry fractional seconds and
/// sometimes do not, so both shapes are attempted.
struct TimestampParser {
    private let fractional = ISO8601DateFormatter()
    private let plain = ISO8601DateFormatter()

    init() {
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        plain.formatOptions = [.withInternetDateTime]
    }

    func date(from text: String) -> Date? {
        fractional.date(from: text) ?? plain.date(from: text)
    }
}

extension [String: Any] {
    /// Numeric field access that tolerates both integer and floating JSON values.
    func intValue(_ key: String) -> Int? {
        (self[key] as? NSNumber)?.intValue
    }

    func doubleValue(_ key: String) -> Double? {
        (self[key] as? NSNumber)?.doubleValue
    }

    func object(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }
}
