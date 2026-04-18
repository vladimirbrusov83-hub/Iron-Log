// CoachBrain.swift
// IronLog — Coach Intelligence Layer
//
// Derived from 3 years × 3 athletes (1,500+ completed sessions) of real TrueCoach data.
// Pure logic layer — no UI, no data mutations, no AI calls.
// All suggestions are transparent/ghost-text unless user acts on them.
//
// Key findings from data analysis:
//   - Progression trigger: RIR 2–3 across 1–3 sessions at same weight → suggest increase
//   - Avg weight jumps: upper body ~5–7kg, lower body ~10–12kg
//   - Deload naturally every 6–8 weeks (Karl: ~7 weeks, Eric: ~7 weeks)
//   - Warmup structure: ~60% × 8, ~75% × 5, ~85% × 3, ~92% × 2 → working sets
//   - Stagnation threshold: same weight 3+ sessions with RIR not improving → plateau alert
//   - Athletes train 2.5–4x/week consistently; gaps >7 days signal deload or break

import Foundation
import SwiftData

// MARK: - Output Types

/// A complete coaching suggestion for one exercise in one session.
/// All fields are optional — consume only what you need, ignore the rest.
public struct CoachSuggestion {
    public let exerciseId: UUID
    public let exerciseName: String

    // Primary suggestions (ghost text in log fields)
    public let suggestedSets: Int?
    public let suggestedReps: Int?
    public let suggestedWeight: Double?

    // Warmup ladder (only for compound exercises with sufficient history)
    public let warmupSets: [WarmupSet]

    // Background warnings (shown as subtle banners, never blocking)
    public let warnings: [CoachWarning]

    // Debug/transparency info — shown if user taps "why?"
    public let reasoning: String
    public let confidence: SuggestionConfidence
}

public struct WarmupSet: Identifiable {
    public let id = UUID()
    public let weight: Double
    public let reps: Int
    public let percentageOfWorking: Double
    public let label: String  // e.g. "Warm-up 1", "Activation"
}

public enum CoachWarning: Equatable {
    case deloadRecommended(weeksUnderLoad: Int)       // 6–8 weeks continuous loading
    case plateauDetected(sessionsStuck: Int)           // Same weight 3+ sessions, RIR not improving
    case longAbsence(daysSinceLastSession: Int)        // >14 days — suggest conservative start
    case personalRecordClose(percentBelow: Double)     // Within 5% of all-time max
    case newPR                                          // Just set a new record
}

public enum SuggestionConfidence {
    case low        // 1–2 sessions of history
    case medium     // 3–5 sessions
    case high       // 6+ sessions with clear pattern
}


// MARK: - Coach Brain

/// The Coach Brain. Instantiate once, call `suggest()` per exercise.
/// Thread-safe for async use. Stateless — all state comes from history parameter.
public final class CoachBrain {

    // MARK: Configuration (tuned from real athlete data)

    private struct Config {
        // Progression triggers (from RIR-before-increase analysis)
        // Karl: avg 2.6 RIR; Matthew: avg 2.6 RIR; Eric: avg 2.4 RIR
        static let progressionRIRThreshold: Double = 2.5
        static let progressionMinSessions: Int = 2   // sessions at same weight before suggesting increase

        // Weight increment defaults (from avg jump analysis)
        static let upperBodyIncrement: Double = 2.5   // kg — Karl avg 5.2, Eric 10.4 / 2 for conservative
        static let lowerBodyIncrement: Double = 5.0   // kg — lower body moves bigger
        static let isolationIncrement: Double = 2.5

        // Deload detection
        // Karl: ~7 weeks, Eric: ~7 weeks between natural deloads
        static let deloadWarningWeeks: Int = 6
        static let deloadForceWeeks: Int = 8

        // Plateau detection
        // From stagnation analysis: 3+ sessions same weight with non-improving RIR
        static let plateauSessionCount: Int = 3

        // Absence threshold
        static let longAbsenceDays: Int = 14
        static let absenceWeightReductionPct: Double = 0.10  // suggest -10% after long break

