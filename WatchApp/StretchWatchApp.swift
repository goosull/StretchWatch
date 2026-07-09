import SwiftUI
import WatchKit

@main
struct StretchWatch_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var router = AppRouter.shared

    var body: some Scene {
        WindowGroup {
            HomeView().environmentObject(router)
        }
    }
}

/// Handles launch and the background refresh task — the only place the trigger
/// can run its pedometer check + reschedule while the app isn't open.
final class AppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { await TriggerEngine.onLaunch() }
    }

    func applicationDidBecomeActive() {
        Task { await TriggerEngine.onForeground() }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refresh as WKApplicationRefreshBackgroundTask:
                Task {
                    await TriggerEngine.onBackgroundWake()
                    refresh.setTaskCompletedWithSnapshot(false)
                }
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
