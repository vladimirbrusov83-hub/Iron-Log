import Foundation
import SwiftData
import Observation

/// ViewModel for the active workout logging screen.
/// Owns session lifecycle: start, log sets, finish, discard.
@Observable
class LoggingViewModel {

    // MARK: - State
    var session: WorkoutSession?
    var sessionID: UUID?
    var elapsedSeconds: Int = 0
    var isRunning: Bool = false
    var selectedExerciseIndex: Int = 0
    var isResting: Bool = false
    var restSecondsLeft: Int = 0
    var totalRestSeconds: Int = 0

    private var workTimer: Timer?
    private var restTimer: Timer?
    private var timerSaveCounter: Int = 0

    // MARK: - Start workout
    func startWorkout(day: WorkoutDay, programName: String, context: ModelContext) {
        let s = WorkoutSession(dayName: day.name, programName: programName)
        context.insert(s)

        let sortedExercises = day.plannedExercises.sorted { $0.order < $1.order }
        for (i, pe) in sortedExercises.enumerated() {
            guard let ex = pe.exercise else { continue }
            let log = ExerciseLog(
                exerciseName: ex.name,
                exerciseID: ex.id,
                muscleGroup: ex.muscleGroup,
                order: i,
                plannedSets: pe.plannedSets,
                plannedReps: pe.plannedReps
            )
            context.insert(log)
            log.session = s
            s.exerciseLogs.append(log)
        }

        do { try context.save() } catch { print("Start workout save error: \(error)") }

        session = s
        sessionID = s.id
        isRunning = true
        startWorkTimer(context: context)
    }

    // MARK: - Finish
    func finishWorkout(context: ModelContext, allSessions: [WorkoutSession]) {
        stopWorkTimer()
        stopRest()
        guard let s = session else { return }
        s.durationSeconds = elapsedSeconds
        s.isFinished = true

        // Check for PRs
        checkAndSavePRs(session: s, context: context, allSessions: allSessions)

        do { try context.save() } catch { print("Finish save error: \(error)") }
        isRunning = false
    }

    // MARK: - Discard
    func discardWorkout(context: ModelContext) {
        stopWorkTimer()
        stopRest()
        if let s = session { context.delete(s) }
        try? context.save()
        session = nil
        sessionID = nil
        isRunning = false
        elapsedSeconds = 0
    }

    // MARK: - Add set
    func addSet(to log: ExerciseLog, weight: Double, reps: Int, context: ModelContext) {
        let next = (log.setLogs.map { $0.setNumber }.max() ?? 0) + 1
        let set = SetLog(setNumber: next, weight: weight, reps: reps)
        context.insert(set)
        set.exerciseLog = log
        log.setLogs.append(set)
        try? context.save()
    }

    // MARK: - Rest timer
    func startRest(seconds: Int) {
        stopRest()
        totalRestSeconds = seconds
        restSecondsLeft = seconds
        isResting = true
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.restSecondsLeft > 0 {
                self.restSecondsLeft -= 1
            } else {
                self.stopRest()
            }
        }
    }

    func stopRest() {
        restTimer?.invalidate()
        restTimer = nil
        isResting = false
    }

    // MARK: - PR check
    private func checkAndSavePRs(session: WorkoutSession, context: ModelContext, allSessions: [WorkoutSession]) {
        let existingPRs = (try? context.fetch(FetchDescriptor<PersonalRecord>())) ?? []

        for log in session.exerciseLogs {
            guard let exerciseID = log.exerciseID else { continue }
            let workingSets = log.setLogs.filter { $0.isCompleted && !$0.isWarmup }
            guard let bestSet = workingSets.max(by: { $0.weight < $1.weight }) else { continue }

            let currentPR = existingPRs.first(where: { $0.exerciseID == exerciseID })

            let isNewPR: Bool
            if let pr = currentPR {
                isNewPR = bestSet.weight > pr.weight || (bestSet.weight == pr.weight && bestSet.reps > pr.reps)
            } else {
                isNewPR = true
            }

            if isNewPR {
                if let existing = currentPR { context.delete(existing) }
                let pr = PersonalRecord(
                    exerciseName: log.exerciseName,
                    exerciseID: exerciseID,
                    weight: bestSet.weight,
                    reps: bestSet.reps,
                    sessionID: session.id
                )
                context.insert(pr)
                Task { @MainActor in
                    await NotificationService.shared.notifyNewPR(
                        exerciseName: log.exerciseName,
                        weight: bestSet.weight,
                        reps: bestSet.reps
                    )
                }
            }
        }
    }

    // MARK: - Work timer
    private func startWorkTimer(context: ModelContext) {
        workTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsedSeconds += 1
            self.timerSaveCounter += 1
            // Save to DB every 15s — not every second
            if self.timerSaveCounter % 15 == 0 {
                self.session?.durationSeconds = self.elapsedSeconds
                try? context.save()
            }
        }
    }

    private func stopWorkTimer() {
        workTimer?.invalidate()
        workTimer = nil
    }

    var formattedElapsed: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
