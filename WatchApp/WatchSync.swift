import Foundation
import WatchConnectivity

/// Pushes the count/streak snapshot from the watch (source of truth) to the
/// iPhone over WatchConnectivity. One-way: the phone dashboard only reads.
/// `updateApplicationContext` coalesces to the latest value and delivers in the
/// background, which is exactly right for a "current state" snapshot.
final class WatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSync()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ snapshot: StretchSnapshot) {
        guard WCSession.default.activationState == .activated,
              let data = try? JSONEncoder.spike.encode(snapshot) else { return }
        try? WCSession.default.updateApplicationContext(["snapshot": data])
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
}
