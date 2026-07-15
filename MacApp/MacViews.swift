import AppKit
import SwiftUI

struct MacMenuBarView: View {
    @ObservedObject var coordinator: MacSessionCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            status
            metrics
            actions
        }
        .padding(20)
        .frame(width: 320, height: 240)
        .background(Theme.ink)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.seated.side")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ember)
            VStack(alignment: .leading, spacing: 1) {
                Text("StretchWatch")
                    .font(Theme.display(18, .semibold))
                    .foregroundStyle(Theme.paper)
                Text(String(localized: "A gentle computer-session coach"))
                    .font(Theme.display(11, .regular))
                    .foregroundStyle(Theme.haze)
            }
            Spacer()
        }
    }

    @ViewBuilder private var status: some View {
        switch coordinator.state.phase {
        case .dormant:
            statusBlock(title: "Ready for a pause", detail: "A reminder arrives after 40 minutes of an active computer session.")
        case .permissionDenied:
            statusBlock(title: "Notification permission is off", detail: "Open Notification Settings to let StretchWatch remind you.")
        case .active, .manualActive:
            if let date = coordinator.state.dueAt {
                statusBlock(title: "Next reset", detail: Text(date, style: .relative))
            } else {
                statusBlock(title: "Session in progress", detail: "The next reset is being prepared.")
            }
        case .snoozed:
            statusBlock(title: "Snoozed for 10 minutes", detail: "Finish what you are doing, then take a small reset.")
        case .due:
            statusBlock(title: "Time to ease up", detail: "Ease your neck right for 12 seconds.")
        case .presenting:
            statusBlock(title: "Stretching now", detail: "Breathe briefly and move gently.")
        case .retryQuiet:
            statusBlock(title: "A quiet hour", detail: "The next computer session is being prepared.")
        case .cooldown:
            statusBlock(title: "Well eased.", detail: "The next computer session is being prepared.")
        case .pausedToday:
            statusBlock(title: "Paused today", detail: "StretchWatch will be quiet until tomorrow.")
        }
    }

    private var metrics: some View {
        HStack {
            Label(String(format: String(localized: "Today: %lld"), Int64(coordinator.dashboardMetrics.completedToday)), systemImage: "sun.max")
            Spacer()
            Text(permissionLabel)
                .font(Theme.display(11, .regular))
                .foregroundStyle(coordinator.authorization == .denied ? Theme.ember2 : Theme.haze)
        }
        .font(Theme.display(12, .regular))
        .foregroundStyle(Theme.haze)
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 10) {
            if coordinator.state.phase == .permissionDenied || coordinator.authorization == .notDetermined {
                Button("Enable reminders") {
                    Task { await coordinator.enableReminders() }
                }
                .buttonStyle(MacEmberButtonStyle())
            } else if coordinator.state.phase == .dormant {
                Button("Start a session") {
                    Task { await coordinator.startManualSession() }
                }
                .buttonStyle(MacEmberButtonStyle())
            } else if coordinator.state.phase.isSession {
                Button("Pause today") {
                    Task { await coordinator.pauseToday() }
                }
                .buttonStyle(MacQuietButtonStyle())
            }

            if coordinator.authorization == .denied {
                Button("Open Notification Settings") {
                    MacSettingsOpener.openNotifications()
                }
                .buttonStyle(MacQuietButtonStyle())
            }
        }
    }

    private var permissionLabel: String {
        switch coordinator.authorization {
        case .authorized, .provisional, .ephemeral: return String(localized: "Notifications on")
        case .denied: return String(localized: "Notifications off")
        case .notDetermined: return String(localized: "Notifications not set up")
        case .unknown: return String(localized: "Checking notifications")
        }
    }

    private func statusBlock(title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        statusBlock(title: title, detail: Text(detail))
    }

    private func statusBlock(title: LocalizedStringKey, detail: Text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.display(16, .semibold))
                .foregroundStyle(Theme.paper)
            detail
                .font(Theme.display(12, .regular))
                .foregroundStyle(Theme.haze)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MacEmberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.display(12, .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Theme.emberGradient, in: Capsule())
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct MacQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.display(12, .regular))
            .foregroundStyle(Theme.haze)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.ink2, in: Capsule())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

@MainActor
final class MacPanelController {
    private var panel: NSPanel?

    func present(stretch: Stretch, snapshot: StretchSnapshot, coordinator: MacSessionCoordinator) {
        dismiss()

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView:
            StretchPanelView(stretch: stretch,
                             snapshotBefore: snapshot,
                             onComplete: { [weak self] in
                                 Task { @MainActor in
                                     await coordinator.completeCurrent()
                                     self?.dismiss()
                                 }
                             },
                             onSkip: { [weak self] in
                                 Task { @MainActor in
                                     await coordinator.skipCurrent()
                                     self?.dismiss()
                                 }
                             }))
        self.panel = panel
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func position(_ panel: NSPanel) {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(x: visible.midX - panel.frame.width / 2,
                             y: visible.midY - panel.frame.height / 2)
        panel.setFrameOrigin(origin)
    }
}

