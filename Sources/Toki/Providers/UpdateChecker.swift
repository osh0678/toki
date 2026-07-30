import Foundation

/// A newer release than the one running.
struct AvailableUpdate: Sendable, Equatable {
    let version: String
    let downloadURL: URL
    let releaseNotesURL: URL
}

/// Asks GitHub whether a newer release exists.
///
/// This is the **only** networking in Toki, and it is deliberately as small as it can
/// be: one unauthenticated GET whose response is read for a single string
/// (`tag_name`). Nothing is uploaded — no telemetry, no version in the request body,
/// no identifier. GitHub learns what any web request reveals: an IP made a request.
///
/// The download itself is **not** performed here. Handing the dmg URL to the browser
/// keeps two properties: Toki never writes an app bundle (so it can never replace
/// itself, which would be an arbitrary-code-execution channel on an ad-hoc-signed
/// app), and the user still sees the Finder install step. Silent self-replacement
/// would need Developer ID signing plus notarisation to be defensible.
enum UpdateChecker {
    private static let latestReleaseAPI = URL(
        string: "https://api.github.com/repos/osh0678/toki/releases/latest"
    )!
    /// Stable asset name, so this link never needs editing on a new version.
    static let downloadURL = URL(
        string: "https://github.com/osh0678/toki/releases/latest/download/Toki.dmg"
    )!
    static let releasesURL = URL(
        string: "https://github.com/osh0678/toki/releases/latest"
    )!

    private static let timeout: TimeInterval = 15

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Returns nil when up to date, offline, or unreadable — a failed check is silent
    /// by design, because a widget nagging about its own updater is worse than not
    /// knowing.
    static func check(currentVersion: String) async -> AvailableUpdate? {
        var request = URLRequest(url: latestReleaseAPI)
        request.timeoutInterval = timeout
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = root["tag_name"] as? String
        else { return nil }

        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(latest, than: currentVersion) else { return nil }

        return AvailableUpdate(
            version: latest,
            downloadURL: downloadURL,
            releaseNotesURL: releasesURL
        )
    }

    /// Numeric component comparison, so `1.10.0` beats `1.9.0`.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = components(candidate)
        let right = components(current)
        for index in 0 ..< 3 where left[index] != right[index] {
            return left[index] > right[index]
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        var parts = version
            .split(separator: ".")
            .prefix(3)
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        return parts
    }
}
