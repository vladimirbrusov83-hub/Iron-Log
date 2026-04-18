# IronLog — Claude Instructions

## What This App Is

IronLog is a production-grade iOS strength training logger with an AI coaching engine. It tracks workouts, manages programs, detects personal records, and gives evidence-based progression suggestions derived from 1,500+ real athlete sessions.

- **Platform:** iOS 17+
- **Stack:** Swift 5.9+, 100% SwiftUI, SwiftData (no UIKit, no Core Data, no third-party deps)
- **Architecture:** MVVM — ViewModels + stateless Services layer

---

## Project Structure

```
IronLog/
├── App/
│   ├── IronLogApp.swift          ← SwiftData container setup, dark mode, app entry
│   └── ContentView.swift         ← Tab bar + rest timer banner
├── Models/
│   └── Models.swift              ← All 10 SwiftData models
├── ViewModels/
│   └── LoggingViewModel.swift    ← Active workout state, timers, PR detection
├── Services/
│   ├── CoachBrain.swift          ← Core intelligence engine (21KB, stateless)
│   ├── CoachBrainMapper.swift    ← Maps SwiftData models → CoachBrain inputs
│   ├── CoachingTips.swift        ← 37 pro tips from elite bodybuilders
│   ├── ProgressionEngine.swift   ← Per-set weight suggestion logic
│   ├── ExportService.swift       ← .ironlog JSON export/import
│   ├── RestTimerService.swift    ← Countdown timer with haptics
│   ├── NotificationService.swift ← PR push notifications
│   └── SeedData.swift            ← 40+ preset exercises + programs
├── ViewsLog/
│   ├── HomeView.swift            ← Program carousel, stats summary, quick-start
│   ├── TrainingDaysView.swift    ← Day selection from active program
│   ├── ExerciseListView.swift    ← Exercise picker for the session
│   ├── WorkoutLoggingView.swift  ← Main logging UI (33KB) — sets, rest timer, deload
│   ├── ExerciseLogView.swift     ← Per-exercise card with set rows
│   └── ActiveWorkoutView.swift   ← Active session overlay
├── ViewsHistory/
│   └── HistoryView.swift         ← Past sessions grouped by month
├── ViewsPrograms/
│   └── ProgramsView.swift        ← Create/edit programs, share via .ironlog
├── ViewsStats/
│   ├── StatsView.swift           ← Volume/intensity/bodyweight charts, PR list
│   ├── CoachView.swift           ← Coach card, warnings, tips by muscle
│   └── ExerciseLibraryView.swift ← Browse/search/create exercises
└── ViewsSettings/
    └── SettingsView.swift        ← Dark mode, rest duration, deload interval, units
```

---

## Data Models (SwiftData)

10 models with cascade-delete relationships:

| Model | Purpose |
|-------|---------|
| `AppUser` | Singleton user profile — settings, bodyweight history |
| `BodyweightEntry` | Date + weight entries for the bodyweight trend chart |
| `Exercise` | Exercise library — preset + custom, with muscle group tagging |
| `WorkoutProgram` | Named program container (pinnable, preset-safe) |
| `WorkoutDay` | Ordered days within a program |
| `PlannedExercise` | Exercise slot within a day (planned sets/reps) |
| `WorkoutSession` | A completed or active workout — stores program/day name at log time |
| `ExerciseLog` | Exercise record within a session |
| `SetLog` | Individual set: weight, reps, RIR, RPE, warmup flag |
| `PersonalRecord` | Best weight × reps per exercise + Epley e1RM |

---

## Key Services

### CoachBrain (`Services/CoachBrain.swift`)
Stateless engine tuned on 3 years × 3 real athletes (~1,500 sessions). Outputs per-exercise coaching cards with:
- Suggested next weight and confidence level (low/medium/high)
- Warmup ladder (60% × 8 → 75% × 5 → 85% × 3 → 92% × 2)
- Warning flags: `deloadRecommended`, `plateauDetected`, `longAbsence`, `personalRecordClose`, `newPR`

Never call this with mocked or partial data — it needs complete session history to be accurate.

### ProgressionEngine (`Services/ProgressionEngine.swift`)
Simpler per-session suggestion: reads RIR/RPE from last completed sets and outputs next weight.
- RIR ≥ 3 → +5kg; RIR ≥ 1 → +2.5kg; all sets complete → +2.5kg; else → same weight
- Handles bodyweight (0kg) by suggesting rep increases instead
- Clamps to prevent 0 or negative weight suggestions

### SeedData (`Services/SeedData.swift`)
Guards with `UserDefaults` boolean flags (not DB count) to prevent double-seeding on parallel init.
- Key: `ironlog_exercises_seeded_v3`
- Never replace this guard with a DB count check — it will race on first launch.

---

## Rules

- **SwiftData only.** No Core Data, no external DB, no third-party packages.
- **SwiftUI only.** No UIKit views. Use `UIImpactFeedbackGenerator` only for haptics (bridged).
- **iOS 17+ minimum.** `@Observable`, `@Query`, `@Bindable`, SwiftUI Charts are all available.
- **Stateless services.** CoachBrain and ProgressionEngine take inputs and return outputs — no stored state.
- **Seed guard.** Never touch the `UserDefaults` seed flags without understanding the race condition they prevent.
- **Session save cadence.** `LoggingViewModel` saves to SwiftData every 15 seconds during active sessions to prevent data loss on crash.
- **PR detection runs post-session.** Called in `finishWorkout()` — do not call mid-session.

---

## How to Build & Run

1. Open `IronLog/IronLog.xcodeproj` in Xcode
2. Select a simulator or connected device (iOS 17+)
3. **Cmd + R** to build and run
4. No env vars or API keys needed — fully offline

---

## Weight Units

`AppUser.weightUnit` is either `"kg"` or `"lb"`. All `SetLog.weight` values are stored in the user's preferred unit — there is no server-side conversion. Display and suggestion logic reads `weightUnit` from `AppUser` to format output correctly.

---

## Program Export Format (`.ironlog`)

```json
{
  "version": 1,
  "exportDate": "ISO8601",
  "program": {
    "name": "...",
    "description": "...",
    "days": [
      {
        "name": "...",
        "order": 0,
        "exercises": [
          { "name": "...", "muscleGroup": "...", "plannedSets": 4, "plannedReps": 8, "order": 0 }
        ]
      }
    ]
  }
}
```

Import finds existing exercises by name+muscleGroup, creates missing ones. Rejects duplicate program names.
