import WidgetKit
import SwiftUI

/// Watch-face complication. Two jobs: (1) surface the reward — today's count and
/// the week's rhythm — where the eyes already glance, and (2) keep the app near
/// the active face so watchOS grants the background-refresh budget the
/// suppression check needs.
struct StretchEntry: TimelineEntry {
    let date: Date
    let todayCount: Int
    let minutesToNext: Int?
    /// Weekly context, reused from the snapshot the heatmap already computes.
    let weeklyActiveDays: Int
    let streakDays: Int
    let weeklyCounts: [Int]   // trailing 7 days, oldest first ([6] = today)
}

struct StretchProvider: TimelineProvider {
    func placeholder(in context: Context) -> StretchEntry {
        StretchEntry(date: .now, todayCount: 2, minutesToNext: 40,
                     weeklyActiveDays: 4, streakDays: 3,
                     weeklyCounts: [0, 2, 1, 3, 0, 1, 2])
    }
    func getSnapshot(in context: Context, completion: @escaping (StretchEntry) -> Void) {
        completion(current())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StretchEntry>) -> Void) {
        let refresh = Calendar.current.date(byAdding: .minute, value: 10, to: .now) ?? .now
        completion(Timeline(entries: [current()], policy: .after(refresh)))
    }
    private func current() -> StretchEntry {
        let s = SharedState.snapshot()
        return StretchEntry(date: .now, todayCount: s.todayCount,
                            minutesToNext: SharedState.minutesToNextFire,
                            weeklyActiveDays: s.weeklyActiveDays,
                            streakDays: s.streakDays,
                            weeklyCounts: s.weeklyCounts)
    }
}

struct StretchComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StretchEntry

    var body: some View {
        switch family {
        case .accessoryCircular:    circular
        case .accessoryCorner:      corner
        case .accessoryInline:      Text(inlineText)
        case .accessoryRectangular: rectangular
        default:                    circular
        }
    }

    /// A weekly-consistency ring (active days / 7) wrapping today's count, so a
    /// glance carries both "today" and "this week" without extra taps.
    private var circular: some View {
        Gauge(value: Double(min(entry.weeklyActiveDays, 7)), in: 0...7) {
            Image(systemName: "figure.cooldown")
        } currentValueLabel: {
            Text("\(entry.todayCount)")
                .font(.system(.title3, design: .rounded)).monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    private var corner: some View {
        Text("\(entry.todayCount)")
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .widgetLabel(inlineText)
    }

    /// The wide slot earns a compact 7-day intensity strip (same lightness ramp as
    /// the app's heatmap) beneath the today line, plus a streak flourish.
    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.cooldown")
                .font(.system(size: 20, design: .rounded)).widgetAccentable()
            VStack(alignment: .leading, spacing: 3) {
                Text("\(entry.todayCount) eased today")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                weekStrip
                Text(rectSubtitle)
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
            }
        }
    }

    private var weekStrip: some View {
        let week = entry.weeklyCounts.count == 7 ? entry.weeklyCounts : Array(repeating: 0, count: 7)
        return HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.primary.opacity(cellOpacity(week[i])))
                    .frame(width: 8, height: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(.primary, lineWidth: i == 6 ? 1 : 0)
                    )
            }
        }
        .widgetAccentable()
    }

    /// Map a day's count to an opacity via the shared stepped heat scale. Accessory
    /// faces flatten hue, so lightness (opacity) carries the intensity.
    private func cellOpacity(_ count: Int) -> Double {
        switch StretchStore.heatLevel(count) {
        case 0:  return 0.18
        case 1:  return 0.45
        case 2:  return 0.7
        default: return 1.0
        }
    }

    private var rectSubtitle: String {
        if entry.streakDays > 1 { return "\(entry.streakDays)-day rhythm · \(inlineText.lowercased())" }
        return inlineText
    }

    private var inlineText: String {
        guard let m = entry.minutesToNext else { return "Ready to ease" }
        if m <= 0 { return "Ease up now" }
        if m < 60 { return "Next in \(m)m" }
        return "Next in \(m / 60)h"
    }
}

@main
struct StretchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StretchComplication", provider: StretchProvider()) { entry in
            StretchComplicationView(entry: entry)
        }
        .configurationDisplayName("StretchWatch")
        .description("Today's count, your week's rhythm, and time to the next stretch.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}
