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

                Section {
                    ForEach(Stretch.Region.allCases, id: \.self) { region in
                        Toggle(LocalizedStringKey(region.title), isOn: regionBinding(region))
                            .tint(Theme.ember)
                    }
                } header: {
                    Text("Focus")
                } footer: {
                    Text("Which areas to stretch. At least one stays on.")
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
                Toggle("Log to Apple Health", isOn: $settings.logToHealth)
                    .tint(Theme.ember)
            } footer: {
                Text("Records each stretch as mindful minutes in Health.")
            }

            Section {
                Button("Spike #1 data") { showDiagnostics = true }
                    .foregroundStyle(Theme.haze)
            }
        }
        .navigationTitle("Settings")
        .onChange(of: settings) { old, new in
            SettingsStore.save(new)
            Task { await TriggerEngine.settingsChanged() }
            // Ask for Health permission the moment the user opts in.
            if new.logToHealth, !old.logToHealth {
                Task { await HealthLogger.requestAuthorization() }
            }
        }
        .sheet(isPresented: $showDiagnostics) { SpikeView() }
    }

    /// Toggle for one region. Blocks turning off the last enabled area so the
    /// user can never end up with zero stretches.
    private func regionBinding(_ region: Stretch.Region) -> Binding<Bool> {
        Binding(
            get: { settings.activeRegions.contains(region) },
            set: { isOn in
                var set = settings.activeRegions
                if isOn { set.insert(region) }
                else if set.count > 1 { set.remove(region) }  // keep at least one
                settings.enabledRegions = set
            }
        )
    }

    /// Locale-aware hour label (e.g. "1 AM" in en, "오전 1시" in ko) instead of a
    /// hardcoded am/pm suffix that would read wrong in Korean.
    private func hourLabel(_ h: Int) -> String {
        let base = Calendar.current.startOfDay(for: Date())
        let date = Calendar.current.date(byAdding: .hour, value: h, to: base) ?? base
        return date.formatted(.dateTime.hour())
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
