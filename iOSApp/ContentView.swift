import SwiftUI

/// Reflection surface. Leads with cliff-free numbers — eased today and this
/// week's consistency — so a missed day never reads as failure. Streak is quiet
/// flavor beneath. All data is a read-only cache of the watch's snapshot.
struct ContentView: View {
    @EnvironmentObject private var sync: PhoneSync

    private var snap: StretchSnapshot { sync.snapshot }

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            VStack(spacing: 28) {
                header
                todayHero
                weekStrip
                rhythm
                Spacer()
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "figure.cooldown").foregroundStyle(Theme.ember)
            Text("StretchWatch")
                .font(Theme.display(20, .semibold)).foregroundStyle(Theme.paper)
            Spacer()
        }
    }

    private var todayHero: some View {
        VStack(spacing: 2) {
            Text("\(snap.todayCount)")
                .font(Theme.display(72, .bold)).monospacedDigit()
                .foregroundStyle(Theme.ember)
                .contentTransition(.numericText())
            Text("eased today")
                .font(Theme.display(15, .regular)).foregroundStyle(Theme.haze)
        }
    }

    /// Trailing 7 days, oldest → today. A pre-heatmap snapshot decodes an empty
    /// array; treat that as all-zero rather than crashing on the index.
    private var weeklyCounts: [Int] {
        snap.weeklyCounts.count == 7 ? snap.weeklyCounts : Array(repeating: 0, count: 7)
    }

    private var weekStrip: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { i in
                    HeatCell(count: weeklyCounts[i],
                             weekday: weekdayInitial(daysAgo: 6 - i),
                             isToday: i == 6)
                }
                // (weekday labels are anchored to the snapshot's own reference
                // date, not wall-clock, so labels never drift from the counts.)
            }
            Text("\(weeklyCounts.filter { $0 > 0 }.count) of 7 days this week")
                .font(Theme.display(13, .regular)).foregroundStyle(Theme.haze)
        }
    }

    /// Narrow weekday letter (M/T/W…) for a day `daysAgo` before the snapshot's
    /// reference date. Anchored to `snap.updatedAt` (the same `now` the counts
    /// were computed against) so labels can't drift from the data across midnight.
    private func weekdayInitial(daysAgo: Int) -> String {
        let anchor = snap.updatedAt
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: anchor) ?? anchor
        let f = DateFormatter()
        f.dateFormat = "EEEEE"  // narrow single-letter weekday, locale-aware
        return f.string(from: day)
    }

    /// Current rhythm, with your all-time best beneath it when the record beats
    /// today's run — a quiet thing to reach back toward, never a scold.
    @ViewBuilder private var rhythm: some View {
        VStack(spacing: 2) {
            if snap.streakDays > 1 {
                Text("\(snap.streakDays)-day rhythm")
                    .font(Theme.display(14, .medium)).foregroundStyle(Theme.calm)
            }
            if snap.bestStreakDays > 1, snap.bestStreakDays > snap.streakDays {
                Text("best: \(snap.bestStreakDays) days")
                    .font(Theme.display(11, .regular)).foregroundStyle(Theme.haze)
            }
        }
    }

    private var footer: some View {
        Text("Do your stretches on the watch.\nThis is just the mirror.")
            .font(Theme.display(12, .regular)).foregroundStyle(Theme.haze.opacity(0.7))
            .multilineTextAlignment(.center)
            .padding(.bottom, 16)
    }
}

/// One day in the weekly heatmap. A single ember hue at a stepped opacity encodes
/// intensity (accessible: lightness is preserved across color-vision deficiency),
/// with a today ring and a VoiceOver label carrying the count so the meaning never
/// rides on color alone. An empty day is a calm dim cell, never an alarm.
private struct HeatCell: View {
    let count: Int
    let weekday: String
    let isToday: Bool

    private var fill: Color {
        switch StretchStore.heatLevel(count) {
        case 0:  return Theme.ink2
        case 1:  return Theme.ember.opacity(0.35)
        case 2:  return Theme.ember.opacity(0.6)
        default: return Theme.ember
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(fill)
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Theme.ember, lineWidth: isToday ? 1.5 : 0)
                )
            Text(weekday)
                .font(Theme.display(10, isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? Theme.paper : Theme.haze.opacity(0.7))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isToday ? "Today" : weekday), \(count) \(count == 1 ? "stretch" : "stretches")")
    }
}

#Preview {
    ContentView().environmentObject(PhoneSync.shared)
}
