import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Optionally records a completed stretch as an Apple Health *mindful session*,
/// so the minutes surface in Health and the Mindfulness ring. Opt-in and fully
/// guarded: if Health is unavailable, or the user hasn't turned it on, every
/// call is a silent no-op — the app never blocks or crashes on Health.
enum HealthLogger {
    #if canImport(HealthKit)
    private static let store = HKHealthStore()
    private static var mindful: HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: .mindfulSession)
    }

    /// Ask once for permission to write mindful sessions. Safe to call repeatedly.
    static func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable(), let mindful else { return }
        try? await store.requestAuthorization(toShare: [mindful], read: [])
    }

    /// Save a mindful session of `seconds`, ending now. No-op if Health is off.
    static func logMindfulSession(seconds: Int, endingAt end: Date = Date()) async {
        guard HKHealthStore.isHealthDataAvailable(), let mindful else { return }
        let start = end.addingTimeInterval(-Double(max(1, seconds)))
        let sample = HKCategorySample(type: mindful,
                                      value: HKCategoryValue.notApplicable.rawValue,
                                      start: start, end: end)
        try? await store.save(sample)
    }
    #else
    static func requestAuthorization() async {}
    static func logMindfulSession(seconds: Int, endingAt end: Date = Date()) async {}
    #endif
}
