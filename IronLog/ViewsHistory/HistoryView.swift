import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse) var allSessions: [WorkoutSession]
    @State private var selected: WorkoutSession?

    var sessions: [WorkoutSession] { allSessions.filter { $0.isFinished } }

    var grouped: [String: [WorkoutSession]] {
        let fmt = DateFormatter(); fmt.dateFormat = "MMMM yyyy"
        return Dictionary(grouping: sessions) { fmt.string(from: $0.date) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView("No Workouts Yet", systemImage: "calendar.badge.plus",
                        description: Text("Finish a workout to see it here"))
                } else {
                    List {
                        ForEach(grouped.keys.sorted(by: >), id: \.self) { month in
                            Section(month) {
                                ForEach(grouped[month]!) { session in
                                    SessionRow(session: session)
                                        .onTapGesture { selected = session }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .sheet(item: $selected) { SessionDetailView(session: $0) }
        }
    }
}

struct SessionRow: View {
    let session: WorkoutSession
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.dayName).font(.headline)
                HStack(spacing: 12) {
                    Label("\(session.exerciseLogs.count) exercises", systemImage: "dumbbell")
                    Label(session.formattedDuration, systemImage: "clock")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(session.date, style: .date).font(.caption).foregroundStyle(.secondary)
                if session.totalVolume > 0 {
                    Text("\(Int(session.totalVolume)) kg vol").font(.caption.bold()).foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SessionDetailView: View {
    let session: WorkoutSession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Overview") {
                    HStack { Label("Date", systemImage: "calendar"); Spacer(); Text(session.date, style: .date).foregroundStyle(.secondary) }
                    HStack { Label("Duration", systemImage: "clock"); Spacer(); Text(session.formattedDuration).foregroundStyle(.secondary) }
                    if session.totalVolume > 0 {
                        HStack { Label("Volume", systemImage: "scalemass"); Spacer(); Text("\(Int(session.totalVolume)) kg").foregroundStyle(.secondary) }
                    }
                    if !session.notes.isEmpty {
                        Text(session.notes).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section("Exercises") {
                    ForEach(session.exerciseLogs.sorted { $0.order < $1.order }) { log in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(log.exerciseName).font(.headline)
                                Spacer()
                                Text(log.muscleGroup).font(.caption).foregroundStyle(.orange)
                            }
                            ForEach(log.setLogs.filter { !$0.isWarmup }.sorted { $0.setNumber < $1.setNumber }) { set in
                                HStack {
                                    Text("Set \(set.setNumber)").font(.caption).foregroundStyle(.secondary).frame(width: 45)
                                    Text(String(format: "%.1f kg × %d", set.weight, set.reps))
                                    Spacer()
                                    if let rir = set.effectiveRIR {
                                        Text("RIR \(rir)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if !log.notes.isEmpty {
                                Text(log.notes).font(.caption).foregroundStyle(.secondary).italic()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(session.dayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.bold) } }
        }
    }
}
