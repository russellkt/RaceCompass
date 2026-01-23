import SwiftUI

struct SettingsView: View {
    @ObservedObject var themeManager: ThemeManager
    @ObservedObject var waypointStore: WaypointStore
    @Binding var isPresented: Bool

    // Direct access to UserDefaults for HapticManager
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    var body: some View {
        NavigationView {
            Form {
                // THEME SECTION
                Section(header: Text("DISPLAY")) {
                    Picker("Theme", selection: $themeManager.selectedThemeName) {
                        Text("Day").tag("Day")
                        Text("Night").tag("Night")
                        Text("High Contrast").tag("High Contrast")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: themeManager.selectedThemeName) { _ in
                        themeManager.updateTheme()
                    }
                }

                // START COACHING SECTION
                Section(header: Text("START COACHING PARAMS"), footer: Text("Adjust these values based on your boat's performance.")) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Target Speed")
                            Spacer()
                            Text(String(format: "%.1f kts", waypointStore.accelConfig.targetSpeed))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $waypointStore.accelConfig.targetSpeed, in: 2...15, step: 0.1)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Time to Accelerate")
                            Spacer()
                            Text(String(format: "%.0f sec", waypointStore.accelConfig.timeToAccelerate))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $waypointStore.accelConfig.timeToAccelerate, in: 5...60, step: 1)
                    }
                    .padding(.vertical, 4)

                    Stepper(value: $waypointStore.accelConfig.buffer, in: 0...15) {
                        HStack {
                            Text("Safety Buffer")
                            Spacer()
                            Text(String(format: "%.0f sec", waypointStore.accelConfig.buffer))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // AUDIO/HAPTICS
                Section(header: Text("FEEDBACK")) {
                    Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                        .onChange(of: hapticsEnabled) { newValue in
                            HapticManager.shared.isEnabled = newValue
                        }
                }

                Section(footer: Text("RaceCompass v1.1")) {
                    EmptyView()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Persist changes
                        waypointStore.updateAccelConfig(waypointStore.accelConfig)
                        isPresented = false
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}
