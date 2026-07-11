import Foundation

/// Shared constants for the App Group container that the watch app, its
/// complication, and (later) the iOS app all read/write.
enum AppGroup {
    static let identifier = "group.com.goosull.stretchwatch"

    /// Container URL for the shared App Group, with a graceful fallback to the
    /// app's own Application Support directory. The fallback matters for unsigned
    /// simulator builds (no entitlement applied) — on a real signed device the
    /// group container is used and the complication can read the same files.
    static var containerURL: URL {
        if let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        NSLog("App Group '\(identifier)' unavailable — using local Application Support (expected in unsigned sim builds).")
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}
