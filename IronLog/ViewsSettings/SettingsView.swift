import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query var users: [AppUser]
    @Environment(\.modelContext) private var modelContext

    var user: AppUser {
        if let existing = users.first { return existing }
        let u = AppUser()
        modelContext.insert(u)
        try? modelContext.save()
        return u
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable RIR / RPE Tracking", isOn: Binding(
                        get: { user.enableRIRRPE },
                        set: { user.enableRIRRPE = $0; try? modelContext.save() }
                    ))
                } header: {
                    Text("Training Metrics")
                } footer: {
                    Text("When enabled, each set shows fields for Reps in Reserve (RIR 0–4) and RPE (6–10). These are used to improve the AI progressive overload suggestion.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Default Rest Duration")
                            Spacer()
                            Text("\(user.defaultRestSeconds)s")
                                .foregroundStyle(.orange).fontWeight(.bold)
                        }
                        Slider(value: Binding(
                            get: { Double(user.defaultRestSeconds) },
                            set: { user.defaultRestSeconds = Int($0); try? modelContext.save() }
                        ), in: 30...300, step: 15).tint(.orange)
                        HStack {
                            Text("30s").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("5 min").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Rest Timer")
                } footer: {
                    Text("Default rest time shown when you log a set. Adjustable per set during a workout.")
                }

                Section {
                    Picker("Weight Unit", selection: Binding(
                        get: { user.weightUnit },
                        set: { user.weightUnit = $0; try? modelContext.save() }
                    )) {
                        Text("kg").tag("kg")
                        Text("lb").tag("lb")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Units")
                } footer: {
                    Text("Note: All weights are stored in kg internally. Display conversion coming in a future update.")
                }

                Section {
                    HStack {
                        Text("Deload Suggestion Interval")
                        Spacer()
                        Text("Every \(user.deloadIntervalWeeks) weeks")
                            .foregroundStyle(.orange).fontWeight(.bold)
                    }
                    Slider(value: Binding(
                        get: { Double(user.deloadIntervalWeeks) },
                        set: { user.deloadIntervalWeeks = Int($0); try? modelContext.save() }
                    ), in: 4...12, step: 1).tint(.orange)
                    HStack {
                        Text("4 weeks").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("12 weeks").font(.caption2).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Recovery")
                } footer: {
                    Text("A deload suggestion will appear in the Stats tab after this many weeks of training.")
                }

                Section("About") {
                    HStack { Text("App"); Spacer(); Text("IronLog").foregroundStyle(.secondary) }
                    HStack { Text("Version"); Spacer(); Text("2.0").foregroundStyle(.secondary) }
                    HStack { Text("Architecture"); Spacer(); Text("SwiftUI + SwiftData").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