        // Warmup percentages (derived from compound lift warmup analysis across all 3 athletes)
        // Karl bench: 67%×7, 80%×6, 91%×4, 99%×4
        // Eric bench: 59%×7, 80%×6, 89%×5, 97%×4
        // Averaged and rounded to clean structure:
        static let warmupLadder: [(pct: Double, reps: Int, label: String)] = [
            (0.40, 10, "Bar / Empty"),    // movement prep, always light
            (0.60, 8,  "Warm-up 1"),
            (0.75, 5,  "Warm-up 2"),
            (0.85, 3,  "Activation"),
            (0.92, 2,  "Primer"),
        ]

        // Compounds that get warmup ladders
        static let compoundExercises: Set<String> = [
            "squat", "barbell squat", "back squat", "front squat",
            "deadlift", "conventional deadlift", "sumo deadlift",
            "trap bar deadlift", "trap bar dl", "trap dl",
            "bench press", "barbell bench", "bb bench press",
            "overhead press", "ohp", "military press", "seated military press",
            "incline bench press", "incline bb press",
            "close grip bench press", "cgbp",
            "romanian deadlift", "rdl", "bar rdl",
            "row", "barbell row", "bentover row",
        ]
    }


    // MARK: - Public API

    /// Generate a suggestion for an exercise given its full history.
    ///
    /// - Parameters:
    ///   - exercise: The exercise definition
    ///   - history: All previous logged sets for this exercise, sorted by date ascending
    ///   - allExerciseHistory: History across ALL exercises (for deload calculation)
    ///   - today: Current date (injectable for testing)
    /// - Returns: A CoachSuggestion. All fields may be nil if insufficient data.
    public func suggest(
        for exercise: ExerciseDefinition,
        history: [LoggedExerciseEntry],
        allExerciseHistory: [LoggedExerciseEntry],
        today: Date = Date()
    ) -> CoachSuggestion {

        let recentHistory = history.sorted { $0.date < $1.date }
        let lastSession = recentHistory.last
        let isCompound = isCompoundExercise(exercise.name)

        // --- Suggested weight ---
        let (suggestedWeight, weightReasoning) = computeSuggestedWeight(
            exercise: exercise,
            history: recentHistory,
            today: today
        )

        // --- Suggested sets & reps ---
        let (suggestedSets, suggestedReps, repReasoning) = computeSuggestedSetsReps(
            history: recentHistory,
            lastSession: lastSession
        )

        // --- Warmup ladder ---
        let warmupSets: [WarmupSet]
        if isCompound, let workWeight = suggestedWeight, workWeight > 0 {
            warmupSets = buildWarmupLadder(workingWeight: workWeight, exercise: exercise)
        } else {
            warmupSets = []
        }

        // --- Warnings ---
        let warnings = computeWarnings(
            exercise: exercise,
            history: recentHistory,
            allHistory: allExerciseHistory,
            today: today
        )

        // --- Confidence ---
        let confidence: SuggestionConfidence
        switch recentHistory.count {
        case 0...2: confidence = .low
        case 3...5: confidence = .medium
        default:    confidence = .high
        }

        // --- Reasoning (for transparency) ---
        let reasoning = [weightReasoning, repReasoning]
            .compactMap { $0 }
            .joined(separator: " | ")

        return CoachSuggestion(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            suggestedSets: suggestedSets,
            suggestedReps: suggestedReps,
            suggestedWeight: suggestedWeight,
            warmupSets: warmupSets,
            warnings: warnings,
            reasoning: reasoning.isEmpty ? "Not enough history yet" : reasoning,
            confidence: confidence
        )
    }


    // MARK: - Weight Progression Logic

