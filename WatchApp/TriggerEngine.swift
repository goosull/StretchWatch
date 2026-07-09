import Foundation
import UserNotifications
import WatchKit
import WidgetKit

/// The single scheduler (rolling one-shot). Exactly one pending notification
/// (`stretch.next`) at an absolute time + one background refresh armed a lead
/// before it. On each wake we query the pedometer and, if the user moved
/// recently, push the fire back (suppression). If watchOS never wakes us, the
/// pending notification fires anyway — that's the timer floor.
enum TriggerEngine {
    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.identifier) }

    // MARK: - Persisted state
    static var nextFireDate: Date? {
        get { defaults?.object(forKey: StretchConfig.kNextFire) as? Date }
        set { defaults?.set(newValue, forKey: StretchConfig.kNextFire) }
    }
    private static var sessionId: String? {
        get { defaults?.string(forKey: StretchConfig.kSessionId) }
        set { defaults?.set(newValue, forKey: StretchConfig.kSessionId) }
    }
    private static var currentMoveId: String? {
        get { defaults?.string(forKey: StretchConfig.kCurrentMove) }
        set { defaults?.set(newValue, forKey: StretchConfig.kCurrentMove) }
    }
    private static var lastMoveId: String? {
        get { defaults?.string(forKey: StretchConfig.kLastMove) }
        set { defaults?.set(newValue, forKey: StretchConfig.kLastMove) }
    }
    private static var seed: Int {
        get { defaults?.integer(forKey: StretchConfig.kSeed) ?? 0 }
        set { defaults?.set(newValue, forKey: StretchConfig.kSeed) }
    }

    /// The move tied to the currently-scheduled session (what a notification tap opens).
    static var currentStretch: Stretch {
        StretchLibrary.all.first { $0.id == currentMoveId } ?? StretchLibrary.all[0]
    }
    static var currentSessionId: String { sessionId ?? "adhoc" }

    static var minutesToNextFire: Int? {
        nextFireDate.map { max(0, Int($0.timeIntervalSinceNow / 60)) }
    }

    // MARK: - Lifecycle

    static func onLaunch() async {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        WatchSync.shared.activate()
        registerCategory()
        // Notification + motion permission are requested contextually from the
        // onboarding card (not cold at launch) per the design review.
        if await authStatus() == .authorized {
            await ensureScheduled()
        }
        await refreshSnapshot()
    }

    private static func ensureScheduled() async {
        if nextFireDate == nil || (nextFireDate ?? .distantPast) < Date() {
            await armNext()
        } else {
            scheduleBackgroundRefresh(at: (nextFireDate ?? Date()).addingTimeInterval(-StretchConfig.wakeLead))
        }
    }

    static func authStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Called from the onboarding card. Requests FULL auth + primes motion, then
    /// arms the first schedule.
    @discardableResult
    static func enableReminders() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        _ = await PedometerReader.shared.stepsInTrailingWindow() // primes motion prompt
        if granted { await ensureScheduled() }
        return granted
    }

    static func onForeground() async {
        if await authStatus() == .authorized { await ensureScheduled() }
        await refreshSnapshot()
    }

    static func onBackgroundWake() async {
        let now = Date()
        let steps = await PedometerReader.shared.stepsInTrailingWindow()
        let fire = nextFireDate
        let lead = fire.map { $0.timeIntervalSince(now) }
        let moved = (steps ?? 0) >= StretchConfig.movedStepThreshold
        let opportunity = (lead ?? -1) > 0 && moved
        await SpikeLogStore.shared.append(SpikeEvent(
            date: now, kind: .wake, stepsLast40min: steps,
            nextFireDate: fire, leadSeconds: lead,
            note: opportunity ? "suppressed (moved)" : nil))

        if opportunity {
            await armNext(from: now)          // moved recently → push the fire back
        } else if fire == nil || (fire ?? .distantPast) < now {
            await armNext(from: now)          // lost/expired → re-arm
        } else {
            scheduleBackgroundRefresh(at: (fire ?? now).addingTimeInterval(-StretchConfig.wakeLead))
        }
        await refreshSnapshot()
    }

    // MARK: - Outcomes (called from the notification actions / the session view)

    static func complete(sessionId sid: String, moveId: String) async {
        await StretchStore.shared.record(.init(sessionId: sid, date: Date(), outcome: .completed, moveId: moveId))
        // Opt-in: mirror the stretch into Apple Health as a mindful session.
        if SettingsStore.load().logToHealth {
            let seconds = StretchLibrary.all.first { $0.id == moveId }?.seconds ?? 30
            await HealthLogger.logMindfulSession(seconds: seconds)
        }
        await refreshSnapshot()
        await armNext()                        // refractory: next reminder from now
    }

    static func skip(sessionId sid: String, moveId: String) async {
        await StretchStore.shared.record(.init(sessionId: sid, date: Date(), outcome: .skipped, moveId: moveId))
        await armNext()
    }

    // MARK: - Scheduling (rolling one-shot)

    /// Re-arm after the user changes settings (interval, quiet hours, on/off).
    static func settingsChanged() async {
        await armNext()
        await refreshSnapshot()
    }

    static func armNext(from: Date = Date()) async {
        let settings = SettingsStore.load()
        guard settings.remindersOn else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [StretchConfig.notifIdentifier])
            nextFireDate = nil
            return
        }
        let move = StretchLibrary.next(afterMoveId: lastMoveId, seed: seed,
                                       enabledRegions: settings.activeRegions)
        let fire = settings.adjustedFire(from.addingTimeInterval(settings.interval))
        let sid = String(Int(fire.timeIntervalSince1970))
        currentMoveId = move.id
        sessionId = sid
        nextFireDate = fire
        lastMoveId = move.id
        seed &+= 1
        await scheduleNotification(move: move, sessionId: sid, at: fire)
        scheduleBackgroundRefresh(at: fire.addingTimeInterval(-StretchConfig.wakeLead))
        await StretchStore.shared.record(.init(sessionId: sid, date: from, outcome: .scheduled, moveId: move.id))
        await SpikeLogStore.shared.append(SpikeEvent(date: from, kind: .armedNotif, nextFireDate: fire))
    }

    static func refreshSnapshot() async {
        let snap = await StretchStore.shared.snapshot()
        if let data = try? JSONEncoder.spike.encode(snap) {
            defaults?.set(data, forKey: StretchConfig.kSnapshot)
        }
        WidgetCenter.shared.reloadAllTimelines()
        WatchSync.shared.send(snap)
    }

    static func loadSnapshot() -> StretchSnapshot {
        guard let data = defaults?.data(forKey: StretchConfig.kSnapshot),
              let snap = try? JSONDecoder.spike.decode(StretchSnapshot.self, from: data)
        else { return StretchSnapshot() }
        return snap
    }

    // MARK: - Notifications

    private static func scheduleNotification(move: Stretch, sessionId sid: String, at date: Date) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [StretchConfig.notifIdentifier])
        let content = UNMutableNotificationContent()
        // Vary the title so the buzz doesn't go invisible by week 3. The body
        // always carries the actual move, so it's doable straight from the banner.
        content.title = ["A little reset?", "Ease up a moment", "Loosen up", "Quick unwind",
                         "Time to ease up"].randomElement() ?? "Ease up a moment"
        content.body = move.title
        content.categoryIdentifier = StretchConfig.notifCategory
        content.interruptionLevel = .active
        content.userInfo = ["sessionId": sid, "moveId": move.id]
        let seconds = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: StretchConfig.notifIdentifier,
                                                    content: content, trigger: trigger))
    }

    private static func registerCategory() {
        let done = UNNotificationAction(identifier: StretchConfig.actionComplete,
                                        title: "Did it", options: [])
        let skip = UNNotificationAction(identifier: StretchConfig.actionSkip,
                                        title: "Not now", options: [])
        let category = UNNotificationCategory(identifier: StretchConfig.notifCategory,
                                              actions: [done, skip], intentIdentifiers: [],
                                              options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private static func scheduleBackgroundRefresh(at date: Date) {
        let target = max(date, Date().addingTimeInterval(StretchConfig.minRefreshLead))
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: target, userInfo: nil) { error in
            if let error { NSLog("scheduleBackgroundRefresh error: \(error)") }
        }
    }
}
