import SwiftUI
import SwiftData

struct ProgramsView: View {
    @Query(sort: \WorkoutProgram.createdAt) var programs: [WorkoutProgram]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAdd = false
    @State private var newName = ""
    @State private var selected: WorkoutProgram?
    @State private var exportURL: URL?
    @State private var showingExporter = false

    var body: some View {
        NavigationStack {
            Group {
                if programs.isEmpty {
                    ContentUnavailableView("No Programs", systemImage: "list.bullet.clipboard",
                        description: Text("Tap + to create a program"))
                } else {
                    List {
                        ForEach(programs) { program in
                            Button { selected = program } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            if program.isPinned { Image(systemName: "pin.fill").foregroundStyle(.orange).font(.caption) }
                                            if program.isPreset { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption) }
                                            Text(program.name).font(.headline).foregroundStyle(.primary)
                                        }
                                        Text("\(program.days.count) days").font(.caption).foregroundStyle(.secondary)
                                        if !program.programDescription.isEmpty {
                                            Text(program.programDescription).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    // Share button
                                    Button {
                                        if let url = try? ExportService.exportURL(program: program) {
                                            exportURL = url
                                            showingExporter = true
                                        }
                                    } label: {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                            .frame(width: 36, height: 36)
                                    }
                                    .buttonStyle(.plain)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: deletePrograms)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Programs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("New Program", isPresented: $showingAdd) {
                TextField("e.g. Push Pull Legs", text: $newName)
                Button("Create") {
                    let trimmed = newName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    modelContext.insert(WorkoutProgram(name: trimmed))
                    try? modelContext.save()
                    newName = ""
                }
                Button("Cancel", role: .cancel) { newName = "" }
            } message: { Text("Enter a name for your workout program") }
            .sheet(item: $selected) { ProgramEditorView(program: $0) }
            .sheet(isPresented: $showingExporter) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    func deletePrograms(at offsets: IndexSet) {
        for i in offsets { modelContext.delete(programs[i]) }
        try? modelContext.save()
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Program Editor
struct ProgramEditorView: View {
    @Bindable var program: WorkoutProgram
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddDay = false
    @State private var newDayName = ""
    @State private var selectedDay: WorkoutDay?

    var sortedDays: [WorkoutDay] { program.days.sorted { $0.order < $1.order } }

    var body: some View {
        NavigationStack {
            List {
                Section("Program Info") {
                    TextField("Program name", text: $program.name).onSubmit { try? modelContext.save() }
                    TextField("Description (optional)", text: $program.programDescription, axis: .vertical)
                        .lineLimit(2...4).onSubmit { try? modelContext.save() }
                }

                Section("Training Days") {
                    ForEach(sortedDays) { day in
                        Button { selectedDay = day } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(day.name).font(.headline).foregroundStyle(.primary)
                                    let total = day.plannedExercises.reduce(0) { $0 + $1.plannedSets }
                                    Text("\(day.plannedExercises.count) exercises · \(total) sets")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete(perform: deleteDays)
                    Button { showingAddDay = true } label: {
                        Label("Add Day", systemImage: "plus.circle.fill").foregroundStyle(.orange)
                    }
                }

                let weekly = weeklySetsPerMuscle(for: program)
                if !weekly.isEmpty {
                    Section("Weekly Volume") {
                        ForEach(weekly.keys.sorted(), id: \.self) { muscle in
                            HStack {
                                Text(muscle).font(.subheadline)
                                Spacer()
                                Text("\(weekly[muscle]!) sets/week").font(.subheadline.bold()).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(program.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { try? modelContext.save(); dismiss() }.fontWeight(.bold)
                }
            }
            .alert("New Training Day", isPresented: $showingAddDay) {
                TextField("e.g. Push, Upper, Chest/Biceps", text: $newDayName)
                Button("Add") {
                    let trimmed = newDayName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    let day = WorkoutDay(name: trimmed, order: program.days.count)
                    modelContext.insert(day)
                    day.program = program
                    program.days.append(day)
                    try? modelContext.save()
                    newDayName = ""
                }
                Button("Cancel", role: .cancel) { newDayName = "" }
            } message: { Text("Enter a name for this training day") }
            .sheet(item: $selectedDay) { DayEditorView(day: $0, program: program) }
        }
    }

    func deleteDays(at offsets: IndexSet) {
        let days = sortedDays
        for i in offsets { modelContext.delete(days[i]) }
        try? modelContext.save()
    }
}

// MARK: - Day Editor
struct DayEditorView: View {
    @Bindable var day: WorkoutDay
    let program: WorkoutProgram
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingPicker = false

    var sortedExercises: [PlannedExercise] { day.plannedExercises.sorted { $0.order < $1.order } }
    var daySets: [String: Int] { setsPerMuscle(for: day) }
    var weekSets: [String: Int] { weeklySetsPerMuscle(for: program) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Muscle group counter bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if daySets.isEmpty {
                            Text("Add exercises and set planned sets to see muscle group totals")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(daySets.keys.sorted(), id: \.self) { muscle in
                                VStack(spacing: 2) {
                                    Text(muscle).font(.caption.bold())
                                    HStack(spacing: 4) {
                                        Text("Today: \(daySets[muscle]!)").font(.caption2).foregroundStyle(.orange)
                                        Text("·").font(.caption2).foregroundStyle(.secondary)
                                        Text("Week: \(weekSets[muscle] ?? 0)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 10)
                }
                .background(Color(.secondarySystemBackground))
                Divider()

                List {
                    Section("Day Name") {
                        TextField("Day name", text: $day.name).onSubmit { try? modelContext.save() }
                    }
                    Section("Exercises") {
                        ForEach(sortedExercises) { pe in PlannedExerciseRow(pe: pe) }
                            .onDelete(perform: deleteExercises)
                            .onMove(perform: moveExercises)
                        Button { showingPicker = true } label: {
                            Label("Add Exercise", systemImage: "plus.circle.fill").foregroundStyle(.orange)
                        }
                    }
                    if sortedExercises.contains(where: { $0.plannedSets == 0 }) {
                        Section {
                            Label("Set planned sets for each exercise using the +/- buttons", systemImage: "exclamationmark.circle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle(day.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { try? modelContext.save(); dismiss() }.fontWeight(.bold)
                }
            }
            .sheet(isPresented: $showingPicker) { ExercisePickerView(day: day) }
        }
    }

    func deleteExercises(at offsets: IndexSet) {
        for i in offsets { modelContext.delete(sortedExercises[i]) }
        try? modelContext.save()
    }

    func moveExercises(from source: IndexSet, to dest: Int) {
        var exs = sortedExercises
        exs.move(fromOffsets: source, toOffset: dest)
        for (i, ex) in exs.enumerated() { ex.order = i }
        try? modelContext.save()
    }
}

// MARK: - Planned Exercise Row
struct PlannedExerciseRow: View {
    @Bindable var pe: PlannedExercise
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pe.exercise?.name ?? "Unknown").font(.headline)
                    HStack(spacing: 6) {
                        Text(pe.exercise?.muscleGroup ?? "").font(.caption).foregroundStyle(.secondary)
                        if pe.exercise?.isCompound == true {
                            Text("COMPOUND").font(.caption2.bold()).foregroundStyle(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.1), in: Capsule())
                        }
                    }
                }
                Spacer()
            }
            HStack(spacing: 20) {
                // Sets
                HStack(spacing: 10) {
                    Text("Sets:").font(.subheadline).foregroundStyle(.secondary)
                    Button { if pe.plannedSets > 0 { pe.plannedSets -= 1; try? modelContext.save() } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(pe.plannedSets > 0 ? .orange : .secondary).font(.title3)
                    }.buttonStyle(.plain)
                    Text("\(pe.plannedSets)").font(.headline.monospacedDigit()).frame(minWidth: 20)
                    Button { pe.plannedSets += 1; try? modelContext.save() } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.orange).font(.title3)
                    }.buttonStyle(.plain)
                }
                // Reps
                HStack(spacing: 10) {
                    Text("Reps:").font(.subheadline).foregroundStyle(.secondary)
                    Button { if pe.plannedReps > 0 { pe.plannedReps -= 1; try? modelContext.save() } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(pe.plannedReps > 0 ? .orange : .secondary).font(.title3)
                    }.buttonStyle(.plain)
                    Text("\(pe.plannedReps)").font(.headline.monospacedDigit()).frame(minWidth: 20)
                    Button { pe.plannedReps += 1; try? modelContext.save() } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.orange).font(.title3)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Exercise Picker
struct ExercisePickerView: View {
    let day: WorkoutDay
    @Query(sort: \Exercise.name) var exercises: [Exercise]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedMuscle = "All"

    let muscles = ["All","Chest","Back","Legs","Shoulders","Biceps","Triceps","Core"]

    var filtered: [Exercise] {
        exercises.filter { ex in
            (selectedMuscle == "All" || ex.muscleGroup == selectedMuscle) &&
            (searchText.isEmpty || ex.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    var alreadyAdded: Set<UUID> { Set(day.plannedExercises.compactMap { $0.exercise?.id }) }

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
                List(filtered) { ex in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).font(.headline)
                            HStack(spacing: 6) {
                                Text(ex.muscleGroup).font(.caption).foregroundStyle(.secondary)
                                if ex.isCompound { Text("COMPOUND").font(.caption2.bold()).foregroundStyle(.orange) }
                            }
                        }
                        Spacer()
                        if alreadyAdded.contains(ex.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !alreadyAdded.contains(ex.id) else { return }
                        let pe = PlannedExercise(order: day.plannedExercises.count, exercise: ex, plannedSets: 3, plannedReps: 10)
                        modelContext.insert(pe)
                        pe.day = day
                        day.plannedExercises.append(pe)
                        try? modelContext.save()
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Add Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.bold) }
            }
        }
    }
}