    private func computeSuggestedWeight(
        exercise: ExerciseDefinition,
        history: [LoggedExerciseEntry],
        today: Date
    ) -> (Double?, String?) {

        guard !history.isEmpty else {
            return (nil, "No previous sessions")
        }

        let last = history.last!
        let lastWeight = last.topSetWeight
        let daysSinceLast = Calendar.current.dateComponents([.day], from: last.date, to: today).day ?? 0

        // Long absence — suggest conservative start
        if daysSinceLast > Config.longAbsenceDays {
            let conservativeWeight = lastWeight * (1.0 - Config.absenceWeightReductionPct)
            let rounded = roundToIncrement(conservativeWeight, exercise: exercise)
            return (rounded, "Back after \(daysSinceLast) days — suggesting -10% to ease back in")
        }

        // Need at least 2 sessions to detect pattern
        guard history.count >= 2 else {
            return (lastWeight, "Repeat last session weight")
        }

        // Check recent RIR trend
        let recentSessions = Array(history.suffix(Config.progressionMinSessions))
        let avgRIR = recentSessions.compactMap { $0.averageRIR }.average()

        // Sessions stuck at same weight
        let sessionsAtSameWeight = countConsecutiveSessionsAtWeight(lastWeight, in: history)

        // --- Progression decision ---
        // Derived rule: if RIR ≤ 2.5 for 2+ sessions at same weight → increase
        if let avgRIR = avgRIR,
           avgRIR <= Config.progressionRIRThreshold,
           sessionsAtSameWeight >= Config.progressionMinSessions {
            let increment = weightIncrement(for: exercise)
            let newWeight = lastWeight + increment
            return (newWeight, "Hit RIR \(String(format: "%.1f", avgRIR)) for \(sessionsAtSameWeight) sessions — time to progress (+\(formatWeight(increment)))")
        }

        // Check if all reps completed (no RIR data available)
        if avgRIR == nil {
            let allCompleted = recentSessions.allSatisfy { $0.completedAllTargetReps }
            if allCompleted && sessionsAtSameWeight >= Config.progressionMinSessions {
                let increment = weightIncrement(for: exercise)
                let newWeight = lastWeight + increment
                return (newWeight, "Completed all reps for \(sessionsAtSameWeight) sessions — suggesting progression")
            }
        }

        // Stagnation with high RIR — stay or deload
        if let avgRIR = avgRIR,
           avgRIR > 3.5,
           sessionsAtSameWeight >= Config.plateauSessionCount {
            // Possibly struggling — suggest same weight, user knows
            return (lastWeight, "RIR \(String(format: "%.1f", avgRIR)) suggests more room — stay at current weight")
        }

        // Default — repeat last weight
        return (lastWeight, "Stay at \(formatWeight(lastWeight)) — building consistency")
    }


    // MARK: - Sets & Reps Logic

    private func computeSuggestedSetsReps(
        history: [LoggedExerciseEntry],
        lastSession: LoggedExerciseEntry?
    ) -> (Int?, Int?, String?) {

        guard let last = lastSession else {
            return (3, 10, "Default starting volume")
        }

        let suggestedSets = last.workingSets
        let suggestedReps = last.targetReps

        return (suggestedSets, suggestedReps, nil)
    }


    // MARK: - Warmup Ladder

    /// Builds a classic percentage-based warmup ladder.
    /// Structure derived from 70+ compound lift warmup instances across Karl & Eric.
    public func buildWarmupLadder(workingWeight: Double, exercise: ExerciseDefinition) -> [WarmupSet] {
        let barWeight = exercise.barWeight ?? 20.0  // default 20kg Olympic bar

        return Config.warmupLadder.compactMap { step in
            let rawWeight = workingWeight * step.pct
            // Don't generate a warmup set if it's below or equal to bar weight
            guard rawWeight > barWeight else { return nil }
            let roundedWeight = roundToIncrement(rawWeight, exercise: exercise)
            return WarmupSet(
                weight: roundedWeight,
                reps: step.reps,
                percentageOfWorking: step.pct,
                label: step.label
            )
        }
    }


    // MARK: - Warnings

