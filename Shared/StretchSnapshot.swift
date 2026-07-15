import Foundation

/// The small derived state shown by the watch complication, phone mirror, and Mac menu bar.
/// It is target-neutral so desktop code can reuse the product's reflection language without
/// importing the Watch App Group store.
struct StretchSnapshot: Codable, Sendable, Equatable {
    var todayCount = 0
    var streakDays = 0
    var weeklyActiveDays = 0
    /// Trailing 7 days of completion counts, oldest first ([6] = today).
    var weeklyCounts: [Int] = []
    /// Longest-ever run of consecutive active days.
    var bestStreakDays = 0
    var lastCompleted: Date?
    var updatedAt = Date()

    /// Whether there's ever been a completed stretch. Drives empty-state copy.
    var hasHistory: Bool {
        todayCount > 0 || weeklyActiveDays > 0 || bestStreakDays > 0 || lastCompleted != nil
    }
}
