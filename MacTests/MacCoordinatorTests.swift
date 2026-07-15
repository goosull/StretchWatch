import XCTest

@MainActor
final class MacCoordinatorTests: XCTestCase {
    func testMacStateMapsNotificationAttemptsToDurableDates() {
        let due = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let followUp = due.addingTimeInterval(15 * 60)
        var state = MacSessionState()
        state.dueAt = due
        state.followUpAt = followUp

        XCTAssertEqual(state.notificationDate(for: 1), due)
        XCTAssertEqual(state.notificationDate(for: 2), followUp)
        XCTAssertNil(state.notificationDate(for: 3))
    }

    func testMacActionEventHasStableIdempotencyKey() {
        let event = MacEvent(timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000),
                             kind: .responded,
                             state: .presenting,
                             sessionId: "session-1",
                             attempt: 2,
                             actionIdentifier: MacNotificationAction.present.rawValue,
                             moveId: "neck-right",
                             dueAt: nil,
                             source: .notification,
                             mode: .automatic,
                             appVersion: "0.1.0")

        XCTAssertEqual(event.idempotencyKey, "session-1|2|now")
    }

    func testMacSQLiteStoreCommitsStateAndEventTogether() async throws {
        let store = try MacSQLiteStateStore(inMemory: true)
        var state = MacSessionState()
        state.phase = .active
        state.sessionId = "session-1"
        state.dueAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let event = MacEvent(timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000),
                             kind: .scheduled,
                             state: .active,
                             sessionId: state.sessionId,
                             attempt: 1,
                             actionIdentifier: nil,
                             moveId: "neck-right",
                             dueAt: state.dueAt,
                             source: .timer,
                             mode: .automatic,
                             appVersion: "0.1.0")

        try await store.commit(state: state, event: event)

        let loaded = try await store.load()
        let eventCount = try await store.eventCount()
        XCTAssertEqual(loaded, state)
        XCTAssertEqual(eventCount, 1)
    }

    func testMacSQLiteStoreDoesNotRepeatAnActionEvent() async throws {
        let store = try MacSQLiteStateStore(inMemory: true)
        let first = MacEvent(timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000),
                             kind: .responded,
                             state: .presenting,
                             sessionId: "session-1",
                             attempt: 2,
                             actionIdentifier: MacNotificationAction.present.rawValue,
                             moveId: "neck-right",
                             dueAt: nil,
                             source: .notification,
                             mode: .automatic,
                             appVersion: "0.1.0")
        var firstState = MacSessionState()
        firstState.phase = .presenting
        firstState.sessionId = "session-1"
        try await store.commit(state: firstState, event: first)

        var secondState = firstState
        secondState.phase = .cooldown
        try await store.commit(state: secondState, event: first)

        let loaded = try await store.load()
        let eventCount = try await store.eventCount()
        XCTAssertEqual(loaded, firstState)
        XCTAssertEqual(eventCount, 1)
    }

    func testEnableRemindersArmsTwoRecoverableAttempts() async throws {
        let clock = MacTestClock(now: Date(timeIntervalSinceReferenceDate: 800_000_000))
        let notifications = MacTestNotifications()
        let coordinator = try makeCoordinator(clock: clock, notifications: notifications)

        await coordinator.bootstrapForTesting()
        XCTAssertEqual(coordinator.state.phase, .dormant)

        await coordinator.enableReminders()

        XCTAssertEqual(coordinator.state.phase, .active)
        XCTAssertEqual(coordinator.state.pendingAttempts, [1, 2])
        XCTAssertEqual(notifications.pending, [
            MacNotificationConstants.requestID(sessionId: coordinator.state.sessionId!, attempt: 1),
            MacNotificationConstants.requestID(sessionId: coordinator.state.sessionId!, attempt: 2)
        ])
    }

    func testFirstNotificationSnoozeMovesOnlyFollowUpTenMinutes() async throws {
        let clock = MacTestClock(now: Date(timeIntervalSinceReferenceDate: 800_000_000))
        let notifications = MacTestNotifications()
        let coordinator = try makeCoordinator(clock: clock, notifications: notifications)
        await coordinator.enableReminders()

        let sessionId = try XCTUnwrap(coordinator.state.sessionId)
        clock.now = try XCTUnwrap(coordinator.state.dueAt)
        await coordinator.handleNotificationAction(sessionId: sessionId,
                                                    attempt: 1,
                                                    actionIdentifier: MacNotificationAction.snooze.rawValue)

        XCTAssertEqual(coordinator.state.phase, .snoozed)
        XCTAssertEqual(coordinator.state.pendingAttempts, [2])
        XCTAssertEqual(coordinator.state.followUpAt, clock.now.addingTimeInterval(MacSessionCoordinator.snoozeInterval))
        XCTAssertEqual(notifications.pending, [MacNotificationConstants.requestID(sessionId: sessionId, attempt: 2)])
    }

    func testNotificationTapPresentsAndCompletionStartsFreshCountdown() async throws {
        let clock = MacTestClock(now: Date(timeIntervalSinceReferenceDate: 800_000_000))
        let notifications = MacTestNotifications()
        let coordinator = try makeCoordinator(clock: clock, notifications: notifications)
        var presented = false
        coordinator.onPresent = { _, _ in presented = true }
        await coordinator.enableReminders()

        let oldSession = try XCTUnwrap(coordinator.state.sessionId)
        clock.now = try XCTUnwrap(coordinator.state.dueAt)
        await coordinator.handleNotificationAction(sessionId: oldSession,
                                                    attempt: 1,
                                                    actionIdentifier: MacNotificationAction.present.rawValue)
        XCTAssertTrue(presented)
        XCTAssertEqual(coordinator.state.phase, .presenting)

        await coordinator.completeCurrent()

        XCTAssertEqual(coordinator.state.phase, .active)
        XCTAssertNotEqual(coordinator.state.sessionId, oldSession)
        XCTAssertEqual(coordinator.state.pendingAttempts, [1, 2])
    }

    func testDeliveredFollowUpThatIsIgnoredEntersQuietRecovery() async throws {
        let clock = MacTestClock(now: Date(timeIntervalSinceReferenceDate: 800_000_000))
        let notifications = MacTestNotifications()
        let coordinator = try makeCoordinator(clock: clock, notifications: notifications)
        await coordinator.enableReminders()

        let sessionId = try XCTUnwrap(coordinator.state.sessionId)
        let followUp = try XCTUnwrap(coordinator.state.followUpAt)
        let followUpID = MacNotificationConstants.requestID(sessionId: sessionId, attempt: 2)
        notifications.pending.remove(followUpID)
        notifications.delivered.insert(followUpID)
        clock.now = followUp.addingTimeInterval(MacSessionCoordinator.retryGrace)

        await coordinator.handleNotificationAction(sessionId: sessionId,
                                                    attempt: 2,
                                                    actionIdentifier: MacNotificationAction.present.rawValue)

        XCTAssertEqual(coordinator.state.phase, .retryQuiet)
        XCTAssertEqual(coordinator.state.pendingAttempts, [])
        XCTAssertNotNil(coordinator.state.quietUntil)
    }

    func testTenMinutesWithoutInputEndsAutomaticSession() async throws {
        let clock = MacTestClock(now: Date(timeIntervalSinceReferenceDate: 800_000_000))
        let notifications = MacTestNotifications()
        let idle = MacTestIdleTime()
        let coordinator = MacSessionCoordinator(store: try MacSQLiteStateStore(inMemory: true),
                                                 idleProvider: idle,
                                                 clock: clock,
                                                 notifications: notifications)
        await coordinator.enableReminders()
        XCTAssertEqual(coordinator.state.phase, .active)

        idle.idle = MacSessionCoordinator.idleExpiry
        await coordinator.tickForTesting()

        XCTAssertEqual(coordinator.state.phase, .dormant)
        XCTAssertTrue(notifications.pending.isEmpty)
    }

    private func makeCoordinator(clock: MacTestClock,
                                 notifications: MacTestNotifications) throws -> MacSessionCoordinator {
        MacSessionCoordinator(store: try MacSQLiteStateStore(inMemory: true),
                               idleProvider: MacTestIdleTime(),
                               clock: clock,
                               notifications: notifications)
    }
}