    private func computeWarnings(
        exercise: ExerciseDefinition,
        history: [LoggedExerciseEntry],
        allHistory: [LoggedExerciseEntry],
        today: Date
    ) -> [CoachWarning] {

        var warnings: [CoachWarning] = []

        // 1. Long absence warning
        if let lastDate = history.last?.date {
            let days = Calendar.current.dateComponents([.day], from: lastDate, to: today).day ?? 0
            if days > Config.longAbsenceDays {
                warnings.append(.longAbsence(daysSinceLastSession: days))
            }
        }

        // 2. Deload recommendation (based on continuous loading weeks)
        let weeksUnderLoad = computeWeeksUnderLoad(from: allHistory, today: today)
        if weeksUnderLoad >= Config.deloadForceWeeks {
            warnings.append(.deloadRecommended(weeksUnderLoad: weeksUnderLoad))
        }

        // 3. Plateau detection
        if history.count >= Config.plateauSessionCount {
            let lastWeight = history.last!.topSetWeight
            let sessionsAtSame = countConsecutiveSessionsAtWeight(lastWeight, in: history)
            let recentRIRs = Array(history.suffix(Config.plateauSessionCount))
                .compactMap { $0.averageRIR }

            if sessionsAtSame >= Config.plateauSessionCount {
                // Check if RIR is worsening or flat (true plateau)
                let isWorsening = recentRIRs.count >= 2 && recentRIRs.last! >= recentRIRs.first!
                if isWorsening {
                    warnings.append(.plateauDetected(sessionsStuck: sessionsAtSame))
                }
            }
        }

        // 4. PR check
        let allTimeMax = history.map { $0.topSetWeight }.max() ?? 0
        if let last = history.last {
            let current = last.topSetWeight
            if current > allTimeMax {
                warnings.append(.newPR)
            } else if allTimeMax > 0 {
                let pctBelow = (allTimeMax - current) / allTimeMax
                if pctBelow <= 0.05 && pctBelow > 0 {
                    warnings.append(.personalRecordClose(percentBelow: pctBelow * 100))
                }
            }
        }

        return warnings
    }


    // MARK: - Deload Tracking

    /// Counts how many consecutive weeks had training load (≥1 completed session).
    /// Based on pattern from all 3 athletes: natural deloads every 6–8 weeks.
    private func computeWeeksUnderLoad(from history: [LoggedExerciseEntry], today: Date) -> Int {
        guard !history.isEmpty else { return 0 }

        // Group sessions by ISO week
        let calendar = Calendar.current
        var weekSet: Set<String> = []
        for entry in history {
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.date)
            if let year = comps.yearForWeekOfYear, let week = comps.weekOfYear {
                weekSet.insert("\(year)-\(week)")
            }
        }

        // Count consecutive weeks backward from today
        var consecutiveWeeks = 0
        var checkDate = today
        for _ in 0..<16 {
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: checkDate)
            if let year = comps.yearForWeekOfYear, let week = comps.weekOfYear {
                let key = "\(year)-\(week)"
                if weekSet.contains(key) {
                    consecutiveWeeks += 1
                } else {
                    break  // gap found — streak ends
                }
            }
            checkDate = calendar.date(byAdding: .weekOfYear, value: -1, to: checkDate) ?? checkDate
        }

        return consecutiveWeeks
    }


    // MARK: - Helpers

    private func isCompoundExercise(_ name: String) -> Bool {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        return Config.compoundExercises.contains(where: { normalized.contains($0) })
    }

    private func weightIncrement(for exercise: ExerciseDefinition) -> Double {
        switch exercise.muscleGroup {
        case .legs, .back:
            return Config.lowerBodyIncrement
        case .chest, .shoulders, .arms:
            return Config.upperBodyIncrement
        default:
            return Config.isolationIncrement
        }
    }

    private func roundToIncrement(_ weight: Double, exercise: ExerciseDefinition) -> Double {
        // Round to nearest 2.5 for upper body, 5 for lower
        let increment: Double = exercise.muscleGroup == .legs ? 5.0 : 2.5
        return (weight / increment).rounded() * increment
    }

    private func countConsecutiveSessionsAtWeight(_ weight: Double, in history: [LoggedExerciseEntry]) -> Int {
        var count = 0
        for entry in history.reversed() {
            if abs(entry.topSetWeight - weight) < 0.1 {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(weight))kg"
            : "\(weight)kg"
    }
}


