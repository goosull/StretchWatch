import Foundation

/// Read-only accessors for the small state the watch app writes and the
/// complication (a separate process) reads, both via the App Group defaults.
enum SharedState {
    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.identifier) }

    static func snapshot() -> StretchSnapshot {
        guard let data = defaults?.data(forKey: StretchConfig.kSnapshot),
              let snap = try? JSONDecoder.spike.decode(StretchSnapshot.self, from: data)
        else { return StretchSnapshot() }
        return snap
    }

    static var nextFireDate: Date? {
        defaults?.object(forKey: StretchConfig.kNextFire) as? Date
    }

    static var minutesToNextFire: Int? {
        nextFireDate.map { max(0, Int($0.timeIntervalSinceNow / 60)) }
    }
}
