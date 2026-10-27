import AppKit
import Combine
@preconcurrency import UserNotifications

@MainActor
final class NotificationController: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var status = "Notification reminders are optional."
    var onAutomatic: (() -> Void)?
    var onOpenRelease: (() -> Void)?
    var onError: ((Int) -> Void)?
    private var presentationIdentifier: String?

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let automatic = UNNotificationAction(identifier: "automatic", title: "Return to Automatic", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "presentation", actions: [automatic], intentIdentifiers: [])])
        Task {
            let pending = await center.pendingNotificationRequests()
            let stale = pending.map(\.identifier).filter { $0.hasPrefix("presentation-reminder") && $0 != self.presentationIdentifier }
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
    }

    func requestAccess() async -> Bool {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
            status = allowed ? "Notifications are enabled." : "Notifications are off. You can enable them in System Settings → Notifications."
            return allowed
        } catch { status = "Notifications could not be enabled."; onError?((error as NSError).code); return false }
    }

    func schedulePresentation(startedAt: Date?, minutes: Int, enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        if let old = presentationIdentifier {
            center.removePendingNotificationRequests(withIdentifiers: [old])
            center.removeDeliveredNotifications(withIdentifiers: [old])
        }
        presentationIdentifier = nil
        guard enabled, let startedAt else { return }
        let content = UNMutableNotificationContent()
        content.title = "Still presenting?"
        content.body = "Meeting Busy is hiding your indicator. Return to Automatic when your screen share is finished."
        content.categoryIdentifier = "presentation"
        let interval = max(1, startedAt.addingTimeInterval(Double(max(1, minutes)) * 60).timeIntervalSinceNow)
        let identifier = "presentation-reminder-" + UUID().uuidString
        presentationIdentifier = identifier
        let request = UNNotificationRequest(identifier: identifier, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        Task {
            do {
                try await center.add(request)
                if self.presentationIdentifier != identifier { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
            } catch { onError?((error as NSError).code) }
        }
    }

    func notifyUpdate(version: String) {
        guard UserDefaults.standard.string(forKey: "lastNotifiedVersion") != version else { return }
        let content = UNMutableNotificationContent()
        content.title = "Meeting Busy update available"
        content.body = "Version \(version) is available. Open the release page to review and download it."
        let request = UNNotificationRequest(identifier: "update-available", content: content, trigger: nil)
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                UserDefaults.standard.set(version, forKey: "lastNotifiedVersion")
            } catch { onError?((error as NSError).code) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let identifier = response.notification.request.identifier
        await MainActor.run {
            if identifier.hasPrefix("presentation-reminder"), action == "automatic" { onAutomatic?() }
            if identifier == "update-available", action == UNNotificationDefaultActionIdentifier { onOpenRelease?() }
        }
    }
}
