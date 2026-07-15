import AppKit
import SwiftUI
import UserNotifications

@main
struct StretchWatchMacApp: App {
    @StateObject private var runtime: MacRuntime

    init() {
        _runtime = StateObject(wrappedValue: MacRuntime.shared)
    }

    var body: some Scene {
        MenuBarExtra {
            MacMenuBarView(coordinator: runtime.coordinator)
        } label: {
            Image(systemName: "figure.seated.side")
                .accessibilityLabel("StretchWatch")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class MacRuntime: ObservableObject {
    static let shared = MacRuntime()

    let coordinator: MacSessionCoordinator
    private let lifecycle = WorkspaceLifecycleAdapter()
    private let panelController = MacPanelController()
    private let notificationDelegate: MacNotificationDelegate

    private init() {
        let store: any MacStateStore
        do {
            store = try MacSQLiteStateStore()
        } catch {
            store = MacUnavailableStateStore(error: error)
        }

        let notifications = LocalMacNotificationClient()
        coordinator = MacSessionCoordinator(store: store,
                                             idleProvider: QuartzIdleTimeAdapter(),
                                             notifications: notifications)
        notificationDelegate = MacNotificationDelegate(coordinator: coordinator)

        UNUserNotificationCenter.current().delegate = notificationDelegate
        lifecycle.onEvent = { [weak coordinator] event in
            Task { @MainActor in
                await coordinator?.handleLifecycle(event)
            }
        }
        coordinator.onPresent = { [weak panelController, weak coordinator] stretch, snapshot in
            guard let panelController, let coordinator else { return }
            panelController.present(stretch: stretch, snapshot: snapshot, coordinator: coordinator)
        }
        coordinator.onDismiss = { [weak panelController] in
            panelController?.dismiss()
        }

        lifecycle.start()
        coordinator.start()
    }
}

/// A readable failure mode if the application-support directory or SQLite
/// schema cannot be opened. The coordinator then fails closed to Dormant while
/// the menu-bar shell remains usable.
actor MacUnavailableStateStore: MacStateStore {
    private let errorMessage: String

    init(error: Error) {
        self.errorMessage = error.localizedDescription
    }

    private var failure: MacStoreError { .queryFailed(errorMessage) }

    func load() async throws -> MacSessionState? { throw failure }
    func commit(state: MacSessionState, event: MacEvent) async throws { throw failure }
    func pruneEvents(olderThan date: Date) async throws { throw failure }
    func eventCount() async throws -> Int { throw failure }
    func metrics(since date: Date) async throws -> MacDashboardMetrics { throw failure }
}
