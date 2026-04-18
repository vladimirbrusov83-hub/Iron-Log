import SwiftUI
import SwiftData

@main
struct IronLogApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await NotificationService.shared.requestPermission()
                }
        }
        .modelContainer(for: [
            AppUser.self,
            BodyweightEntry.self,
            Exercise.self,
            WorkoutProgram.self,
            WorkoutDay.self,
            PlannedExercise.self,
            WorkoutSession.self,
            ExerciseLog.self,
            SetLog.self,
            PersonalRecord.self,
        ])
    }
}
