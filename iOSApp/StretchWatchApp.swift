import SwiftUI

@main
struct StretchWatchApp: App {
    @StateObject private var sync = PhoneSync.shared

    init() {
        // Dev-only: seed a sample snapshot to screenshot the dashboard without a
        // paired watch (mirrors the watch app's -previewHome convention).
        if CommandLine.arguments.contains("-previewData") {
            PhoneSync.shared.snapshot = StretchSnapshot(
                todayCount: 3, streakDays: 4, weeklyActiveDays: 5,
                weeklyCounts: [0, 2, 1, 3, 0, 1, 3], bestStreakDays: 12,
                lastCompleted: Date(), updatedAt: Date())
        }
        PhoneSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(sync)
        }
    }
}
