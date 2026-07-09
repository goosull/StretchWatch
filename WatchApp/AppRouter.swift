import SwiftUI
import UserNotifications

/// Drives which stretch session is on screen. A notification tap, or the
/// "Stretch now" button, sets `activeStretch`; the root view presents it.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var activeStretch: Stretch?
    @Published var activeSessionId: String = "adhoc"

    /// Open the currently-scheduled stretch (from a notification tap).
    func open(sessionId: String, moveId: String) {
        activeSessionId = sessionId
        activeStretch = StretchLibrary.all.first { $0.id == moveId } ?? TriggerEngine.currentStretch
    }

    /// Start a stretch immediately, unprompted.
    func startNow() {
        let move = StretchLibrary.next(afterMoveId: nil, seed: Int(Date().timeIntervalSince1970))
        activeSessionId = "adhoc-\(Int(Date().timeIntervalSince1970))"
        activeStretch = move
    }

    func complete() {
        let sid = activeSessionId, moveId = activeStretch?.id ?? ""
        activeStretch = nil
        Task { await TriggerEngine.complete(sessionId: sid, moveId: moveId) }
    }

    func skip() {
        let sid = activeSessionId, moveId = activeStretch?.id ?? ""
        activeStretch = nil
        Task { await TriggerEngine.skip(sessionId: sid, moveId: moveId) }
    }
}

/// Routes notification actions. Retained for the app's lifetime as a singleton.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    // Show the banner + haptic even while the app is foreground (helps testing).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let sid = info["sessionId"] as? String ?? "adhoc"
        let moveId = info["moveId"] as? String ?? ""

        switch response.actionIdentifier {
        case StretchConfig.actionComplete:
            await TriggerEngine.complete(sessionId: sid, moveId: moveId)
        case StretchConfig.actionSkip:
            await TriggerEngine.skip(sessionId: sid, moveId: moveId)
        default:
            // Tap on the banner body → open the guided session.
            await MainActor.run { AppRouter.shared.open(sessionId: sid, moveId: moveId) }
        }
    }
}
