import SwiftUI

struct SettingsView: View {
    @State private var settings = SettingsStore.load()
    @State private var showDiagnostics = false

    var body: some View {
        Form {
            Section {
                Toggle("Reminders", isOn: $settings.remindersOn)
                    .tint(Theme.ember)
            }

            if settings.remindersOn {
                Section("Nudge every") {
                    Picker("Interval", selection: $settings.intervalMinutes) {
                        ForEach(StretchSettings.intervalChoices, id: \.self) { m in
                            Text("\(m) min").tag(m)
                        }
                    }
                }

                Section {
                    Toggle("Standing desk", isOn: $settings.standingDesk)
                        .tint(Theme.ember)
                } footer: {
                    Text("When on, we lean off movement detection — a standing desk looks the same as sitting to the sensors.")
                }

                Section("Quiet hours") {
                    Toggle("Silence overnight", isOn: $settings.quietEnabled)
                        .tint(Theme.ember)
                    if settings.quietEnabled {
                        Picker("From", selection: $settings.quietStartHour) {
                            ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                        }
                        Picker("Until", selection: $settings.quietEndHour) {
                            ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                        }
                    }
                }
            }

            Section {
                Button("Spike #1 data") { showDiagnostics = true }
                    .foregroundStyle(Theme.haze)
            }
        }
        .navigationTitle("Settings")
        .onChange(of: settings) { _, new in
            SettingsStore.save(new)
            Task { await TriggerEngine.settingsChanged() }
        }
        .sheet(isPresented: $showDiagnostics) { SpikeView() }
    }

    private func hourLabel(_ h: Int) -> String {
        let suffix = h < 12 ? "am" : "pm"
        let twelve = h % 12 == 0 ? 12 : h % 12
        return "\(twelve)\(suffix)"
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