// MARK: - Supporting Types
// These mirror your SwiftData models — adjust property names to match your actual schema.

public struct ExerciseDefinition {
    public let id: UUID
    public let name: String
    public let muscleGroup: MuscleGroup
    public let barWeight: Double?  // nil for dumbbells/machines

    public init(id: UUID = UUID(), name: String, muscleGroup: MuscleGroup, barWeight: Double? = 20.0) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.barWeight = barWeight
    }
}

public enum MuscleGroup {
    case chest, back, shoulders, legs, arms, core, other
}

public struct LoggedExerciseEntry {
    public let id: UUID
    public let date: Date
    public let sets: [LoggedSet]

    /// Highest weight used in any working set this session
    public var topSetWeight: Double {
        sets.map { $0.weight }.max() ?? 0
    }

    /// Average RIR across all sets (nil if no RIR was logged)
    public var averageRIR: Double? {
        let rirValues = sets.compactMap { $0.rirLogged }
        guard !rirValues.isEmpty else { return nil }
        return rirValues.average()
    }

    /// Number of sets at or near the top weight (≥90%)
    public var workingSets: Int {
        guard topSetWeight > 0 else { return sets.count }
        return sets.filter { $0.weight >= topSetWeight * 0.90 }.count
    }

    /// Target reps — uses the most common rep count in working sets
    public var targetReps: Int {
        let workingSetReps = sets
            .filter { $0.weight >= topSetWeight * 0.90 }
            .map { $0.reps }
        return workingSetReps.mostCommon() ?? 8
    }

    /// Whether the athlete completed all target reps (approximation)
    public var completedAllTargetReps: Bool {
        let target = targetReps
        let workingSets = sets.filter { $0.weight >= topSetWeight * 0.90 }
        return workingSets.allSatisfy { $0.reps >= target }
    }

    public init(id: UUID = UUID(), date: Date, sets: [LoggedSet]) {
        self.id = id
        self.date = date
        self.sets = sets
    }
}

public struct LoggedSet {
    public let weight: Double
    public let reps: Int
    public let rirLogged: Double?  // nil if not tracked

    public init(weight: Double, reps: Int, rirLogged: Double? = nil) {
        self.weight = weight
        self.reps = reps
        self.rirLogged = rirLogged
    }
}


// MARK: - Array Extensions

private extension Array where Element == Double {
    func average() -> Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

private extension Array where Element == Int {
    func mostCommon() -> Int? {
        guard !isEmpty else { return nil }
        var freq: [Int: Int] = [:]
        forEach { freq[$0, default: 0] += 1 }
        return freq.max(by: { $0.value < $1.value })?.key
    }
}


// MARK: - Usage Example
/*

let brain = CoachBrain()

// Get suggestion for Bench Press
let benchExercise = ExerciseDefinition(
    name: "Bench Press",
    muscleGroup: .chest,
    barWeight: 20.0
)

let suggestion = brain.suggest(
    for: benchExercise,
    history: fetchHistory(for: benchExercise),
    allExerciseHistory: fetchAllHistory()
)

// In your exercise log screen:
if let weight = suggestion.suggestedWeight {
    weightField.placeholder = formatWeight(weight)  // transparent ghost text
}

if !suggestion.warmupSets.isEmpty {
    showWarmupPanel(suggestion.warmupSets)  // collapsible warmup section
}

for warning in suggestion.warnings {
    switch warning {
    case .deloadRecommended(let weeks):
        showBanner("You've trained \(weeks) weeks straight — consider a deload this week")
    case .plateauDetected(let sessions):
        showBanner("Same weight for \(sessions) sessions — try a technique variation or deload")
    case .newPR:
        showPRCelebration()
    default:
        break
    }
}

// Explanation (on "why?" tap):
showReasoning(suggestion.reasoning)  // e.g. "Hit RIR 2.0 for 2 sessions — time to progress (+2.5kg)"

*/
