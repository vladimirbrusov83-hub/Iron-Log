import Foundation
import SwiftData

// MARK: - User Settings & Preferences
@Model
class AppUser {
    var id: UUID
    var createdAt: Date
    // Bodyweight
    @Relationship(deleteRule: .cascade) var bodyweightEntries: [BodyweightEntry]
    // Settings
    var enableRIRRPE: Bool
    var defaultRestSeconds: Int
    var deloadIntervalWeeks: Int        // suggest deload every N weeks
    var lastDeloadSuggestionDate: Date?
    var weightUnit: String              // "kg" or "lb"

    init() {
        self.id = UUID()
        self.createdAt = Date()
        self.bodyweightEntries = []
        self.enableRIRRPE = false
        self.defaultRestSeconds = 90
        self.deloadIntervalWeeks = 6
        self.lastDeloadSuggestionDate = nil
        self.weightUnit = "kg"
    }
}

// MARK: - Bodyweight Entry
@Model
class BodyweightEntry {
    var id: UUID
    var date: Date
    var weight: Double                  // stored in kg always
    var user: AppUser?

    init(weight: Double, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.weight = weight
    }
}

// MARK: - Exercise Definition
@Model
class Exercise {
    var id: UUID
    var name: String
    var muscleGroup: String             // "Chest", "Back", "Legs", etc.
    var secondaryMuscles: [String]      // stored as array
    var isCompound: Bool                // used for warm-up calculator
    var notes: String
    var photoPath: String?              // file path to user photo
    var isPreset: Bool                  // built-in exercises can't be deleted
    var createdAt: Date

    init(name: String, muscleGroup: String, secondaryMuscles: [String] = [],
         isCompound: Bool = false, notes: String = "", isPreset: Bool = false) {
        self.id = UUID()
        self.name = name
        self.muscleGroup = muscleGroup
        self.secondaryMuscles = secondaryMuscles
        self.isCompound = isCompound
        self.notes = notes
        self.photoPath = nil
        self.isPreset = isPreset
        self.createdAt = Date()
    }
}

// MARK: - Workout Program
@Model
class WorkoutProgram {
    var id: UUID
    var name: String
    var programDescription: String
    var createdAt: Date
    var isPinned: Bool
    var isPreset: Bool
    @Relationship(deleteRule: .cascade) var days: [WorkoutDay]

    init(name: String, description: String = "", isPreset: Bool = false) {
        self.id = UUID()
        self.name = name
        self.programDescription = description
        self.createdAt = Date()
        self.isPinned = false
        self.isPreset = isPreset
        self.days = []
    }
}

// MARK: - Workout Day Template
@Model
class WorkoutDay {
    var id: UUID
    var name: String
    var order: Int
    var program: WorkoutProgram?
    @Relationship(deleteRule: .cascade) var plannedExercises: [PlannedExercise]

    init(name: String, order: Int) {
        self.id = UUID()
        self.name = name
        self.order = order
        self.plannedExercises = []
    }
}

// MARK: - Planned Exercise (template slot in a day)
@Model
class PlannedExercise {
    var id: UUID
    var order: Int
    var plannedSets: Int
    var plannedReps: Int                // target reps per set
    var exercise: Exercise?
    var day: WorkoutDay?

    init(order: Int, exercise: Exercise, plannedSets: Int = 3, plannedReps: Int = 10) {
        self.id = UUID()
        self.order = order
        self.plannedSets = plannedSets
        self.plannedReps = plannedReps
        self.exercise = exercise
    }
}

// MARK: - Workout Session (completed or in-progress)
@Model
class WorkoutSession {
    var id: UUID
    var date: Date
    var dayName: String
    var programName: String
    var durationSeconds: Int
    var notes: String
    var isFinished: Bool
    @Relationship(deleteRule: .cascade) var exerciseLogs: [ExerciseLog]

    init(dayName: String, programName: String = "") {
        self.id = UUID()
        self.date = Date()
        self.dayName = dayName
        self.programName = programName
        self.durationSeconds = 0
        self.notes = ""
        self.isFinished = false
        self.exerciseLogs = []
    }

    var formattedDuration: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        let s = durationSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    var totalVolume: Double {
        exerciseLogs.flatMap { $0.setLogs }.reduce(0) { $0 + $1.volume }
    }
}

// MARK: - Exercise Log (one exercise within a session)
@Model
class ExerciseLog {
    var id: UUID
    var exerciseName: String            // denormalized — exercise might be renamed
    var exerciseID: UUID?               // reference to Exercise
    var muscleGroup: String             // denormalized for stats
    var order: Int
    var notes: String
    var plannedSets: Int
    var plannedReps: Int
    var session: WorkoutSession?
    @Relationship(deleteRule: .cascade) var setLogs: [SetLog]

    init(exerciseName: String, exerciseID: UUID?, muscleGroup: String,
         order: Int, plannedSets: Int = 0, plannedReps: Int = 0) {
        self.id = UUID()
        self.exerciseName = exerciseName
        self.exerciseID = exerciseID
        self.muscleGroup = muscleGroup
        self.order = order
        self.notes = ""
        self.plannedSets = plannedSets
        self.plannedReps = plannedReps
        self.setLogs = []
    }
}

// MARK: - Set Log
@Model
class SetLog {
    var id: UUID
    var setNumber: Int
    var weight: Double                  // always stored in kg
    var reps: Int
    var rir: Int                        // 0-4; -1 = not tracked
    var rpe: Double                     // 6-10; -1 = not tracked
    var notes: String
    var isCompleted: Bool
    var isWarmup: Bool
    var exerciseLog: ExerciseLog?

    init(setNumber: Int, weight: Double = 0, reps: Int = 0,
         rir: Int = -1, rpe: Double = -1, isWarmup: Bool = false) {
        self.id = UUID()
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.rir = rir
        self.rpe = rpe
        self.notes = ""
        self.isCompleted = false
        self.isWarmup = isWarmup
    }

    var volume: Double { isWarmup ? 0 : weight * Double(reps) }

    // Effective RIR — nil if not tracked
    var effectiveRIR: Int? { rir >= 0 ? rir : nil }
    var effectiveRPE: Double? { rpe >= 0 ? rpe : nil }
}

// MARK: - Personal Record
@Model
class PersonalRecord {
    var id: UUID
    var exerciseName: String
    var exerciseID: UUID?
    var weight: Double
    var reps: Int
    var date: Date
    var sessionID: UUID?

    init(exerciseName: String, exerciseID: UUID?, weight: Double, reps: Int, sessionID: UUID?) {
        self.id = UUID()
        self.exerciseName = exerciseName
        self.exerciseID = exerciseID
        self.weight = weight
        self.reps = reps
        self.date = Date()
        self.sessionID = sessionID
    }

    // 1RM estimate using Epley formula
    var estimated1RM: Double {
        reps == 1 ? weight : weight * (1 + Double(reps) / 30.0)
    }
}

// MARK: - Helpers
extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

// Muscle group set counters — standalone to keep @Model classes clean
func setsPerMuscle(for day: WorkoutDay) -> [String: Int] {
    var result: [String: Int] = [:]
    for pe in day.plannedExercises where pe.plannedSets > 0 {
        let m = pe.exercise?.muscleGroup ?? "Other"
        result[m, default: 0] += pe.plannedSets
    }
    return result
}

func weeklySetsPerMuscle(for program: WorkoutProgram) -> [String: Int] {
    var result: [String: Int] = [:]
    for day in program.days {
        for (m, s) in setsPerMuscle(for: day) { result[m, default: 0] += s }
    }
    return result
}