struct StretchPanelView: View {
    let stretch: Stretch
    let snapshotBefore: StretchSnapshot
    let onComplete: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: PanelPhase = .ready(3)
    @State private var remaining: Double = 12
    @State private var breathing = false
    @State private var bloom = false
    @State private var outcomeSent = false

    private enum PanelPhase: Equatable { case ready(Int), active, done }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.ink)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Theme.ink2, lineWidth: 1))
            bloomLayer
            content
        }
        .frame(width: 360, height: 260)
        .onExitCommand(perform: skip)
        .task { await runSession() }
        .onDisappear {
            if !outcomeSent {
                outcomeSent = true
                onSkip()
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .ready(let count):
            VStack(spacing: 8) {
                Text("Ready")
                    .font(Theme.display(15, .regular))
                    .foregroundStyle(Theme.haze)
                Text("\(count)")
                    .font(Theme.display(52, .semibold))
                    .foregroundStyle(Theme.paper)
                    .monospacedDigit()
            }
        case .active:
            VStack(spacing: 10) {
                Text(LocalizedStringKey(stretch.title))
                    .font(Theme.display(20, .semibold))
                    .foregroundStyle(Theme.paper)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .lineLimit(2)
                ZStack {
                    Circle().stroke(Theme.ink2, lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: max(0, remaining / Double(stretch.seconds)))
                        .stroke(Theme.emberGradient,
                                style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    MacMovementGlyph(motion: stretch.motion,
                                     symbol: stretch.symbol,
                                     breathing: breathing && !reduceMotion)
                }
                .frame(width: 104, height: 104)
                .scaleEffect(breathing && !reduceMotion ? 1.035 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(NSLocalizedString(stretch.title, comment: "stretch instruction")), \(Int(ceil(remaining))) seconds")
                Text("Stop if it hurts.")
                    .font(Theme.display(12, .regular))
                    .foregroundStyle(Theme.haze)
                Button("Skip", action: skip)
                    .buttonStyle(.plain)
                    .font(Theme.display(12, .regular))
                    .foregroundStyle(Theme.haze)
                    .accessibilityLabel(NSLocalizedString("Skip this stretch", comment: "skip accessibility label"))
            }
            .padding(.horizontal, 28)
        case .done:
            VStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(Theme.display(34, .bold))
                    .foregroundStyle(Theme.paper)
                    .scaleEffect(bloom ? 1 : 0.5)
                    .opacity(bloom ? 1 : 0)
                Text("Well eased.")
                    .font(Theme.display(20, .semibold))
                    .foregroundStyle(Theme.paper)
            }
        }
    }

    private var bloomLayer: some View {
        RadialGradient(colors: [Theme.ember.opacity(0.55), .clear],
                       center: .center,
                       startRadius: 0,
                       endRadius: bloom ? 180 : 0)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .allowsHitTesting(false)
    }

    private func runSession() async {
        do {
            for count in stride(from: 3, through: 1, by: -1) {
                phase = .ready(count)
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            phase = .active
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }

            let start = Date()
            while remaining > 0 {
                try await Task.sleep(nanoseconds: 50_000_000)
                remaining = max(0, Double(stretch.seconds) - Date().timeIntervalSince(start))
            }
            outcomeSent = true
            phase = .done
            withAnimation(.easeOut(duration: 0.45)) { bloom = true }
            try await Task.sleep(nanoseconds: 1_300_000_000)
            onComplete()
        } catch {
            // Cancellation means the panel is closing; onDisappear records Skip.
        }
    }

    private func skip() {
        guard !outcomeSent else { return }
        outcomeSent = true
        onSkip()
    }
}

private struct MacMovementGlyph: View {
    let motion: Stretch.Motion
    let symbol: String
    let breathing: Bool
    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.haze.opacity(0.42))
            cue
        }
        .onAppear {
            guard breathing else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                offset = 1
            }
        }
    }

    @ViewBuilder private var cue: some View {
        switch motion {
        case .tiltRight, .turnRight, .rollBack:
            arrow("arrow.right").offset(x: 16 + 8 * offset)
        case .tiltLeft, .turnLeft:
            arrow("arrow.left").offset(x: -16 - 8 * offset)
        case .reachUp, .lookUp, .shrug:
            arrow("arrow.up").offset(y: -16 - 8 * offset)
        case .lookDown:
            arrow("arrow.down").offset(y: 16 + 8 * offset)
        case .openChest:
            HStack(spacing: 20 + 10 * offset) {
                arrow("arrow.left")
                arrow("arrow.right")
            }
        case .wristCircle:
            arrow("arrow.clockwise").rotationEffect(.degrees(40 * offset))
        }
    }

    private func arrow(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.ember)
    }
}

enum MacSettingsOpener {
    static func openNotifications() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
