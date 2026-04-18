import Foundation
import UserNotifications

/// Handles all push notification logic.
/// Currently: PR notifications. Architected to support reminders later.
@MainActor
class NotificationService {
    static let shared = NotificationService()
    private init() {}

    func requestPermission() async {
        try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Call this after saving a new PersonalRecord.
    func notifyNewPR(exerciseName: String, weight: Double, reps: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🏆 New Personal Record!"
        content.body = "\(exerciseName): \(String(format: "%.1f", weight))kg × \(reps) reps"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "PR-\(exerciseName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}
