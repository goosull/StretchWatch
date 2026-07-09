import Foundation

/// One recorded moment in the Spike #1 diagnostic. The spike answers a single
/// question: **when watchOS wakes us in the background, does the wake land
/// early enough (before the next scheduled notification fires) to suppress it,
/// and had the user actually moved?** That is the suppression hit-rate.
struct SpikeEvent: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case wake            // background refresh handler ran
        case armedRefresh    // we scheduled the next background refresh
        case armedNotif      // we scheduled the next one-shot notification
        case foreground      // app came to foreground
        case launch          // app process launched
    }

    var id = UUID()
    var date: Date
    var kind: Kind
    /// Steps in the trailing ~40 min window (nil when pedometer unavailable / not a wake).
    var stepsLast40min: Int?
    /// The next scheduled notification's fire time at the moment of this event.
    var nextFireDate: Date?
    /// Seconds from `date` until `nextFireDate`. Positive = we woke BEFORE the
    /// fire (suppression is possible). Negative/absent = we lost the race.
    var leadSeconds: Double?
    var note: String?

    /// True when this wake could have suppressed a notification: it landed
    /// before the fire AND the user had recently moved (steps > 0).
    var wasSuppressionOpportunity: Bool {
        guard kind == .wake, let lead = leadSeconds, let steps = stepsLast40min else { return false }
        return lead > 0 && steps > 0
    }
}

/// Append-only log persisted to the App Group container as a JSON array.
/// Chosen over SwiftData/CoreData because the complication (a separate process)
/// also reads it, and a Codable append-log with atomic writes avoids the
/// multi-process hazards of a shared CoreData store (per the eng review).
actor SpikeLogStore {
    static let shared = SpikeLogStore()

    private let fileURL = AppGroup.containerURL.appendingPathComponent("spike-log.json")
    private let maxEvents = 2000  // spike backstop; trims oldest

    func append(_ event: SpikeEvent) {
        var events = loadFromDisk()
        events.append(event)
        if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
        writeToDisk(events)
    }

    func all() -> [SpikeEvent] { loadFromDisk() }

    func clear() { writeToDisk([]) }

    /// Aggregate hit-rate stats over all recorded wakes.
    func stats() -> SpikeStats {
        let events = loadFromDisk()
        let wakes = events.filter { $0.kind == .wake }
        let moved = wakes.filter { ($0.stepsLast40min ?? 0) > 0 }
        let opportunities = wakes.filter { $0.wasSuppressionOpportunity }
        let leads = wakes.compactMap { $0.leadSeconds }
        let firstWake = wakes.first?.date
        let lastWake = wakes.last?.date
        let span = (firstWake != nil && lastWake != nil) ? lastWake!.timeIntervalSince(firstWake!) : 0
        let wakesPerHour = span > 0 ? Double(wakes.count) / (span / 3600) : 0
        return SpikeStats(
            totalEvents: events.count,
            wakeCount: wakes.count,
            movedWakeCount: moved.count,
            suppressionOpportunityCount: opportunities.count,
            hitRate: moved.isEmpty ? nil : Double(opportunities.count) / Double(moved.count),
            wakesPerHour: wakesPerHour,
            medianLeadSeconds: leads.sorted(by: <).middle,
            firstWake: firstWake,
            lastWake: lastWake
        )
    }

    private func loadFromDisk() -> [SpikeEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.spike.decode([SpikeEvent].self, from: data)) ?? []
    }

    private func writeToDisk(_ events: [SpikeEvent]) {
        guard let data = try? JSONEncoder.spike.encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

struct SpikeStats: Sendable {
    var totalEvents = 0
    var wakeCount = 0
    var movedWakeCount = 0
    var suppressionOpportunityCount = 0
    /// Suppression hit-rate: of wakes where the user moved, the fraction that
    /// landed before the next fire. `nil` when no moved-wakes yet.
    var hitRate: Double?
    var wakesPerHour: Double = 0
    var medianLeadSeconds: Double?
    var firstWake: Date?
    var lastWake: Date?
}

private extension Array where Element == Double {
    var middle: Double? { isEmpty ? nil : self[count / 2] }
}

extension JSONEncoder {
    static let spike: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
extension JSONDecoder {
    static let spike: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
