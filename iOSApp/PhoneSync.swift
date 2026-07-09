import Foundation
import WatchConnectivity

/// Receives the watch's snapshot and caches it for the dashboard. The phone
/// never records outcomes — the watch owns the truth.
@MainActor
final class PhoneSync: NSObject, ObservableObject {
    static let shared = PhoneSync()
    @Published var snapshot = StretchSnapshot()

    private let cacheKey = "cached.snapshot"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let snap = try? JSONDecoder.spike.decode(StretchSnapshot.self, from: data) {
            snapshot = snap
        }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func apply(_ data: Data?) {
        guard let data, let snap = try? JSONDecoder.spike.decode(StretchSnapshot.self, from: data) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        snapshot = snap
    }
}

extension PhoneSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        let data = session.receivedApplicationContext["snapshot"] as? Data
        Task { @MainActor in self.apply(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        let data = context["snapshot"] as? Data
        Task { @MainActor in self.apply(data) }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
