import Foundation

/// User settings, edited on the watch, stored in the App Group. Kept small and
/// concrete — every field maps to a lever the person recognizes.
struct StretchSettings: Codable, Sendable, Equatable {
    var remindersOn = true
    var intervalMinutes = 40
    /// When you use a standing desk, "no steps" no longer means "sitting", so
    /// suppression leans off and reminders relax.
    var standingDesk = false
    var quietEnabled = true
    var quietStartHour = 22   // 10pm
    var quietEndHour = 7      // 7am
    /// Body areas the user wants reminders for. Optional so a settings blob saved
    /// before this feature still decodes (missing key → nil → treated as all).
    var enabledRegions: Set<Stretch.Region>? = nil

    static let intervalChoices = [20, 30, 40, 50, 60]

    var interval: TimeInterval { TimeInterval(intervalMinutes * 60) }

    /// The regions to actually rotate through — never empty, so the user always
    /// gets a stretch even if they somehow cleared the set.
    var activeRegions: Set<Stretch.Region> {
        let e = enabledRegions ?? Set(Stretch.Region.allCases)
        return e.isEmpty ? Set(Stretch.Region.allCases) : e
    }

    /// Is `date` inside the quiet window? Handles windows that cross midnight.
    func isQuiet(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard quietEnabled else { return false }
        let h = calendar.component(.hour, from: date)
        return quietStartHour <= quietEndHour
            ? (h >= quietStartHour && h < quietEndHour)
            : (h >= quietStartHour || h < quietEndHour)
    }

    /// The next fire moved out of the quiet window (to quiet-end) if it landed inside.
    func adjustedFire(_ fire: Date, calendar: Calendar = .current) -> Date {
        guard isQuiet(fire, calendar: calendar) else { return fire }
        var comps = calendar.dateComponents([.year, .month, .day], from: fire)
        comps.hour = quietEndHour; comps.minute = 0
        var end = calendar.date(from: comps) ?? fire
        if end <= fire { end = calendar.date(byAdding: .day, value: 1, to: end) ?? fire }
        return end
    }
}

enum SettingsStore {
    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.identifier) }
    private static let key = "settings.v1"

    static func load() -> StretchSettings {
        guard let data = defaults?.data(forKey: key),
              let s = try? JSONDecoder.spike.decode(StretchSettings.self, from: data)
        else { return StretchSettings() }
        return s
    }

    static func save(_ s: StretchSettings) {
        if let data = try? JSONEncoder.spike.encode(s) { defaults?.set(data, forKey: key) }
    }
}
