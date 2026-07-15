import Foundation

enum MacSessionPhase: String, Codable, Sendable {
    case dormant
    case active
    case manualActive
    case due
    case snoozed
    case retryQuiet
    case presenting
    case cooldown
    case pausedToday
    case permissionDenied
}

enum MacSessionMode: String, Codable, Sendable {
    case automatic
    case manual
}

enum MacEventKind: String, Codable, Sendable {
    case scheduled
    case deliveryObserved
    case deliveryWindowElapsed
    case responded
    case snoozed
    case presented
    case completed
    case skipped
    case paused
    case retryQuiet
    case permissionDenied
    case storageError
    case remindersEnabled
    case sessionEnded
}

enum MacEventSource: String, Codable, Sendable {
    case timer
    case notification
    case menuBar
    case lifecycle
}

struct MacSessionState: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = MacSessionState.currentSchemaVersion
    var phase: MacSessionPhase = .dormant
    var mode: MacSessionMode = .automatic
    var remindersEnabled = false
    var sessionId: String?
    var moveId: String?
    var dueAt: Date?
    var followUpAt: Date?
    var quietUntil: Date?
    var pendingAttempts: Set<Int> = []
    var observedAttempts: Set<Int> = []
    var pausedUntil: Date?
    var lastDeliveryObservedAt: Date?
    var lastResponseAt: Date?
    var transitionAt = Date()

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, phase, mode, remindersEnabled, sessionId, moveId
        case dueAt, followUpAt, quietUntil, pendingAttempts, observedAttempts
        case pausedUntil, lastDeliveryObservedAt, lastResponseAt, transitionAt
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        phase = try values.decodeIfPresent(MacSessionPhase.self, forKey: .phase) ?? .dormant
        mode = try values.decodeIfPresent(MacSessionMode.self, forKey: .mode) ?? .automatic
        remindersEnabled = try values.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? false
        sessionId = try values.decodeIfPresent(String.self, forKey: .sessionId)
        moveId = try values.decodeIfPresent(String.self, forKey: .moveId)
        dueAt = try values.decodeIfPresent(Date.self, forKey: .dueAt)
        followUpAt = try values.decodeIfPresent(Date.self, forKey: .followUpAt)
        quietUntil = try values.decodeIfPresent(Date.self, forKey: .quietUntil)
        pendingAttempts = try values.decodeIfPresent(Set<Int>.self, forKey: .pendingAttempts) ?? []
        observedAttempts = try values.decodeIfPresent(Set<Int>.self, forKey: .observedAttempts) ?? []
        pausedUntil = try values.decodeIfPresent(Date.self, forKey: .pausedUntil)
        lastDeliveryObservedAt = try values.decodeIfPresent(Date.self, forKey: .lastDeliveryObservedAt)
        lastResponseAt = try values.decodeIfPresent(Date.self, forKey: .lastResponseAt)
        transitionAt = try values.decodeIfPresent(Date.self, forKey: .transitionAt) ?? Date()
    }

    func notificationDate(for attempt: Int) -> Date? {
        switch attempt {
        case 1: return dueAt
        case 2: return followUpAt
        default: return nil
        }
    }

    var isPaused: Bool { phase == .pausedToday }
    var isAutomatic: Bool { mode == .automatic }
}

struct MacEvent: Codable, Sendable, Equatable {
    var id = UUID().uuidString
    var timestamp: Date
    var kind: MacEventKind
    var state: MacSessionPhase
    var sessionId: String?
    var attempt: Int?
    var actionIdentifier: String?
    var moveId: String?
    var dueAt: Date?
    var source: MacEventSource
    var mode: MacSessionMode
    var appVersion: String

    var idempotencyKey: String? {
        guard let sessionId, let attempt, let actionIdentifier else { return nil }
        return "\(sessionId)|\(attempt)|\(actionIdentifier)"
    }
}

struct MacNotificationPayload: Sendable, Equatable {
    var sessionId: String
    var attempt: Int
    var moveId: String
    var title: String
    var body: String
}

enum MacNotificationConstants {
    static let category = "STRETCH_MAC"
    static let now = "STRETCH_MAC_NOW"
    static let snooze = "STRETCH_MAC_SNOOZE"
    static let pauseToday = "STRETCH_MAC_PAUSE_TODAY"

    static func requestID(sessionId: String, attempt: Int) -> String {
        "\(sessionId).\(attempt)"
    }
}

enum MacNotificationAction: String, Sendable {
    case present = "now"
    case snooze = "snooze"
    case pauseToday = "pauseToday"
    case defaultTap = "com.apple.UNNotificationDefaultActionIdentifier"
}

enum MacLifecycleEvent: Sendable {
    case willSleep
    case didWake
}

protocol MacClock: Sendable {
    var now: Date { get }
    var monotonicSeconds: TimeInterval { get }
}

struct SystemMacClock: MacClock {
    var now: Date { Date() }
    var monotonicSeconds: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

protocol IdleTimeProviding: Sendable {
    func secondsSinceInteraction() -> TimeInterval?
}

protocol MacStateStore: AnyObject, Sendable {
    func load() async throws -> MacSessionState?
    func commit(state: MacSessionState, event: MacEvent) async throws
    func pruneEvents(olderThan date: Date) async throws
    func eventCount() async throws -> Int
    func metrics(since date: Date) async throws -> MacDashboardMetrics
}

struct MacDashboardMetrics: Sendable, Equatable {
    var completedToday = 0
    var automaticDeliveryObservedToday = 0
    var automaticRespondedToday = 0
    var automaticPresentedToday = 0
    var automaticCompletedToday = 0
    var manualCompletedToday = 0

    var automaticResponseRate: Double? {
        guard automaticDeliveryObservedToday > 0 else { return nil }
        return Double(automaticRespondedToday) / Double(automaticDeliveryObservedToday)
    }

    var overlayCompletionRate: Double? {
        guard automaticPresentedToday > 0 else { return nil }
        return Double(automaticCompletedToday) / Double(automaticPresentedToday)
    }
}

protocol MacNotificationClient: AnyObject, Sendable {
    func registerCategory()
    func requestAuthorization() async throws -> Bool
    func authorizationStatus() async -> MacNotificationAuthorization
    func pendingRequestIDs() async -> Set<String>
    func deliveredRequestIDs() async -> Set<String>
    func schedule(_ payload: MacNotificationPayload, at date: Date) async throws
    func remove(sessionId: String, attempts: Set<Int>) async
    func removeDelivered(sessionId: String, attempts: Set<Int>) async
    func removeRequestIDs(_ ids: Set<String>) async
}

enum MacNotificationAuthorization: String, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown
}
