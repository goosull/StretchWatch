import SwiftUI
import WatchKit

/// The signature moment. Ready beat → breathing countdown arc with a movement
/// glyph you mirror → auto-complete with a bloom. Completion is automatic (the
/// countdown finishing); a tap is only ever needed to *skip*. This kills the
/// false-skip failure mode where the wrist drops mid-stretch (per the review).
struct StretchSessionView: View {
    let stretch: Stretch
    var onComplete: () -> Void = {}
    var onSkip: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .ready(3)
    @State private var remaining: Double = 0
    @State private var breath = false
    @State private var bloom = false
    @State private var outcomeSent = false

    private enum Phase: Equatable { case ready(Int), active, done }

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            bloomLayer

            switch phase {
            case .ready(let n):  readyView(n)
            case .active:        activeView
            case .done:          doneView
            }
        }
        .onAppear(perform: start)
        // Dismissing via the system close (X) or crown counts as a skip, so the
        // outcome is always recorded and the schedule always re-arms.
        .onDisappear { if !outcomeSent { outcomeSent = true; onSkip() } }
    }

    // MARK: - Phases

    private func readyView(_ n: Int) -> some View {
        VStack(spacing: 6) {
            Text("Ready")
                .font(Theme.display(15, .regular)).foregroundStyle(Theme.haze)
            Text("\(n)")
                .font(Theme.display(44, .semibold)).foregroundStyle(Theme.paper)
                .contentTransition(.numericText())
                .monospacedDigit()
        }
        .transition(.opacity)
    }

    private var activeView: some View {
        VStack(spacing: 8) {
            Text(stretch.title)
                .font(Theme.display(18, .semibold)).foregroundStyle(Theme.paper)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7).lineLimit(2)

            ZStack {
                // Breathing countdown arc — depletes like an exhale.
                Circle()
                    .stroke(Theme.ink2, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0, remaining / Double(stretch.seconds)))
                    .stroke(Theme.emberGradient,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                MovementGlyph(motion: stretch.motion, symbol: stretch.symbol,
                              breathing: breath && !reduceMotion)
            }
            .frame(width: 96, height: 96)
            .scaleEffect(breath && !reduceMotion ? 1.03 : 1.0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(stretch.title), hold \(stretch.seconds) seconds")

            Button(action: skip) {
                Text("Skip").font(Theme.display(13, .regular))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.haze)
            .accessibilityLabel("Skip this stretch")
        }
        .padding(.horizontal, 6)
        .transition(.opacity)
    }

    private var doneView: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(Theme.display(30, .bold)).foregroundStyle(Theme.paper)
                .scaleEffect(bloom ? 1 : 0.5).opacity(bloom ? 1 : 0)
            Text(rewardLine)
                .font(Theme.display(16, .semibold)).foregroundStyle(Theme.paper)
        }
        .transition(.opacity)
    }

    private var bloomLayer: some View {
        RadialGradient(colors: [Theme.ember.opacity(0.55), .clear],
                       center: .center, startRadius: 0,
                       endRadius: bloom ? 160 : 0)
            .ignoresSafeArea()
            .opacity(bloom ? 1 : 0)
            .allowsHitTesting(false)
    }

    // MARK: - Flow

    private func start() {
        remaining = Double(stretch.seconds)
        WKInterfaceDevice.current().play(.start)
        withAnimation { breath = true }
        // Dev-only: jump near the end to screenshot the reward/done view.
        if CommandLine.arguments.contains("-previewDone") {
            phase = .active; remaining = 0.4; tickDown(); return
        }
        runReady(from: 3)
    }

    private func runReady(from n: Int) {
        guard n > 0 else {
            withAnimation(.easeInOut) { phase = .active }
            WKInterfaceDevice.current().play(.click)
            tickDown()
            return
        }
        withAnimation(.easeInOut) { phase = .ready(n) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { runReady(from: n - 1) }
    }

    private func tickDown() {
        guard phase == .active else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard phase == .active else { return }
            remaining -= 0.05
            if remaining <= 0 { finish() } else { tickDown() }
        }
    }

    private func finish() {
        outcomeSent = true
        WKInterfaceDevice.current().play(.success)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            phase = .done; bloom = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { onComplete() }
    }

    private func skip() {
        outcomeSent = true
        WKInterfaceDevice.current().play(.click)
        onSkip()
    }

    private var rewardLine: String {
        ["Nice.", "That's one.", "Your neck thanks you.", "Well eased."]
            .randomElement() ?? "Nice."
    }
}

/// Movement cue: a dim body-part symbol in the center with a bright ember
/// directional arrow that animates the way you should move, so you can mirror
/// it without reading. Circular motions rotate; linear motions slide.
private struct MovementGlyph: View {
    let motion: Stretch.Motion
    let symbol: String
    let breathing: Bool
    @State private var t: CGFloat = 0

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.haze.opacity(0.45))
            cue
        }
        .onAppear {
            guard breathing else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { t = 1 }
        }
    }

    @ViewBuilder private var cue: some View {
        switch motion {
        case .tiltRight, .turnRight, .rollBack:
            arrow("arrow.right").offset(x: 16 + 8 * t)
        case .tiltLeft, .turnLeft:
            arrow("arrow.left").offset(x: -16 - 8 * t)
        case .reachUp, .lookUp:
            arrow("arrow.up").offset(y: -16 - 8 * t)
        case .lookDown:
            arrow("arrow.down").offset(y: 16 + 8 * t)
        case .shrug:
            arrow("arrow.up").offset(y: -14 + 10 * t)   // lift then drop
        case .openChest:
            HStack(spacing: 20 + 10 * t) {
                arrow("arrow.left"); arrow("arrow.right")
            }
        case .wristCircle:
            arrow("arrow.clockwise").rotationEffect(.degrees(40 * t))
        }
    }

    private func arrow(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.ember)
    }
}

#Preview {
    StretchSessionView(stretch: StretchLibrary.all[0])
}
