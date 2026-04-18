# IronLog

A production-grade iOS strength training app with an AI coaching engine. Built entirely with SwiftUI and SwiftData — no third-party dependencies.

---

## Features

- **Workout Logging** — Log sets, reps, weight, RIR (Reps In Reserve), and RPE in real time
- **Program Management** — Create and manage multi-day training programs with drag-to-reorder
- **AI Coach** — Evidence-based progression suggestions and deload detection derived from 1,500+ real athlete sessions
- **Personal Records** — Automatic PR detection after every session with Epley estimated 1RM
- **Statistics** — Volume trends, intensity curves, bodyweight chart, and per-muscle-group analytics
- **Rest Timer** — Countdown timer with haptic feedback and quick-adjust presets
- **Exercise Library** — 40+ preset exercises organized by muscle group, plus custom exercise creation
- **Program Sharing** — Export and import programs as `.ironlog` files
- **Multi-unit Support** — kg or lb, applied consistently across the entire app
- **Coaching Tips** — 37 evidence-based tips from elite bodybuilders (Hany Rambod, Chris Bumstead, Phil Heath, and others)
- **Dark Mode** — Full dark mode support with military-style dark aesthetic

---

## Tech Stack

| | |
|---|---|
| **Language** | Swift 5.9+ |
| **UI** | SwiftUI (100% — no UIKit) |
| **Persistence** | SwiftData |
| **Charts** | SwiftUI Charts |
| **Concurrency** | async/await |
| **Notifications** | UserNotifications |
| **Minimum iOS** | iOS 17+ |
| **Dependencies** | None — Apple frameworks only |

---

## Architecture

```
MVVM + stateless Services layer

Views → ViewModels → Services → SwiftData Models
```

```
IronLog/
├── App/                    ← Entry point, tab bar, SwiftData container
├── Models/                 ← 10 SwiftData models
├── ViewModels/             ← Active workout state, timers, PR detection
├── Services/
│   ├── CoachBrain.swift    ← AI coaching engine (stateless, 21KB)
│   ├── ProgressionEngine   ← Per-set weight suggestion logic
│   ├── ExportService       ← .ironlog JSON export/import
│   ├── RestTimerService    ← Countdown timer with haptics
│   └── SeedData            ← 40+ preset exercises + programs
├── ViewsLog/               ← Workout session screens
├── ViewsHistory/           ← Past sessions browser
├── ViewsPrograms/          ← Program editor and sharing
├── ViewsStats/             ← Charts, coach cards, exercise library
└── ViewsSettings/          ← App preferences
```

---

## Data Model

10 SwiftData models with cascade-delete relationships:

```
AppUser
 └── BodyweightEntry[]

WorkoutProgram
 └── WorkoutDay[]
      └── PlannedExercise[]
           └── Exercise

WorkoutSession
 └── ExerciseLog[]
      └── SetLog[]

PersonalRecord
Exercise (library)
```

---

## Coach Brain

The coaching engine is stateless — it takes workout history as input and returns coaching cards per exercise. Tuned on 3 years of training data across 3 athletes (~1,500 sessions).

**Outputs per exercise:**
- Suggested next weight with confidence level (low / medium / high)
- Warmup ladder: ~60% × 8 → ~75% × 5 → ~85% × 3 → ~92% × 2
- Warnings: deload recommended, plateau detected, long absence, PR within reach, new PR

**Progression logic:**
- RIR ≥ 3 → +5 kg (upper body) / +10 kg (lower body)
- RIR ≥ 1 → +2.5 kg
- All sets complete → +2.5 kg
- Stagnation (same weight 3+ sessions, RIR not improving) → plateau warning
- 6–8 weeks continuous load → deload recommendation

---

## Getting Started

1. Clone the repo
2. Open `IronLog.xcodeproj` in Xcode
3. Select a simulator or connected device (iOS 17+)
4. Press **Cmd + R** to build and run
5. No API keys or environment variables needed — fully offline

---

## Program Export Format

Programs can be shared as `.ironlog` files (JSON):

```json
{
  "version": 1,
  "exportDate": "2026-04-17T00:00:00Z",
  "program": {
    "name": "Push Pull Legs",
    "description": "Classic 6-day split",
    "days": [
      {
        "name": "Push",
        "order": 0,
        "exercises": [
          { "name": "Bench Press", "muscleGroup": "Chest", "plannedSets": 4, "plannedReps": 8, "order": 0 }
        ]
      }
    ]
  }
}
```

---

## Built By

Vladimir Brusov — strength coach and developer.  
Coaching data sourced from real athlete training across 3 years of TrueCoach sessions.
