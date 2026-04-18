import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse) var allSessions: [WorkoutSession]
    @Query(sort: \PersonalRecord.date, order: .reverse) var prs: [PersonalRecord]
    @Query(sort: \BodyweightEntry.date) var bodyweightEntries: [BodyweightEntry]
    @Query var users: [AppUser]
    @Environment(\.modelContext) private var modelContext

    @State private var showingBodyweightInput = false
    @State private var newBodyweight = ""

    var sessions: [WorkoutSession] { allSessions.filter { $0.isFinished } }
    var user: AppUser? { users.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if sessions.isEmpty {
                        ContentUnavailableView("No Data Yet", systemImage: "chart.xyaxis.line",
                            description: Text("Complete workouts to see your stats"))
                    } else {
                        // Deload suggestion banner
                        if shouldSuggestDeload { deloadBanner }

                        // Bodyweight
                        bodyweightCard

                        // Volume chart
                        volumeCard

                        // Muscle group breakdown
                        muscleBreakdownCard

                        // Personal records
                        prCard
                    }
                }
                .padding()
            }
            .navigationTitle("Stats")
            .sheet(isPresented: $showingBodyweightInput) {
                bodyweightInputSheet
            }
        }
    }

    // MARK: - Deload

    var shouldSuggestDeload: Bool {
        guard let user = user, let firstSession = sessions.last else { return false }
        let weeksSinceStart = Calendar.current.dateComponents([.weekOfYear], from: firstSession.date, to: Date()).weekOfYear ?? 0
        return weeksSinceStart >= user.deloadIntervalWeeks
    }

    var deloadBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "battery.25").font(.title2).foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Deload Week Suggested").font(.headline)
                Text("You've been training hard. Consider a lighter week to recover and come back stronger.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Bodyweight

    var bodyweightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bodyweight").font(.headline)
                Spacer()
                Button { showingBodyweightInput = true } label: {
                    Label("Log", systemImage: "plus").font(.subheadline).foregroundStyle(.orange)
                }
            }

            if bodyweightEntries.count >= 2 {
                Chart(bodyweightEntries) { entry in
                    LineMark(x: .value("Date", entry.date), y: .value("kg", entry.weight))
                        .foregroundStyle(.orange)
                    PointMark(x: .value("Date", entry.date), y: .value("kg", entry.weight))
                        .foregroundStyle(.orange)
                }
                .frame(height: 140)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
            } else if let latest = bodyweightEntries.last {
                Text(String(format: "%.1f kg", latest.weight))
                    .font(.largeTitle.bold()).foregroundStyle(.orange)
                Text("Log more entries to see your trend").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No bodyweight logged yet").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    var bodyweightInputSheet: some View {
        NavigationStack {
            Form {
                Section("Log Bodyweight") {
                    TextField("Weight in kg", text: $newBodyweight)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Bodyweight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { showingBodyweightInput = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let w = Double(newBodyweight.replacingOccurrences(of: ",", with: ".")), w > 0 {
                            let entry = BodyweightEntry(weight: w)
                            if let user = user {
                                modelContext.insert(entry)
                                entry.user = user
                                user.bodyweightEntries.append(entry)
                                try? modelContext.save()
                            }
                        }
                        newBodyweight = ""
                        showingBodyweightInput = false
                    }
                    .fontWeight(.bold)
                    .disabled(newBodyweight.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Volume chart

    var tonnageData: [(date: Date, volume: Double)] {
        sessions.prefix(20).reversed().map { (date: $0.date, volume: $0.totalVolume) }
    }

    var volumeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Volume").font(.headline)
            if tonnageData.count >= 2 {
                Chart(tonnageData, id: \.date) { point in
                    BarMark(x: .value("Date", point.date, unit: .day), y: .value("Volume", point.volume))
                        .foregroundStyle(Color.orange.gradient)
                }
                .frame(height: 160)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
            } else {
                Text("Log more sessions to see your volume trend")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Muscle breakdown

    var weeklyMuscleData: [(muscle: String, sets: Int)] {
        let oneWeekAgo = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date())!
        var counts: [String: Int] = [:]
        for session in sessions where session.date >= oneWeekAgo {
            for log in session.exerciseLogs {
                let completedSets = log.setLogs.filter { $0.isCompleted && !$0.isWarmup }.count
                if completedSets > 0 { counts[log.muscleGroup, default: 0] += completedSets }
            }
        }
        return counts.map { (muscle: $0.key, sets: $0.value) }.sorted { $0.sets > $1.sets }
    }

    var muscleBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Sets by Muscle").font(.headline)
            if weeklyMuscleData.isEmpty {
                Text("No completed sets this week").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart(weeklyMuscleData, id: \.muscle) { item in
                    BarMark(x: .value("Sets", item.sets), y: .value("Muscle", item.muscle))
                        .foregroundStyle(Color.orange.gradient)
                        .annotation(position: .trailing) {
                            Text("\(item.sets)").font(.caption.bold()).foregroundStyle(.secondary)
                        }
                }
                .frame(height: CGFloat(weeklyMuscleData.count) * 36)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Personal Records

    var prCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Records").font(.headline)
            if prs.isEmpty {
                Text("No PRs yet — finish a workout to see your records").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(prs.prefix(10)) { pr in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.exerciseName).font(.subheadline.bold())
                            Text(pr.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f kg × %d", pr.weight, pr.reps))
                                .font(.subheadline.bold()).foregroundStyle(.orange)
                            Text(String(format: "~%.0f kg 1RM", pr.estimated1RM))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if pr.id != prs.prefix(10).last?.id { Divider() }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
