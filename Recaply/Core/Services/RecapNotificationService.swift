import Foundation
import UserNotifications

final class RecapNotificationService {
    static let shared = RecapNotificationService()

    private init() {}

    func notifyReady(title: String) async {
        await notify(
            title: "Recap ready",
            body: "\(title) is ready in Recaply.",
            identifier: "recaply-ready-\(UUID().uuidString)"
        )
    }

    func notifyFailed(title: String) async {
        await notify(
            title: "Recap needs attention",
            body: "\(title) was saved, but Recaply could not finish processing.",
            identifier: "recaply-failed-\(UUID().uuidString)"
        )
    }

    private func notify(title: String, body: String, identifier: String) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await center.add(request)
    }
}
