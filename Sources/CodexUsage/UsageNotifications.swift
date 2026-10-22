import Foundation
import UserNotifications

@MainActor
final class UsageNotifications: NSObject, UNUserNotificationCenterDelegate {
    private var center: UNUserNotificationCenter?
    var onIssue: ((String?) -> Void)?

    func start(onAuthorized: (() -> Void)? = nil) {
        // UserNotifications requires an app bundle; keep CLI/demo invocations usable.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        self.center = center
        center.delegate = self
        Task {
            do {
                let allowed = try await center.requestAuthorization(options: [.alert, .sound])
                onIssue?(allowed ? nil : "Für Reset-Hinweise bitte Mitteilungen und Töne für Codex Usage in den macOS-Systemeinstellungen erlauben.")
                if allowed { onAuthorized?() }
                if !allowed { fputs("Mitteilungen sind in macOS nicht erlaubt.\n", stderr) }
            } catch {
                onIssue?("Mitteilungen konnten nicht aktiviert werden: \(error.localizedDescription)")
            }
        }
    }

    func notify(refilledLimits: [String], isTest: Bool = false) {
        guard let center, !refilledLimits.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "Codex Reset: 100% verfügbar"
        if isTest { content.subtitle = "Test-Mitteilung" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy 'um' HH:mm"
        content.body = "Reset erkannt am \(formatter.string(from: Date()))."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task {
            do {
                try await center.add(request)
                if isTest {
                    FileHandle.standardOutput.write(Data("Test-Reset erkannt; Mitteilung mit Ton an macOS übergeben.\n".utf8))
                }
            } catch {
                fputs("Reset-Mitteilung fehlgeschlagen: \(error.localizedDescription)\n", stderr)
                onIssue?("Reset-Mitteilung konnte nicht gesendet werden: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
