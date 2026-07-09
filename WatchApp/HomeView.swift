import SwiftUI
import UserNotifications

/// Calm home. Leads with the one cliff-free number that matters — eased today —
/// with time-to-next quiet beneath it. One ember highlight, everything else ink/haze.
/// Gates on notification permission so first-run and denied are real, designed states.
struct HomeView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var snapshot = StretchSnapshot()
    @State private var minutesToNext: Int?
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack { rootContent }
            .fullScreenCover(item: $router.activeStretch) { stretch in
                StretchSessionView(stretch: stretch,
                                   snapshotBefore: snapshot,
                                   onComplete: { router.complete() },
                                   onSkip: { router.skip() })
            }
    }

    private var rootContent: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            ZStack {
                Theme.ink.ignoresSafeArea()
                switch authStatus {
                case .notDetermined: onboarding
                case .denied:        denied
                default:             home
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: {
                        Image(systemName: "gearshape").foregroundStyle(Theme.haze)
                    }
                }
            }
            .onAppear {
                refresh()
                if CommandLine.arguments.contains("-previewHome") {
                    authStatus = .authorized
                    // Seed a sample so the week strip has intensity to show.
                    snapshot = StretchSnapshot(
                        todayCount: 3, streakDays: 4, weeklyActiveDays: 5,
                        weeklyCounts: [0, 2, 1, 3, 0, 1, 3],
                        lastCompleted: Date(), updatedAt: Date())
                }
                // Dev-only: `-previewSession <moveId>` opens a stretch for screenshots.
                if let i = CommandLine.arguments.firstIndex(of: "-previewSession") {
                    let moveId = CommandLine.arguments[safe: i + 1] ?? "sh-roll"
                    if let m = StretchLibrary.all.first(where: { $0.id == moveId }) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { router.activeStretch = m }
                    }
                }
            }
            .onChange(of: router.activeStretch) { _, new in if new == nil { refresh() } }
        }
    }

    // MARK: - Home (authorized)

    private var home: some View {
        VStack(spacing: 10) {
            Text("STRETCHWATCH")
                .font(Theme.display(10, .medium)).tracking(1.5)
                .foregroundStyle(Theme.haze)

            VStack(spacing: 0) {
                Text("\(snapshot.todayCount)")
                    .font(Theme.display(46, .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.ember)
                    .contentTransition(.numericText())
                Text("eased today")
                    .font(Theme.display(12, .regular)).foregroundStyle(Theme.haze)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(snapshot.todayCount) eased today")

            Text(nextLine)
                .font(Theme.display(12, .regular)).foregroundStyle(Theme.haze)

            Button(action: { router.startNow() }) {
                Text("Stretch now")
                    .font(Theme.display(15, .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .tint(Theme.ember)

            WatchWeekStrip(counts: snapshot.weeklyCounts)

            if snapshot.streakDays > 1 {
                Text("\(snapshot.streakDays)-day rhythm")
                    .font(Theme.display(11, .regular)).foregroundStyle(Theme.calm)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - First run

    private var onboarding: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "figure.cooldown")
                    .font(.system(size: 30, design: .rounded)).foregroundStyle(Theme.ember)
                    .padding(.top, 2)
                Text("Ease up, seated")
                    .font(Theme.display(17, .semibold)).foregroundStyle(Theme.paper)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A gentle nudge to stretch when you've sat a while. No standing.")
                    .font(Theme.display(11, .regular)).foregroundStyle(Theme.haze)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: enable) {
                    Text("Turn on reminders")
                        .font(Theme.display(14, .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                }
                .tint(Theme.ember).padding(.top, 2)
                Button("Just stretch now") { router.startNow() }
                    .font(Theme.display(11, .regular)).buttonStyle(.plain)
                    .foregroundStyle(Theme.haze)
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Denied

    private var denied: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 28, design: .rounded)).foregroundStyle(Theme.haze)
            Text("Reminders are off")
                .font(Theme.display(15, .semibold)).foregroundStyle(Theme.paper)
            Text("Turn them on in the Watch Settings › Notifications › StretchWatch.")
                .font(Theme.display(11, .regular)).foregroundStyle(Theme.haze)
                .multilineTextAlignment(.center)
            Button(action: { router.startNow() }) {
                Text("Stretch now").font(Theme.display(14, .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 3)
            }
            .tint(Theme.ember)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Logic

    private var nextLine: String {
        guard let m = minutesToNext else { return "no reminder set" }
        if m <= 0 { return "any moment now" }
        if m < 60 { return "next in \(m) min" }
        return "next in \(m / 60)h \(m % 60)m"
    }

    private func enable() {
        Task {
            _ = await TriggerEngine.enableReminders()
            await reloadAuth()
        }
    }

    private func refresh() {
        // In screenshot preview the seeded sample owns the snapshot; don't clobber it.
        if CommandLine.arguments.contains("-previewHome") { return }
        snapshot = TriggerEngine.loadSnapshot()
        minutesToNext = TriggerEngine.minutesToNextFire
        Task {
            await TriggerEngine.refreshSnapshot()
            let fresh = TriggerEngine.loadSnapshot()
            await MainActor.run {
                snapshot = fresh
                minutesToNext = TriggerEngine.minutesToNextFire
            }
            await reloadAuth()
        }
    }

    private func reloadAuth() async {
        if CommandLine.arguments.contains("-previewHome") { return }
        let status = await TriggerEngine.authStatus()
        await MainActor.run { authStatus = status }
    }
}

/// A compact 7-day intensity strip for the watch home — the same single-hue ember
/// ramp as the iOS heatmap, shrunk to fit the wrist. No weekday labels (too cramped);
/// today gets a ring, and one VoiceOver label summarizes the week so the meaning
/// never rides on color alone. A pre-heatmap snapshot decodes empty → all-dim.
private struct WatchWeekStrip: View {
    let counts: [Int]

    private var week: [Int] { counts.count == 7 ? counts : Array(repeating: 0, count: 7) }

    private func fill(_ count: Int) -> Color {
        switch StretchStore.heatLevel(count) {
        case 0:  return Theme.ink2
        case 1:  return Theme.ember.opacity(0.35)
        case 2:  return Theme.ember.opacity(0.6)
        default: return Theme.ember
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(fill(week[i]))
                    .frame(width: 13, height: 13)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Theme.ember, lineWidth: i == 6 ? 1.2 : 0)
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(week.filter { $0 > 0 }.count) of 7 days, \(week.reduce(0, +)) stretches")
    }
}

#Preview {
    HomeView().environmentObject(AppRouter.shared)
}
