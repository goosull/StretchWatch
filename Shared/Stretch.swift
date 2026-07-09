import Foundation

/// A single seated micro-stretch. The content IS the product's interface, so
/// each move carries its own instruction copy, hold time, and a movement
/// direction the glyph animates. All are doable seated, no standing.
struct Stretch: Identifiable, Codable, Sendable, Equatable {
    enum Region: String, Codable, CaseIterable, Sendable {
        case neck, shoulder, wrist, back

        /// Display name for the Settings focus toggles.
        var title: String {
            switch self {
            case .neck:     return "Neck"
            case .shoulder: return "Shoulders"
            case .wrist:    return "Wrists"
            case .back:     return "Back"
            }
        }
    }

    /// The direction the on-screen glyph sweeps, mirroring the movement.
    enum Motion: String, Codable, Sendable {
        case tiltRight, tiltLeft   // ear toward shoulder
        case turnRight, turnLeft   // chin over shoulder
        case rollBack              // shoulder rolls
        case openChest             // pull shoulders back
        case reachUp               // reach overhead
        case wristCircle           // wrist rotation
        case lookDown              // chin to chest, back of neck
        case lookUp                // gentle neck extension
        case shrug                 // lift shoulders and drop
    }

    var id: String
    var region: Region
    /// Second-person, specific, calm. Shown big and used as the notification body.
    var title: String
    var seconds: Int
    var motion: Motion
    /// SF Symbol shown small beside the glyph as a body-part cue.
    var symbol: String
}

/// The v1 set: 4 regions, 2–3 each = 10 moves. Rotates by region so consecutive
/// nudges hit different parts of the body.
enum StretchLibrary {
    static let all: [Stretch] = [
        .init(id: "neck-right",   region: .neck,     title: "Ease your neck right",      seconds: 12, motion: .tiltRight, symbol: "figure.stand"),
        .init(id: "neck-left",    region: .neck,     title: "Ease your neck left",       seconds: 12, motion: .tiltLeft,  symbol: "figure.stand"),
        .init(id: "neck-down",    region: .neck,     title: "Chin to chest, slow",       seconds: 12, motion: .lookDown,  symbol: "figure.stand"),
        .init(id: "sh-roll",      region: .shoulder, title: "Roll your shoulders back",  seconds: 15, motion: .rollBack,  symbol: "figure.arms.open"),
        .init(id: "sh-open",      region: .shoulder, title: "Open your chest",           seconds: 15, motion: .openChest, symbol: "figure.arms.open"),
        .init(id: "sh-reach",     region: .shoulder, title: "Reach up and breathe",      seconds: 15, motion: .reachUp,   symbol: "arrow.up"),
        .init(id: "wrist-r",      region: .wrist,    title: "Circle your right wrist",   seconds: 12, motion: .wristCircle, symbol: "hand.raised"),
        .init(id: "wrist-l",      region: .wrist,    title: "Circle your left wrist",    seconds: 12, motion: .wristCircle, symbol: "hand.raised"),
        .init(id: "back-turn-r",  region: .back,     title: "Turn gently to the right",  seconds: 14, motion: .turnRight, symbol: "figure.walk"),
        .init(id: "back-turn-l",  region: .back,     title: "Turn gently to the left",   seconds: 14, motion: .turnLeft,  symbol: "figure.walk"),
        .init(id: "neck-up",      region: .neck,     title: "Look up, slowly",           seconds: 10, motion: .lookUp,   symbol: "figure.stand"),
        .init(id: "sh-shrug",     region: .shoulder, title: "Lift your shoulders, drop", seconds: 12, motion: .shrug,    symbol: "figure.arms.open"),
        .init(id: "back-side-r",  region: .back,     title: "Lean gently right",         seconds: 14, motion: .tiltRight, symbol: "figure.walk"),
        .init(id: "back-side-l",  region: .back,     title: "Lean gently left",          seconds: 14, motion: .tiltLeft,  symbol: "figure.walk"),
        .init(id: "upper-back",   region: .back,     title: "Round your upper back",     seconds: 14, motion: .lookDown,  symbol: "figure.walk"),
    ]

    /// Pick the next move: rotate to a *different region* than last, never repeat
    /// the exact last move. Deterministic given (lastMoveId, a rotation seed).
    /// `enabledRegions` restricts the pool to the body areas the user opted into;
    /// nil or empty means all regions (we never leave the user with no stretch).
    static func next(afterMoveId lastId: String?, seed: Int,
                     enabledRegions: Set<Stretch.Region>? = nil) -> Stretch {
        let enabled = enabledRegions.flatMap { $0.isEmpty ? nil : $0 }
        let regions = Stretch.Region.allCases.filter { enabled?.contains($0) ?? true }
        let activeRegions = regions.isEmpty ? Stretch.Region.allCases : regions

        let lastRegion = all.first(where: { $0.id == lastId })?.region
        // Advance to the next enabled region in rotation.
        let startIndex = lastRegion.flatMap { activeRegions.firstIndex(of: $0) }.map { $0 + 1 } ?? seed
        for offset in 0..<activeRegions.count {
            let region = activeRegions[(startIndex + offset) % activeRegions.count]
            let candidates = all.filter { $0.region == region && $0.id != lastId }
            if let pick = candidates[safe: seed % max(1, candidates.count)] { return pick }
        }
        // Fallback: any enabled move, avoiding the immediate repeat when possible.
        let pool = all.filter { activeRegions.contains($0.region) }
        let avoidLast = pool.filter { $0.id != lastId }
        let finalPool = avoidLast.isEmpty ? pool : avoidLast
        return finalPool[seed % finalPool.count]
    }
}

/// Gentle milestone moments. Pure so the celebratory line is unit-testable and
/// the session view stays dumb. Calm, text-only (no confetti) — a milestone is a
/// warmer word, not a trophy, in keeping with the anti-Stand tone.
enum StretchMilestone {
    static let streakMarks: Set<Int> = [3, 7, 14, 30, 50, 100, 200, 365]
    static let todayMarks: Set<Int> = [5, 10]

    /// The (today, streak) numbers *after* the just-recorded completion, projected
    /// from the pre-completion snapshot summary. Doing today's first stretch extends
    /// the streak by one; a later same-day stretch leaves the streak unchanged
    /// (the snapshot already counts today once it has any completion).
    static func project(from snap: StretchSnapshot) -> (today: Int, streak: Int) {
        let today = snap.todayCount + 1
        let streak = snap.todayCount == 0 ? snap.streakDays + 1 : snap.streakDays
        return (today, streak)
    }

    /// A gentle line if this completion lands on a milestone, else nil. A streak
    /// milestone outranks the same-day count when both land at once.
    static func line(streakDays: Int, todayCount: Int) -> String? {
        if streakMarks.contains(streakDays) { return "A \(streakDays)-day rhythm." }
        if todayMarks.contains(todayCount)  { return "\(todayCount) today. Lovely." }
        return nil
    }

    /// Convenience: the milestone line for completing a stretch given the
    /// pre-completion snapshot, or nil.
    static func line(afterCompleting snap: StretchSnapshot) -> String? {
        let p = project(from: snap)
        return line(streakDays: p.streak, todayCount: p.today)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
