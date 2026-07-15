import Foundation
import UserNotifications

final class LocalMacNotificationClient: MacNotificationClient, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()

    func registerCategory() {
        let now = UNNotificationAction(identifier: MacNotificationConstants.now,
                                        title: String(localized: "Start now"),
                                        options: [.foreground])
        let snooze = UNNotificationAction(identifier: MacNotificationConstants.snooze,
                                          title: String(localized: "In 10 minutes"),
                                          options: [])
        let pause = UNNotificationAction(identifier: MacNotificationConstants.pauseToday,
                                         title: String(localized: "Pause today"),
                                         options: [])
        let category = UNNotificationCategory(identifier: MacNotificationConstants.category,
                                              actions: [now, snooze, pause],
                                              intentIdentifiers: [],
                                              options: [])
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func authorizationStatus() async -> MacNotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }

    func pendingRequestIDs() async -> Set<String> {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: Set(requests.map(\.identifier)))
            }
        }
    }

    func deliveredRequestIDs() async -> Set<String> {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: Set(notifications.map { $0.request.identifier }))
            }
        }
    }

    func schedule(_ payload: MacNotificationPayload, at date: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default
        content.categoryIdentifier = MacNotificationConstants.category
        content.interruptionLevel = .active
        content.userInfo = [
            "sessionId": payload.sessionId,
            "attempt": payload.attempt,
            "moveId": payload.moveId
        ]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow),
                                                         repeats: false)
        let request = UNNotificationRequest(identifier: MacNotificationConstants.requestID(
            sessionId: payload.sessionId,
            attempt: payload.attempt),
            content: content,
            trigger: trigger)
        try await center.add(request)
    }

    func remove(sessionId: String, attempts: Set<Int>) async {
        let ids = attempts.map { MacNotificationConstants.requestID(sessionId: sessionId, attempt: $0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func removeDelivered(sessionId: String, attempts: Set<Int>) async {
        let ids = attempts.map { MacNotificationConstants.requestID(sessionId: sessionId, attempt: $0) }
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func removeRequestIDs(_ ids: Set<String>) async {
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: Array(ids))
        center.removeDeliveredNotifications(withIdentifiers: Array(ids))
    }
}

final class MacNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var coordinator: MacSessionCoordinator?

    init(coordinator: MacSessionCoordinator) {
        self.coordinator = coordinator
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // The menu bar utility owns the visible guided panel; do not duplicate it with a banner.
        completionHandler([])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let sessionId = userInfo["sessionId"] as? String
        let attempt = userInfo["attempt"] as? Int
        let actionIdentifier = response.actionIdentifier
        Task { @MainActor [weak coordinator] in
            await coordinator?.handleNotificationAction(sessionId: sessionId,
                                                         attempt: attempt,
                                                         actionIdentifier: actionIdentifier)
        }
        completionHandler()
    }
}
