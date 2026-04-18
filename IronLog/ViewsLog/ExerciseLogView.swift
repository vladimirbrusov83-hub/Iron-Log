import SwiftUI
import SwiftData

struct ExerciseLogView: View {
    @Bindable var exerciseLog: ExerciseLog
    let previousLog: ExerciseLog?
    let loggingVM: LoggingViewModel
    let enableRIRRPE: Bool
    let defaultRestSeconds: Int

    @Environment(\.modelContext) private var modelContext
    @State private var setToEdit: SetLog?
    @State private var showSetEditor = false

    var prevSets: [SetLog] {
        (previousLog?.setLogs ?? []).filter { !$0.isWarmup }.sorted { $0.setNumber < $1.setNumber }
    }

    var currentSets: [SetLog] {
        exerciseLog.setLogs.filter { !$0.isWarmup }.sorted { $0.setNumber < $1.setNumber }
    }

    var warmupSets: [SetLog] {
        exerciseLog.setLogs.filter { $0.isWarmup }.sorted { $0.setNumber < $1.setNumber }
    }

    var suggestion: ProgressionEngine.Suggestion? {
        ProgressionEngine.suggest(previousLog: previousLog, plannedReps: exerciseLog.plannedReps)
    }

    // How many working set rows to show
    var rowCount: Int {
        let base = max(max(exerciseLog.plannedSets, prevSets.count), max(currentSets.count, 1))
        return min(base, 15)
    }

