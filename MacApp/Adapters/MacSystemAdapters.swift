import AppKit
import CoreGraphics

final class QuartzIdleTimeAdapter: IdleTimeProviding, @unchecked Sendable {
    private let eventTypes: [CGEventType] = [
        .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .scrollWheel, .keyDown, .flagsChanged, .tabletPointer, .tabletProximity
    ]

    func secondsSinceInteraction() -> TimeInterval? {
        let values = eventTypes.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.filter { $0.isFinite && $0 >= 0 }
        return values.min()
    }
}

/// Public workspace notifications are intentionally the only lifecycle signal used by P0.
final class WorkspaceLifecycleAdapter: @unchecked Sendable {
    var onEvent: ((MacLifecycleEvent) -> Void)?
    private var observerTokens: [NSObjectProtocol] = []

    func start() {
        guard observerTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observerTokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification,
                                                  object: nil,
                                                  queue: .main) { [weak self] _ in
            self?.onEvent?(.willSleep)
        })
        observerTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                                  object: nil,
                                                  queue: .main) { [weak self] _ in
            self?.onEvent?(.didWake)
        })
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observerTokens.forEach(center.removeObserver)
        observerTokens.removeAll()
    }
}
