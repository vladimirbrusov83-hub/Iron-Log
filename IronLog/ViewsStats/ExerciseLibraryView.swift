import SwiftUI
import SwiftData
import Charts

struct ExerciseLibraryView: View {
    @Query(sort: \Exercise.name) var exercises: [Exercise]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAdd = false
    @State private var searchText = ""
    @State private var selectedMuscle = "All"
    @State private var selected: Exercise?

    let muscles = ["All","Chest","Back","Legs","Shoulders","Biceps","Triceps","Core"]

    var filtered: [Exercise] {
        exercises.filter {
            (selectedMuscle == "All" || $0.muscleGroup == selectedMuscle) &&
            (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    var grouped: [String: [Exercise]] {
        selectedMuscle == "All"
            ? Dictionary(grouping: filtered) { $0.muscleGroup.isEmpty ? "Other" : $0.muscleGroup }
            : [selectedMuscle: filtered]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(muscles, id: \.self) { m in
                            Button(m) { selectedMuscle = m }
                                .font(.caption.bold())
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(selectedMuscle == m ? Color.orange : Color(.secondarySystemBackground), in: Capsule())
                                .foregroundStyle(selectedMuscle == m ? .white : .primary)
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
                .background(Color(.systemBackground))
                Divider()

                if exercises.isEmpty {
                    ContentUnavailableView("No Exercises", systemImage: "dumbbell.fill",
                        description: Text("Loading…"))
                } else {
                    List {
                        ForEach(grouped.keys.sorted(), id: \.self) { group in
                            Section(group) {
                                ForEach(grouped[group]!) { ex in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ex.name).font(.headline)
                                            if ex.isCompound {
                                                Text("COMPOUND").font(.caption2.bold()).foregroundStyle(.orange)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { selected = ex }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, prompt: "Search exercises")
                }
            }
            .navigationTitle("Exercises")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) { AddExerciseView() }
            .sheet(item: $selected) { ExerciseDetailView(exercise: $0) }
        }
    }
}

struct AddExerciseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var muscleGroup = "Chest"
    @State private var isCompound = false
    let groups = ["Chest","Back","Legs","Shoulders","Biceps","Triceps","Core","Cardio","Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise name", text: $name)
                    Picker("Muscle Group", selection: $muscleGroup) {
                        ForEach(groups, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Compound exercise", isOn: $isCompound)
                }
                if isCompound {
                    Section {
                        Label("Warm-up sets will be auto-generated for compound exercises", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        modelContext.insert(Exercise(name: trimmed, muscleGroup: muscleGroup, isCompound: isCompound))
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.bold)
                }
            }
        }
    }
}

struct ExerciseDetailView: View {
    let exercise: Exercise
    @Query(sort: \WorkoutSession.date, order: .reverse) var allSessions: [WorkoutSession]
    @Query var allPRs: [PersonalRecord]
    @Environment(\.dismiss) private var dismiss

    var history: [(date: Date, sets: [SetLog])] {
        allSessions.filter { $0.isFinished }.compactMap { s -> (Date, [SetLog])? in
            guard let log = s.exerciseLogs.first(where: { $0.exerciseID == exercise.id }),
                  !log.setLogs.isEmpty else { return nil }
            return (s.date, log.setLogs.filter { !$0.isWarmup }.sorted { $0.setNumber < $1.setNumber })
        }
    }

    var pr: PersonalRecord? { allPRs.first { $0.exerciseID == exercise.id } }

    var chartData: [(date: Date, maxWeight: Double)] {
        history.map { (date: $0.date, maxWeight: $0.sets.map { $0.weight }.max() ?? 0) }.reversed()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // PR badge
                    if let pr = pr {
                        HStack {
                            Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                            VStack(alignment: .leading) {
                                Text("Personal Record").font(.caption.bold()).foregroundStyle(.secondary)
                                Text(String(format: "%.1f kg × %d reps", pr.weight, pr.reps)).font(.headline)
                            }
                            Spacer()
                            Text(pr.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    // Progress chart
                    if chartData.count >= 2 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Max Weight Progress").font(.headline)
                            Chart(chartData, id: \.date) { point in
                                LineMark(x: .value("Date", point.date), y: .value("kg", point.maxWeight))
                                    .foregroundStyle(.orange)
                                PointMark(x: .value("Date", point.date), y: .value("kg", point.maxWeight))
                                    .foregroundStyle(.orange)
                            }
                            .frame(height: 180)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }

                    if history.isEmpty {
                        Text("No history yet. Log a workout with this exercise.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                    }

                    ForEach(history.prefix(8), id: \.date) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.date, style: .date).font(.subheadline.bold())
                            ForEach(entry.sets) { set in
                                HStack {
                                    Text("Set \(set.setNumber)").font(.caption).foregroundStyle(.secondary).frame(width: 40)
                                    Text(String(format: "%.1f kg × %d", set.weight, set.reps))
                                    Spacer()
                                    if let rir = set.effectiveRIR { Text("RIR \(rir)").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.bold) } }
        }
    }
}
