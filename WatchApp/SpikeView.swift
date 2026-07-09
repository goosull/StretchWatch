import SwiftUI

/// Diagnostic screen for Spike #1. NOT product UI — it exists so you can read
/// the suppression hit-rate off your wrist after a few days of wear.
struct SpikeView: View {
    @State private var stats = SpikeStats()
    @State private var recent: [SpikeEvent] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Spike #1").font(.headline)

                statRow("Hit-rate", stats.hitRate.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                statRow("Wakes", "\(stats.wakeCount)")
                statRow("Wakes/hr", String(format: "%.1f", stats.wakesPerHour))
                statRow("Moved wakes", "\(stats.movedWakeCount)")
                statRow("Opportunities", "\(stats.suppressionOpportunityCount)")
                statRow("Median lead", stats.medianLeadSeconds.map { String(format: "%.0fm", $0 / 60) } ?? "—")

                Divider()

                ForEach(recent.reversed().prefix(8)) { e in
                    HStack {
                        Text(e.kind.rawValue).font(.caption2)
                        Spacer()
                        if let s = e.stepsLast40min { Text("\(s) steps").font(.caption2) }
                        if let l = e.leadSeconds { Text(String(format: "%+.0fm", l / 60)).font(.caption2) }
                    }
                    .foregroundStyle(e.wasSuppressionOpportunity ? .green : .secondary)
                }

                Button("Force cycle now") {
                    Task { await TriggerEngine.armNext(); await reload() }
                }
                .font(.caption)
                Button("Clear log", role: .destructive) {
                    Task { await SpikeLogStore.shared.clear(); await reload() }
                }
                .font(.caption)
            }
            .padding(.horizontal, 4)
        }
        .task { await reload() }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption).monospacedDigit()
        }
    }

    private func reload() async {
        stats = await SpikeLogStore.shared.stats()
        recent = await SpikeLogStore.shared.all()
    }
}

#Preview {
    SpikeView()
}
