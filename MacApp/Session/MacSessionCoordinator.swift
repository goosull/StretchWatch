import Foundation
import SwiftUI

/// The one owner of the Mac session state machine. Views and adapters send
/// commands here; they never write the snapshot or schedule notifications
/// themselves.
@MainActor
final class MacSessionCoordinator: ObservableObject {
    static let interval: TimeInterval = 40 * 60
    static let followUpInterval: TimeInterval = 15 * 60
    static let snoozeInterval: TimeInterval = 10 * 60
    static let idleExpiry: TimeInterval = 10 * 60
    static let retryGrace: TimeInterval = 5 * 60
    static let retryQuietInterval: TimeInterval = 60 * 60
    static let pollInterval: TimeInterval = 15

    @Published private(set) var state = MacSessionState()
    @Published private(set) var authorization: MacNotificationAuthorization = .notDetermined
    @Published private(set) var dashboardMetrics = MacDashboardMetrics()
    @Published private(set) var lastError: String?

    var onPresent: ((Stretch, StretchSnapshot) -> Void)?
    var onDismiss: (() -> Void)?

    private let store: any MacStateStore
    private let idleProvider: any IdleTimeProviding
    private let clock: any MacClock
    private let notifications: any MacNotificationClient
    private var pollTask: Task<Void, Never>?
    private var started = false
    private var processClockAnchor: (wall: Date, monotonic: TimeInterval)?

    init(store: any MacStateStore,
         idleProvider: any IdleTimeProviding,
         clock: any MacClock = SystemMacClock(),
         notifications: any MacNotificationClient) {
        self.store = store
        self.idleProvider = idleProvider
        self.clock = clock
        self.notifications = notifications
    }

