import Foundation

/// Timing + identifier constants for the trigger. One place so the spike and the
/// product agree. Drop `interval` temporarily (e.g. 3*60) to collect data fast.
enum StretchConfig {
    static let interval: TimeInterval = 40 * 60        // cadence between nudges
    static let wakeLead: TimeInterval = 8 * 60         // wake this far before a fire
    static let pedometerWindow: TimeInterval = 40 * 60 // trailing movement window
    static let minRefreshLead: TimeInterval = 5 * 60   // watchOS refresh floor
    /// Steps above this in the window count as "recently moved" → suppress.
    static let movedStepThreshold = 15

    static let notifIdentifier = "stretch.next"
    static let notifCategory = "STRETCH"
    static let actionComplete = "STRETCH_DONE"
    static let actionSkip = "STRETCH_SKIP"

    // App Group defaults keys
    static let kNextFire = "trigger.nextFireDate"
    static let kSessionId = "trigger.sessionId"
    static let kCurrentMove = "trigger.currentMoveId"
    static let kLastMove = "trigger.lastMoveId"
    static let kSeed = "trigger.seed"
    static let kSnapshot = "trigger.snapshot"
}