    var isFirstTimeExercise: Bool {
        previousLog == nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // Exercise header
                exerciseHeader
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                // Rest timer banner
                if loggingVM.isResting {
                    RestTimerBanner(
                        secondsLeft: $loggingVM.restSecondsLeft,
                        totalSeconds: loggingVM.totalRestSeconds,
                        onStop: { loggingVM.stopRest() }
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Warm-up sets (compound only, if any)
                if !warmupSets.isEmpty {
                    warmupSection
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                // Column header
                setColumnHeader
                    .padding(.horizontal)
                    .padding(.bottom, 4)

                Divider().padding(.horizontal)

                // Zero state
                if isFirstTimeExercise {
                    firstTimePrompt.padding()
                }

                // Set rows
                ForEach(0..<rowCount, id: \.self) { i in
                    SetSideBySideRow(
                        setNumber: i + 1,
                        previousSet: prevSets[safe: i],
                        currentSet: currentSets[safe: i],
                        suggestion: i == 0 ? suggestion : nil,  // only first row gets suggestion
                        onTap: {
                            let set = getOrCreateSet(at: i)
                            setToEdit = set
                            showSetEditor = true
                        }
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 2)
                }

                // Add extra set
                Button {
                    let new = SetLog(
                        setNumber: (currentSets.last?.setNumber ?? 0) + 1,
                        weight: currentSets.last?.weight ?? prevSets.last?.weight ?? 0,
                        reps: currentSets.last?.reps ?? exerciseLog.plannedReps
                    )
                    modelContext.insert(new)
                    new.exerciseLog = exerciseLog
                    exerciseLog.setLogs.append(new)
                    try? modelContext.save()
                    setToEdit = new
                    showSetEditor = true
                } label: {
                    Label("Add Set", systemImage: "plus.circle.fill")
                        .font(.subheadline.bold()).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Notes section
                notesSection
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
            }
        }
        .animation(.spring(response: 0.3), value: loggingVM.isResting)
        .onDisappear { try? modelContext.save() }
        .sheet(isPresented: $showSetEditor) {
            if let set = setToEdit {
                SetEditorSheet(
                    set: set,
                    enableRIRRPE: enableRIRRPE,
                    defaultRestSeconds: defaultRestSeconds,
                    onSave: {
                        try? modelContext.save()
                        showSetEditor = false
                    },
                    onSaveAndRest: { seconds in
                        try? modelContext.save()
                        showSetEditor = false
                        loggingVM.startRest(seconds: seconds)
                    }
                )
            }
        }
    }

    // MARK: - Sub-views

    var exerciseHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            // Photo placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 76, height: 76)
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.plus")
                        .foregroundStyle(.secondary).font(.title2)
                    Text("Add Photo").font(.caption2).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(exerciseLog.exerciseName).font(.title3.bold()).lineLimit(2)

                if !exerciseLog.muscleGroup.isEmpty {
                    Text(exerciseLog.muscleGroup)
                        .font(.caption).foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }

                // AI suggestion badge
                if let s = suggestion, isFirstTimeExercise == false {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile").font(.caption2)
                        Text(String(format: "Suggest: %.1fkg × %d", s.weight, s.reps)).font(.caption)
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.purple.opacity(0.1), in: Capsule())
                }

                if let prev = previousLog, let date = prev.session?.date {
                    Text("Last: \(date, style: .date)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    var setColumnHeader: some View {
        HStack {
            Text("#").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 28)
            Spacer()
            Text("PREVIOUS").font(.caption.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Rectangle().fill(Color(.separator)).frame(width: 1, height: 14)
            Text("TODAY").font(.caption.bold()).foregroundStyle(.orange).frame(maxWidth: .infinity)
        }
    }

    var firstTimePrompt: some View {
        HStack(spacing: 10) {
            Image(systemName: "flag.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("First time — set your baseline").font(.subheadline.bold())
                Text("Log any weight and reps. Future sessions will track your progress from here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    var warmupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Warm-up Sets").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(warmupSets) { ws in
                HStack {
                    Text("W\(ws.setNumber)").font(.caption).foregroundStyle(.secondary).frame(width: 28)
                    Text(String(format: "%.1f kg × %d", ws.weight, ws.reps)).font(.subheadline)
                    Spacer()
                    Image(systemName: ws.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(ws.isCompleted ? .green : .secondary)
                        .onTapGesture { ws.isCompleted.toggle(); try? modelContext.save() }
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Previous notes (grayed)
            if let prev = previousLog, !prev.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Previous notes").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(prev.notes).font(.subheadline).foregroundStyle(.secondary).italic()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }

            // Today notes
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(.caption.bold()).foregroundStyle(.secondary)
                TextField("How did it feel? Any notes…", text: $exerciseLog.notes, axis: .vertical)
                    .font(.subheadline).lineLimit(2...5)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Helpers

    func getOrCreateSet(at index: Int) -> SetLog {
        if let existing = currentSets[safe: index] { return existing }
        let prev = prevSets[safe: index]
        let new = SetLog(
            setNumber: index + 1,
            weight: prev?.weight ?? currentSets.last?.weight ?? 0,
            reps: prev?.reps ?? exerciseLog.plannedReps
        )
        modelContext.insert(new)
        new.exerciseLog = exerciseLog
        exerciseLog.setLogs.append(new)
        try? modelContext.save()
        return new
    }
}

// MARK: - Set Side By Side Row
struct SetSideBySideRow: View {
    let setNumber: Int
    let previousSet: SetLog?
    let currentSet: SetLog?
    let suggestion: ProgressionEngine.Suggestion?
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("\(setNumber)").font(.subheadline.bold()).foregroundStyle(.secondary).frame(width: 28)

            // Previous
            Group {
                if let prev = previousSet {
                    VStack(spacing: 1) {
                        Text(String(format: "%.1f kg", prev.weight)).font(.subheadline.bold())
                        Text("× \(prev.reps)").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("—").foregroundStyle(.quaternary)
                }
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(Color(.separator)).frame(width: 1, height: 44)

            // Today
            Button(action: onTap) {
                ZStack {
                    if let cur = currentSet {
                        VStack(spacing: 1) {
                            Text(String(format: "%.1f kg", cur.weight))
                                .font(.subheadline.bold())
                                .foregroundStyle(cur.isCompleted ? .green : .orange)
                            Text("× \(cur.reps)")
                                .font(.caption)
                                .foregroundStyle(cur.isCompleted ? .green.opacity(0.8) : .orange.opacity(0.8))
                        }
                    } else if let s = suggestion {
                        // Show suggestion as placeholder
                        VStack(spacing: 1) {
                            Text(String(format: "%.1f kg", s.weight))
                                .font(.subheadline).foregroundStyle(.tertiary)
                            Text("× \(s.reps)")
                                .font(.caption).foregroundStyle(.quaternary)
                        }
                    } else {
                        Text("tap to log").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    currentSet?.isCompleted == true ? Color.green.opacity(0.07) : Color.orange.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Set Editor Sheet
struct SetEditorSheet: View {
    @Bindable var set: SetLog
    let enableRIRRPE: Bool
    let defaultRestSeconds: Int
    let onSave: () -> Void
    let onSaveAndRest: (Int) -> Void

    @State private var restDuration: Int

    init(set: SetLog, enableRIRRPE: Bool, defaultRestSeconds: Int,
         onSave: @escaping () -> Void, onSaveAndRest: @escaping (Int) -> Void) {
        self.set = set
        self.enableRIRRPE = enableRIRRPE
        self.defaultRestSeconds = defaultRestSeconds
        self.onSave = onSave
        self.onSaveAndRest = onSaveAndRest
        self._restDuration = State(initialValue: defaultRestSeconds)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    weightSection
                    repsSection
                    if enableRIRRPE { rirSection; rpeSection }
                    restSection
                    actionButtons
                }
                .padding()
            }
            .navigationTitle("Set \(set.setNumber)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    var weightSection: some View {
        VStack(spacing: 12) {
            Text("Weight (kg)").font(.headline).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Button { if set.weight >= 2.5 { set.weight -= 2.5 } } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 38)).foregroundStyle(.orange.opacity(0.7))
                }
                Text(String(format: "%.1f", set.weight))
                    .font(.system(size: 52, weight: .bold, design: .rounded)).frame(minWidth: 130)
                Button { set.weight += 2.5 } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 38)).foregroundStyle(.orange)
                }
            }
            HStack(spacing: 8) {
                ForEach([1.0, 2.5, 5.0, 10.0], id: \.self) { inc in
                    Button("+\(String(format: inc.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", inc))") {
                        set.weight += inc
                    }
                    .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color(.tertiarySystemBackground), in: Capsule())
                }
            }
        }
        .padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    var repsSection: some View {
        VStack(spacing: 12) {
            Text("Reps").font(.headline).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Button { if set.reps > 0 { set.reps -= 1 } } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 38)).foregroundStyle(.orange.opacity(0.7))
                }
                Text("\(set.reps)")
                    .font(.system(size: 52, weight: .bold, design: .rounded)).frame(minWidth: 80)
                Button { set.reps += 1 } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 38)).foregroundStyle(.orange)
                }
            }
        }
        .padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    var rirSection: some View {
        VStack(spacing: 10) {
            Text("Reps in Reserve (RIR)").font(.headline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(0...4, id: \.self) { val in
                    Button {
                        set.rir = set.rir == val ? -1 : val  // toggle off
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(val)").font(.headline.bold())
                            Text(["Fail","1","2","3","4+"][safe: val] ?? "").font(.caption2)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(set.rir == val ? Color.orange : Color(.tertiarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(set.rir == val ? .white : .primary)
                    }
                }
            }
        }
        .padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    var rpeSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("RPE (Effort)").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Text(set.rpe >= 0 ? String(format: "%.1f / 10", set.rpe) : "Not set")
                    .font(.headline.bold()).foregroundStyle(.orange)
            }
            Slider(value: Binding(
                get: { set.rpe >= 0 ? set.rpe : 7.0 },
                set: { set.rpe = $0 }
            ), in: 6...10, step: 0.5).tint(.orange)
            HStack {
                Text("6 — Easy").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("10 — Max").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    var restSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Rest Timer").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Text("\(restDuration)s").font(.headline.bold()).foregroundStyle(.orange)
            }
            Slider(
                value: Binding(get: { Double(restDuration) }, set: { restDuration = Int($0) }),
                in: 30...300, step: 15
            ).tint(.orange)
            HStack {
                Text("30s").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("5 min").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                set.isCompleted = true
                onSaveAndRest(restDuration)
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save & Rest \(restDuration)s").fontWeight(.bold)
                }
                .frame(maxWidth: .infinity).padding()
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white)
            }

            Button {
                set.isCompleted = true
                onSave()
            } label: {
                Text("Save").fontWeight(.semibold)
                    .frame(maxWidth: .infinity).padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

// MARK: - Rest Timer Banner
struct RestTimerBanner: View {
    @Binding var secondsLeft: Int
    let totalSeconds: Int
    let onStop: () -> Void

    var progress: Double {
        totalSeconds > 0 ? Double(secondsLeft) / Double(totalSeconds) : 0
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.orange.opacity(0.2), lineWidth: 5)
                Circle().trim(from: 0, to: progress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: secondsLeft)
                Text("\(secondsLeft)").font(.caption.bold().monospacedDigit()).foregroundStyle(.orange)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text("Resting").font(.subheadline.bold())
                Text("Next set in \(secondsLeft)s").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Skip", action: onStop).font(.subheadline.bold()).foregroundStyle(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}
