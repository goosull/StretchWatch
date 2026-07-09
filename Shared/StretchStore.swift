import Foundation

/// A recorded outcome for one stretch prompt. `sessionId` (derived from the
/// scheduled fire time) makes completion idempotent across the three channels
/// that can record it: in-app finish, notification action, and resume-reconcile.
struct StretchEvent: Codable, Sendable, Identifiable {
    enum Outcome: String, Codable, Sendable { case scheduled, opened, completed, skipped, expired }
    var id = UUID()
    var sessionId: String
    var date: Date
    var outcome: Outcome
    var moveId: String
}

/// Product source of truth: an append-log in the App Group container. The
/// complication reads the derived snapshot; the phone gets it over
/// WatchConnectivity. Pure derivations (count/streak) so they're unit-testable.
actor StretchStore {
    static let shared = StretchStore()

    private let fileURL = AppGroup.containerURL.appendingPathComponent("stretch-events.json")
    private let maxEvents = 5000

    func record(_ event: StretchEvent) {
        var events = load()
        // Idempotency: a session can only be completed once.
        if event.outcome == .completed,
           events.contains(where: { $0.sessionId == event.sessionId && $0.outcome == .completed }) {
            return
        }
        events.append(event)
        if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
        write(events)
    }

    func all() -> [StretchEvent] { load() }

    func snapshot(calendar: Calendar = .current, now: Date = Date()) -> StretchSnapshot {
        StretchStore.snapshot(from: load(), calendar: calendar, now: now)
    }

    // MARK: - Pure derivations (static so tests don't need the actor / disk)

    static func snapshot(from events: [StretchEvent],
                         calendar: Calendar = .current,
                         now: Date = Date()) -> StretchSnapshot {
        let completed = events.filter { $0.outcome == .completed }
        let today = calendar.startOfDay(for: now)
        let todayCount = completed.filter { calendar.isDate($0.date, inSameDayAs: now) }.count

        // Distinct local days that had ≥1 completion.
        let completedDays = Set(completed.map { calendar.startOfDay(for: $0.date) })

        // Weekly consistency: distinct active days in the trailing 7 days.
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let weeklyActiveDays = completedDays.filter { $0 >= weekAgo && $0 <= today }.count

        // Per-day completion counts for the trailing 7 days, oldest first:
        // index 0 = 6 days ago … index 6 = today. Feeds the iOS heatmap.
        var weeklyCounts = [Int](repeating: 0, count: 7)
        for event in completed {
            let day = calendar.startOfDay(for: event.date)
            if let diff = calendar.dateComponents([.day], from: day, to: today).day,
               diff >= 0, diff <= 6 {
                weeklyCounts[6 - diff] += 1
            }
        }

        // Lenient streak: walk back from today; today counting as 0 does NOT break
        // it (the day isn't over). A prior day with no completion ends the streak.
        var streak = 0
        var cursor = today
        while true {
            if completedDays.contains(cursor) {
                streak += 1
            } else if cursor == today {
                // today not done yet — neutral, keep looking back
            } else {
                break
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
            if streak > 400 { break }  // backstop
        }

        // Best ever: the longest run of consecutive completed days across all
        // history. Reflective, never punitive — a personal record to return to.
        var bestStreak = 0
        if !completedDays.isEmpty {
            let sorted = completedDays.sorted()
            var run = 1
            bestStreak = 1
            for i in 1..<sorted.count {
                let prevPlusOne = calendar.date(byAdding: .day, value: 1, to: sorted[i - 1])
                run = (prevPlusOne == sorted[i]) ? run + 1 : 1
                bestStreak = max(bestStreak, run)
            }
        }
        // The in-progress streak is always a real run, so best is never below it.
        bestStreak = max(bestStreak, streak)

        return StretchSnapshot(todayCount: todayCount,
                               streakDays: streak,
                               weeklyActiveDays: weeklyActiveDays,
                               weeklyCounts: weeklyCounts,
                               bestStreakDays: bestStreak,
                               lastCompleted: completed.map(\.date).max(),
                               updatedAt: now)
    }

    /// Stepped intensity bucket for a day's completion count, 0…3. A discrete
    /// scale reads cleaner than a continuous gradient (and stays accessible with
    /// a single-hue opacity ramp). The UI maps the level to an ember opacity.
    static func heatLevel(_ count: Int) -> Int {
        switch count {
        case ..<1:  return 0
        case 1:     return 1
        case 2:     return 2
        default:    return 3
        }
    }

    private func load() -> [StretchEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.spike.decode([StretchEvent].self, from: data)) ?? []
    }
    private func write(_ events: [StretchEvent]) {
        guard let data = try? JSONEncoder.spike.encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// The small derived state the complication and phone dashboard show. Cliff-free
/// primary numbers (today + weekly) lead; streak is secondary flavor.
struct StretchSnapshot: Codable, Sendable {
    var todayCount = 0
    var streakDays = 0
    var weeklyActiveDays = 0
    /// Trailing 7 days of completion counts, oldest first ([6] = today). Empty on
    /// decode of a pre-heatmap snapshot — the UI treats that as all-zero.
    var weeklyCounts: [Int] = []
    /// Longest-ever run of consecutive active days. Defaults to 0 for a snapshot
    /// saved before this field existed.
    var bestStreakDays = 0
    var lastCompleted: Date?
    var updatedAt = Date()

    /// Whether there's ever been a completed stretch. Drives the dashboard's
    /// first-run empty state so a brand-new user sees an invitation, not a wall
    /// of zeros.
    var hasHistory: Bool {
        todayCount > 0 || weeklyActiveDays > 0 || bestStreakDays > 0 || lastCompleted != nil
    }
}