    deinit {
        pollTask?.cancel()
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        notifications.registerCategory()
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.bootstrap()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                } catch {
                    return
                }
                await self.tick()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        started = false
    }

    /// Used by unit tests to run the launch path deterministically without
    /// starting the repeating desktop poll.
    func bootstrapForTesting() async {
        await bootstrap()
    }

    func tickForTesting() async {
        await tick()
    }

    private func bootstrap() async {
        do {
            if let persisted = try await store.load() {
                state = persisted
            }
            authorization = await notifications.authorizationStatus()
            try await store.pruneEvents(olderThan: currentDate.addingTimeInterval(-30 * 24 * 60 * 60))

            if state.phase == .presenting {
                await endInterruptedSession()
            }
            if state.phase == .pausedToday, isPauseExpired {
                await resetPause()
            }

            if state.phase == .permissionDenied,
               isAuthorizationGranted,
               state.remindersEnabled {
                state.phase = .dormant
            }

            if state.remindersEnabled, authorization == .denied, state.phase.isSession {
                var next = state
                let oldSession = state.sessionId
                next.phase = .permissionDenied
                next.remindersEnabled = false
                clearSessionFields(&next)
                let event = makeEvent(kind: .permissionDenied,
                                      next: next,
                                      sessionId: oldSession,
                                      source: .lifecycle)
                guard await commit(next, event: event) else { return }
                await notifications.removeRequestIDs(await managedNotificationIDs())
            }

            if state.phase.isAutomaticSession,
               !isEligibleToRecover {
                await endSession(source: .lifecycle)
            } else if state.phase == .dormant,
                      state.remindersEnabled,
                      isIdleEligible {
                await armSession(mode: .automatic, source: .lifecycle)
            }

            await reconcileNotifications()
            await refreshDashboardMetrics()
        } catch {
            failClosed(error)
        }
    }

    private func tick() async {
        if state.phase == .pausedToday {
            if isPauseExpired { await resetPause() }
            return
        }

        if state.phase == .retryQuiet {
            if let quietUntil = state.quietUntil, currentDate >= quietUntil {
                await armSession(mode: state.mode, source: .timer)
            }
            return
        }

        if state.phase == .dormant {
            if state.remindersEnabled, isIdleEligible {
                await armSession(mode: .automatic, source: .timer)
            }
            return
        }

        if state.mode == .automatic,
           [.active, .snoozed, .due].contains(state.phase),
           !isIdleEligible {
            await endSession(source: .timer)
            return
        }

        let now = currentDate
        let dueBoundary = state.phase == .active && state.dueAt.map { now >= $0 } == true
        let followUpBoundary = state.phase == .snoozed && state.followUpAt.map { now >= $0 } == true
        let retryBoundary = state.pendingAttempts.contains(2)
            && state.followUpAt.map { now >= $0.addingTimeInterval(Self.retryGrace) } == true
        if dueBoundary || followUpBoundary || retryBoundary {
            await reconcileNotifications()
        }
    }

    func handleLifecycle(_ event: MacLifecycleEvent) async {
        switch event {
        case .willSleep:
            onDismiss?()
            if state.phase == .pausedToday { return }
            if state.phase.isSession {
                await endSession(source: .lifecycle)
            } else {
                await notifications.removeRequestIDs(await managedNotificationIDs())
            }
        case .didWake:
            authorization = await notifications.authorizationStatus()
            if state.phase == .pausedToday, !isPauseExpired { return }
            if state.phase == .dormant,
               state.remindersEnabled,
               isIdleEligible {
                await armSession(mode: .automatic, source: .lifecycle)
            }
            await reconcileNotifications()
        }
    }

    // MARK: User commands

    func enableReminders() async {
        do {
            let granted = try await notifications.requestAuthorization()
            authorization = granted ? .authorized : .denied
            if !granted {
                var next = state
                let oldSession = state.sessionId
                next.phase = .permissionDenied
                next.remindersEnabled = false
                clearSessionFields(&next)
                let event = makeEvent(kind: .permissionDenied,
                                      next: next,
                                      sessionId: oldSession,
                                      source: .menuBar)
                guard await commit(next, event: event) else { return }
                await notifications.removeRequestIDs(await managedNotificationIDs())
                return
            }

            var enabled = state
            enabled.remindersEnabled = true
            if enabled.phase == .permissionDenied { enabled.phase = .dormant }
            let event = makeEvent(kind: .remindersEnabled,
                                  next: enabled,
                                  source: .menuBar)
            guard await commit(enabled, event: event) else { return }

            if state.phase == .dormant, isIdleEligible {
                await armSession(mode: .automatic, source: .menuBar)
            }
        } catch {
            authorization = .denied
            failClosed(error)
        }
    }

    func refreshAuthorization() async {
        authorization = await notifications.authorizationStatus()
        guard isAuthorizationGranted, state.phase == .permissionDenied else { return }
        var next = state
        next.phase = .dormant
        next.remindersEnabled = true
        let event = makeEvent(kind: .remindersEnabled, next: next, source: .lifecycle)
        guard await commit(next, event: event) else { return }
        if isIdleEligible { await armSession(mode: .automatic, source: .lifecycle) }
    }

    func startManualSession() async {
        guard state.phase != .pausedToday, !state.phase.isSession else { return }
        await armSession(mode: .manual, source: .menuBar)
    }

    func pauseToday() async {
        let oldSession = state.sessionId
        var next = state
        next.phase = .pausedToday
        next.pausedUntil = startOfTomorrow
        clearSessionFields(&next)
        let event = makeEvent(kind: .paused,
                              next: next,
                              sessionId: oldSession,
                              action: MacNotificationAction.pauseToday.rawValue,
                              source: .menuBar)
        guard await commit(next, event: event) else { return }
        await notifications.removeRequestIDs(await managedNotificationIDs())
        onDismiss?()
        await refreshDashboardMetrics()
    }

    func handleNotificationAction(sessionId: String?,
                                  attempt: Int?,
                                  actionIdentifier: String) async {
        await reconcileNotifications()
        guard let sessionId,
              let attempt,
              state.sessionId == sessionId,
              state.pendingAttempts.contains(attempt),
              let action = MacNotificationAction(rawValue: actionIdentifier)
        else { return }

        switch action {
        case .present, .defaultTap:
            await present(sessionId: sessionId, attempt: attempt, action: actionIdentifier)
        case .snooze:
            await snooze(sessionId: sessionId, attempt: attempt, action: actionIdentifier)
        case .pauseToday:
            await pauseFromNotification(sessionId: sessionId, attempt: attempt, action: actionIdentifier)
        }
    }

    func completeCurrent() async {
        guard state.phase == .presenting else { return }
        let oldState = state
        let oldSession = oldState.sessionId
        let oldMove = oldState.moveId
        let next = makeNextSession(from: oldState)
        let event = makeEvent(kind: .completed,
                              next: next,
                              sessionId: oldSession,
                              moveId: oldMove,
                              source: .menuBar)
        guard await commit(next, event: event) else { return }
        await scheduleNotifications(for: state)
    }

    func skipCurrent() async {
        guard state.phase == .presenting else { return }
        let oldState = state
        let oldSession = oldState.sessionId
        let oldMove = oldState.moveId
        let next = makeNextSession(from: oldState)
        let event = makeEvent(kind: .skipped,
                              next: next,
                              sessionId: oldSession,
                              moveId: oldMove,
                              source: .menuBar)
        guard await commit(next, event: event) else { return }
        await scheduleNotifications(for: state)
    }

    // MARK: Notification reconciliation

    private func reconcileNotifications() async {
        let pending = await notifications.pendingRequestIDs()
        let delivered = await notifications.deliveredRequestIDs()
        let expectedIDs = Set<String>(state.pendingAttempts.compactMap { attempt in
            guard let sessionId = state.sessionId else { return nil }
            return MacNotificationConstants.requestID(sessionId: sessionId, attempt: attempt)
        })
        let unexpected = pending.union(delivered).subtracting(expectedIDs)
        if !unexpected.isEmpty { await notifications.removeRequestIDs(unexpected) }

        guard let sessionId = state.sessionId, !state.pendingAttempts.isEmpty else { return }
        let now = currentDate

        for attempt in state.pendingAttempts.sorted() {
            guard state.pendingAttempts.contains(attempt) else { continue }
            let requestID = MacNotificationConstants.requestID(sessionId: sessionId, attempt: attempt)
            if delivered.contains(requestID), !state.observedAttempts.contains(attempt) {
                var next = state
                next.observedAttempts.insert(attempt)
                next.lastDeliveryObservedAt = now
                let event = makeEvent(kind: .deliveryObserved,
                                      next: next,
                                      sessionId: sessionId,
                                      attempt: attempt,
                                      source: .notification)
                guard await commit(next, event: event) else { return }
                await notifications.removeDelivered(sessionId: sessionId, attempts: [attempt])
            }
        }

        if state.phase == .active,
           state.dueAt.map({ now >= $0 }) == true {
            var next = state
            next.phase = .due
            next.transitionAt = now
            let event = makeEvent(kind: .deliveryWindowElapsed,
                                  next: next,
                                  sessionId: sessionId,
                                  attempt: 1,
                                  source: .timer)
            guard await commit(next, event: event) else { return }
        } else if state.phase == .snoozed,
                  state.followUpAt.map({ now >= $0 }) == true {
            var next = state
            next.phase = .due
            next.transitionAt = now
            let event = makeEvent(kind: .deliveryWindowElapsed,
                                  next: next,
                                  sessionId: sessionId,
                                  attempt: 2,
                                  source: .timer)
            guard await commit(next, event: event) else { return }
        }

        guard state.sessionId == sessionId else { return }
        if state.pendingAttempts.contains(2),
           let followUpAt = state.followUpAt,
           now >= followUpAt.addingTimeInterval(Self.retryGrace),
           (state.observedAttempts.contains(2)
            || !pending.contains(MacNotificationConstants.requestID(sessionId: sessionId, attempt: 2))) {
            await enterRetryQuiet(sessionId: sessionId, now: now)
            return
        }

        var missingFutureAttempts = Set<Int>()
        for attempt in state.pendingAttempts {
            guard !state.observedAttempts.contains(attempt),
                  let date = state.notificationDate(for: attempt),
                  date > now
            else { continue }
            let requestID = MacNotificationConstants.requestID(sessionId: sessionId, attempt: attempt)
            if !pending.contains(requestID) { missingFutureAttempts.insert(attempt) }
        }
        for attempt in missingFutureAttempts.sorted() {
            await scheduleNotification(for: state, attempt: attempt)
        }

        var elapsedAttempts = Set<Int>()
        for attempt in state.pendingAttempts {
            guard !state.observedAttempts.contains(attempt),
                  let date = state.notificationDate(for: attempt),
                  date <= now
            else { continue }
            let requestID = MacNotificationConstants.requestID(sessionId: sessionId, attempt: attempt)
            if !pending.contains(requestID) { elapsedAttempts.insert(attempt) }
        }
        for attempt in elapsedAttempts.sorted() {
            var next = state
            next.pendingAttempts.remove(attempt)
            let event = makeEvent(kind: .deliveryWindowElapsed,
                                  next: next,
                                  sessionId: sessionId,
                                  attempt: attempt,
                                  source: .timer)
            guard await commit(next, event: event) else { return }
        }
    }

    private func enterRetryQuiet(sessionId: String, now: Date) async {
        var next = state
        next.phase = .retryQuiet
        next.quietUntil = now.addingTimeInterval(Self.retryQuietInterval)
        next.dueAt = nil
        next.followUpAt = nil
        next.pendingAttempts = []
        next.observedAttempts = []
        next.transitionAt = now
        let event = makeEvent(kind: .retryQuiet,
                              next: next,
                              sessionId: sessionId,
                              attempt: 2,
                              source: .timer)
        guard await commit(next, event: event) else { return }
        await notifications.remove(sessionId: sessionId, attempts: [1, 2])
        await notifications.removeDelivered(sessionId: sessionId, attempts: [1, 2])
    }

    // MARK: Action transitions

    private func present(sessionId: String, attempt: Int, action: String) async {
        guard let moveId = state.moveId else { return }
        var next = state
        next.phase = .presenting
        next.pendingAttempts = []
        next.observedAttempts = []
        next.lastResponseAt = currentDate
        next.transitionAt = currentDate
        let responseEvent = makeEvent(kind: .responded,
                                      next: next,
                                      sessionId: sessionId,
                                      attempt: attempt,
                                      action: action,
                                      source: .notification)
        guard await commit(next, event: responseEvent) else { return }

        let presentedEvent = makeEvent(kind: .presented,
                                       next: next,
                                       sessionId: sessionId,
                                       attempt: attempt,
                                       moveId: moveId,
                                       source: .notification)
        guard await commit(next, event: presentedEvent) else { return }
        await notifications.remove(sessionId: sessionId, attempts: [1, 2])
        await notifications.removeDelivered(sessionId: sessionId, attempts: [1, 2])
        onPresent?(stretch(for: moveId), StretchSnapshot())
    }

    private func snooze(sessionId: String, attempt: Int, action: String) async {
        if attempt == 1 {
            var next = state
            next.phase = .snoozed
            next.followUpAt = currentDate.addingTimeInterval(Self.snoozeInterval)
            next.pendingAttempts = [2]
            next.observedAttempts.remove(2)
            next.lastResponseAt = currentDate
            next.transitionAt = currentDate
            let responseEvent = makeEvent(kind: .responded,
                                          next: next,
                                          sessionId: sessionId,
                                          attempt: attempt,
                                          action: action,
                                          source: .notification)
            guard await commit(next, event: responseEvent) else { return }
            let snoozeEvent = makeEvent(kind: .snoozed,
                                        next: next,
                                        sessionId: sessionId,
                                        attempt: attempt,
                                        source: .notification)
            guard await commit(next, event: snoozeEvent) else { return }
            await notifications.remove(sessionId: sessionId, attempts: [1, 2])
            await notifications.removeDelivered(sessionId: sessionId, attempts: [1, 2])
            await scheduleNotification(for: state, attempt: 2)
        } else {
            await quietFromAction(sessionId: sessionId, attempt: attempt, action: action)
        }
    }

    private func quietFromAction(sessionId: String, attempt: Int, action: String) async {
        var next = state
        next.phase = .retryQuiet
        next.quietUntil = currentDate.addingTimeInterval(Self.retryQuietInterval)
        next.dueAt = nil
        next.followUpAt = nil
        next.pendingAttempts = []
        next.observedAttempts = []
        next.lastResponseAt = currentDate
        next.transitionAt = currentDate
        let responseEvent = makeEvent(kind: .responded,
                                      next: next,
                                      sessionId: sessionId,
                                      attempt: attempt,
                                      action: action,
                                      source: .notification)
        guard await commit(next, event: responseEvent) else { return }
        let quietEvent = makeEvent(kind: .retryQuiet,
                                   next: next,
                                   sessionId: sessionId,
                                   attempt: attempt,
                                   source: .notification)
        guard await commit(next, event: quietEvent) else { return }
        await notifications.remove(sessionId: sessionId, attempts: [1, 2])
        await notifications.removeDelivered(sessionId: sessionId, attempts: [1, 2])
    }

    private func pauseFromNotification(sessionId: String, attempt: Int, action: String) async {
        var next = state
        next.phase = .pausedToday
        next.pausedUntil = startOfTomorrow
        clearSessionFields(&next)
        let event = makeEvent(kind: .paused,
                              next: next,
                              sessionId: sessionId,
                              attempt: attempt,
                              action: action,
                              source: .notification)
        guard await commit(next, event: event) else { return }
        await notifications.remove(sessionId: sessionId, attempts: [1, 2])
        await notifications.removeDelivered(sessionId: sessionId, attempts: [1, 2])
        onDismiss?()
    }

    // MARK: Persistence and scheduling

    private func armSession(mode: MacSessionMode, source: MacEventSource) async {
        guard state.phase != .pausedToday else { return }
        let now = currentDate
        var next = MacSessionState()
        next.remindersEnabled = state.remindersEnabled
        next.phase = mode == .manual ? .manualActive : .active
        next.mode = mode
        next.sessionId = UUID().uuidString
        next.moveId = StretchLibrary.all.first?.id
        next.dueAt = now.addingTimeInterval(Self.interval)
        next.followUpAt = next.dueAt?.addingTimeInterval(Self.followUpInterval)
        next.pendingAttempts = [1, 2]
        next.transitionAt = now
        let event = makeEvent(kind: .scheduled,
                              next: next,
                              sessionId: next.sessionId,
                              moveId: next.moveId,
                              dueAt: next.dueAt,
                              source: source)
        guard await commit(next, event: event) else { return }
        await scheduleNotifications(for: state)
    }

    private func scheduleNotifications(for currentState: MacSessionState) async {
        guard currentState.sessionId != nil else { return }
        for attempt in currentState.pendingAttempts.sorted() {
            await scheduleNotification(for: currentState, attempt: attempt)
        }
    }

    private func scheduleNotification(for currentState: MacSessionState, attempt: Int) async {
        guard isAuthorizationGranted,
              let sessionId = currentState.sessionId,
              let moveId = currentState.moveId,
              let date = currentState.notificationDate(for: attempt),
              date > currentDate
        else { return }
        let move = stretch(for: moveId)
        let payload = MacNotificationPayload(sessionId: sessionId,
                                             attempt: attempt,
                                             moveId: move.id,
                                             title: String(localized: "A little reset?"),
                                             body: String(localized: "Ease your neck right for 15 seconds? Stop if it hurts."))
        do {
            try await notifications.schedule(payload, at: date)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func endSession(source: MacEventSource) async {
        guard state.phase.isSession else { return }
        let oldSession = state.sessionId
        var next = state
        clearSessionFields(&next)
        next.phase = .dormant
        next.transitionAt = currentDate
        let event = makeEvent(kind: .sessionEnded,
                              next: next,
                              sessionId: oldSession,
                              source: source)
        guard await commit(next, event: event) else { return }
        if let oldSession {
            await notifications.remove(sessionId: oldSession, attempts: [1, 2])
            await notifications.removeDelivered(sessionId: oldSession, attempts: [1, 2])
        }
    }

    private func endInterruptedSession() async {
        let oldSession = state.sessionId
        let mode = state.mode
        var next = makeNextSession(from: state)
        next.mode = mode
        let event = makeEvent(kind: .skipped,
                              next: next,
                              sessionId: oldSession,
                              source: .lifecycle)
        guard await commit(next, event: event) else { return }
        await scheduleNotifications(for: state)
        onDismiss?()
    }

    private func resetPause() async {
        var next = state
        next.phase = .dormant
        next.pausedUntil = nil
        next.transitionAt = currentDate
        let event = makeEvent(kind: .sessionEnded, next: next, source: .lifecycle)
        guard await commit(next, event: event) else { return }
        if state.remindersEnabled, isIdleEligible {
            await armSession(mode: .automatic, source: .lifecycle)
        }
    }

    private func commit(_ next: MacSessionState, event: MacEvent) async -> Bool {
        do {
            try await store.commit(state: next, event: event)
            state = next
            await refreshDashboardMetrics()
            return true
        } catch {
            failClosed(error)
            return false
        }
    }

    private func refreshDashboardMetrics() async {
        let start = Calendar.current.startOfDay(for: currentDate)
        do {
            dashboardMetrics = try await store.metrics(since: start)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func failClosed(_ error: Error) {
        lastError = error.localizedDescription
        let remindersEnabled = state.remindersEnabled
        state = MacSessionState()
        state.remindersEnabled = remindersEnabled
    }

    // MARK: Helpers

    private func makeNextSession(from oldState: MacSessionState) -> MacSessionState {
        let now = currentDate
        var next = MacSessionState()
        next.remindersEnabled = oldState.remindersEnabled
        next.phase = oldState.mode == .manual ? .manualActive : .active
        next.mode = oldState.mode
        next.sessionId = UUID().uuidString
        next.moveId = StretchLibrary.all.first?.id
        next.dueAt = now.addingTimeInterval(Self.interval)
        next.followUpAt = next.dueAt?.addingTimeInterval(Self.followUpInterval)
        next.pendingAttempts = [1, 2]
        next.transitionAt = now
        return next
    }

    private func clearSessionFields(_ state: inout MacSessionState) {
        state.sessionId = nil
        state.moveId = nil
        state.dueAt = nil
        state.followUpAt = nil
        state.quietUntil = nil
        state.pendingAttempts = []
        state.observedAttempts = []
        state.lastDeliveryObservedAt = nil
        state.lastResponseAt = nil
        state.transitionAt = currentDate
    }

    private func makeEvent(kind: MacEventKind,
                           next: MacSessionState,
                           sessionId: String? = nil,
                           attempt: Int? = nil,
                           action: String? = nil,
                           moveId: String? = nil,
                           dueAt: Date? = nil,
                           source: MacEventSource) -> MacEvent {
        MacEvent(timestamp: currentDate,
                 kind: kind,
                 state: next.phase,
                 sessionId: sessionId ?? next.sessionId,
                 attempt: attempt,
                 actionIdentifier: action,
                 moveId: moveId ?? next.moveId,
                 dueAt: dueAt ?? next.dueAt,
                 source: source,
                 mode: next.mode,
                 appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
    }

    private func stretch(for moveId: String) -> Stretch {
        StretchLibrary.all.first(where: { $0.id == moveId }) ?? StretchLibrary.all[0]
    }

    private var isAuthorizationGranted: Bool {
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
    }

    private var isIdleEligible: Bool {
        guard let idle = idleProvider.secondsSinceInteraction() else { return false }
        return idle < Self.idleExpiry
    }

    private var isEligibleToRecover: Bool {
        guard state.remindersEnabled else { return false }
        guard let idle = idleProvider.secondsSinceInteraction() else { return false }
        return idle < Self.idleExpiry && !isClockStale
    }

    private var isClockStale: Bool {
        let now = currentDate
        let dates = [state.dueAt, state.followUpAt].compactMap { $0 }
        guard !dates.isEmpty else { return false }
        return dates.contains { $0 > now.addingTimeInterval(24 * 60 * 60) || $0 < now.addingTimeInterval(-24 * 60 * 60) }
    }

    private var isPauseExpired: Bool {
        guard let pausedUntil = state.pausedUntil else { return true }
        return currentDate >= pausedUntil
    }

    private var startOfTomorrow: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: currentDate)) ?? currentDate
    }

    /// Wall-clock deadlines survive relaunch, but while this process is alive
    /// monotonic time prevents a manual clock rollback from postponing a
    /// reminder that was already due.
    private var currentDate: Date {
        let wall = clock.now
        let monotonic = clock.monotonicSeconds
        guard let anchor = processClockAnchor else {
            processClockAnchor = (wall: wall, monotonic: monotonic)
            return wall
        }
        let elapsed = max(0, monotonic - anchor.monotonic)
        return max(wall, anchor.wall.addingTimeInterval(elapsed))
    }

    private func managedNotificationIDs() async -> Set<String> {
        await notifications.pendingRequestIDs().union(notifications.deliveredRequestIDs())
    }
}

extension MacSessionPhase {
    var isSession: Bool {
        switch self {
        case .active, .manualActive, .due, .snoozed, .presenting:
            return true
        default:
            return false
        }
    }

    var isAutomaticSession: Bool {
        isSession && self != .manualActive
    }
}
