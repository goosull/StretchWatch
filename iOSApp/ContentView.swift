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
                if snap.streakDays > 1 { streak }
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

    private var weekStrip: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { i in
                    Circle()
                        .fill(i < snap.weeklyActiveDays ? Theme.ember : Theme.ink2)
                        .frame(width: 14, height: 14)
                }
            }
            Text("\(snap.weeklyActiveDays) of 7 days this week")
                .font(Theme.display(13, .regular)).foregroundStyle(Theme.haze)
        }
    }

    private var streak: some View {
        Text("\(snap.streakDays)-day rhythm")
            .font(Theme.display(14, .medium)).foregroundStyle(Theme.calm)
    }

    private var footer: some View {
        Text("Do your stretches on the watch.\nThis is just the mirror.")
            .font(Theme.display(12, .regular)).foregroundStyle(Theme.haze.opacity(0.7))
            .multilineTextAlignment(.center)
            .padding(.bottom, 16)
    }
}

#Preview {
    ContentView().environmentObject(PhoneSync.shared)
}
