import AppKit
import UserNotifications

/// This app's own notifications for Code sessions. Each names its profile,
/// and a click opens the session in that profile. Claude's notifications
/// all come from one bundle id, so macOS may hand their click to whichever
/// profile it picks.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: ((_ profileID: String, _ sessionID: String) -> Void)?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Whether macOS lets this app's notifications through.
    func checkPermission(_ done: @escaping @MainActor (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = [.authorized, .provisional].contains(settings.authorizationStatus)
            Task { @MainActor in done(allowed) }
        }
    }

    /// The Notifications page of System Settings for one app.
    static func openSettings(for bundleID: String) {
        let page = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        if let url = URL(string: "\(page)?id=\(bundleID)") ?? URL(string: page) { NSWorkspace.shared.open(url) }
    }

    func post(_ event: SessionWatcher.Event, profile: Profile) {
        let content = UNMutableNotificationContent()
        content.title = event.session.title
        content.subtitle = profile.name
        switch event.kind {
        case .finished: content.body = "Claude finished. Click to open it in \(profile.name)."
        case .asking: content.body = "Claude has a question for you in \(profile.name)."
        }
        content.sound = .default
        content.threadIdentifier = event.session.id
        content.userInfo = ["profile": profile.id, "session": event.session.id]
        // One notification per session: a newer one replaces it.
        let request = UNNotificationRequest(identifier: event.session.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let profile = info["profile"] as? String, let session = info["session"] as? String {
            Task { @MainActor in self.onOpen?(profile, session) }
        }
        completionHandler()
    }
}
