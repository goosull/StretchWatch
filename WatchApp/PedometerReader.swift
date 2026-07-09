import Foundation
import CoreMotion

/// Retains a CMPedometer and bridges its completion-handler API to async/await.
/// The retrospective query works even when the app wasn't running: the motion
/// coprocessor logs steps continuously and keeps ~7 days.
final class PedometerReader: @unchecked Sendable {
    static let shared = PedometerReader()
    private let pedometer = CMPedometer()

    var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    /// Steps over the trailing window ending now, or nil if unavailable/error.
    func stepsInTrailingWindow(_ window: TimeInterval = StretchConfig.pedometerWindow) async -> Int? {
        guard isAvailable else { return nil }
        let end = Date()
        let start = end.addingTimeInterval(-window)
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                continuation.resume(returning: data?.numberOfSteps.intValue)
            }
        }
    }
}