final class MacTestClock: MacClock, @unchecked Sendable {
    var now: Date

    init(now: Date) { self.now = now }

    var monotonicSeconds: TimeInterval { now.timeIntervalSinceReferenceDate }
}

final class MacTestIdleTime: IdleTimeProviding, @unchecked Sendable {
    var idle: TimeInterval = 0

    func secondsSinceInteraction() -> TimeInterval? { idle }
}

final class MacTestNotifications: MacNotificationClient, @unchecked Sendable {
    var authorization: MacNotificationAuthorization = .authorized
    var pending = Set<String>()
    var delivered = Set<String>()
    var payloads = [String: MacNotificationPayload]()

    func registerCategory() {}
    func requestAuthorization() async throws -> Bool {
        authorization = .authorized
        return true
    }
    func authorizationStatus() async -> MacNotificationAuthorization { authorization }
    func pendingRequestIDs() async -> Set<String> { pending }
    func deliveredRequestIDs() async -> Set<String> { delivered }

    func schedule(_ payload: MacNotificationPayload, at date: Date) async throws {
        let id = MacNotificationConstants.requestID(sessionId: payload.sessionId, attempt: payload.attempt)
        pending.insert(id)
        payloads[id] = payload
    }

    func remove(sessionId: String, attempts: Set<Int>) async {
        await removeRequestIDs(Set(attempts.map { MacNotificationConstants.requestID(sessionId: sessionId, attempt: $0) }))
    }

    func removeDelivered(sessionId: String, attempts: Set<Int>) async {
        delivered.subtract(attempts.map { MacNotificationConstants.requestID(sessionId: sessionId, attempt: $0) })
    }

    func removeRequestIDs(_ ids: Set<String>) async {
        pending.subtract(ids)
        delivered.subtract(ids)
        ids.forEach { payloads.removeValue(forKey: $0) }
    }
}
