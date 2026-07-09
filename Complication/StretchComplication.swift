import WidgetKit
import SwiftUI

/// Watch-face complication. Two jobs: (1) surface the reward — today's count —
/// where the eyes already glance, and (2) keep the app near the active face so
/// watchOS grants the background-refresh budget the suppression check needs.
struct StretchEntry: TimelineEntry {
    let date: Date
    let todayCount: Int
    let minutesToNext: Int?
}

struct StretchProvider: TimelineProvider {
    func placeholder(in context: Context) -> StretchEntry {
        StretchEntry(date: .now, todayCount: 0, minutesToNext: 40)
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
        return StretchEntry(date: .now, todayCount: s.todayCount, minutesToNext: SharedState.minutesToNextFire)
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

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -1) {
                Image(systemName: "figure.cooldown")
                    .font(.system(size: 11, design: .rounded)).widgetAccentable()
                Text("\(entry.todayCount)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }

    private var corner: some View {
        Text("\(entry.todayCount)")
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .widgetLabel(inlineText)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.cooldown")
                .font(.system(size: 20, design: .rounded)).widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text("\(entry.todayCount) eased today")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(inlineText)
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(.secondary)
            }
        }
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
        .description("Eased today and time to your next stretch.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}
