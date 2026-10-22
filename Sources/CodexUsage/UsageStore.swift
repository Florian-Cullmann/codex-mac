import AppKit
import CodexUsageCore
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    static let refreshInterval: TimeInterval = 15
    @Published var snapshot: UsageSnapshot?
    @Published var isLoading = false
    @Published var error: String?
    @Published var notificationIssue: String?
    var onChange: (() -> Void)?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private let notifications = UsageNotifications()
    let isDemo: Bool

    init(demo: Bool = false) {
        isDemo = demo && !CommandLine.arguments.contains("--live")
        if demo { snapshot = Self.example }
    }

    var stale: Bool { error != nil || snapshot.map { Date().timeIntervalSince($0.fetchedAt) > 180 } == true }
    var menuTitle: String {
        guard !stale, let snapshot else { return "—%" }
        return snapshot.menuTitle
    }

    func start() {
        guard !isDemo else { return }
        notifications.onIssue = { [weak self] in self?.notificationIssue = $0 }
        notifications.start { [weak self] in
            if CommandLine.arguments.contains("--test-reset-notification") {
                self?.testResetNotification()
            }
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 1
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    private func testResetNotification() {
        let json = """
        {"planType":"plus","primary":{"usedPercent":0,"windowDurationMins":300},"secondary":{"usedPercent":0,"windowDurationMins":10080}}
        """
        let full = UsageSnapshot(limits: try! JSONDecoder().decode(RateLimits.self, from: Data(json.utf8)), accountPlan: "plus")
        notifications.notify(refilledLimits: full.refilledLimits(since: Self.example), isTest: true)
    }

    func refresh() {
        guard !isLoading, !isDemo else { return }
        isLoading = true
        onChange?()
        let path = UserDefaults.standard.string(forKey: "codexPath")
        Task {
            do {
                let fresh = try await Task.detached(priority: .utility) {
                    guard let executable = CodexLocator.executable(customPath: path) else { throw UsageError.missingCLI }
                    return try CodexClient(executable: executable).fetch()
                }.value
                let refilledLimits = fresh.refilledLimits(since: snapshot)
                snapshot = fresh
                error = nil
                notifications.notify(refilledLimits: refilledLimits)
            } catch {
                if let usageError = error as? UsageError {
                    // Old account data must not survive logout or switching accounts.
                    switch usageError {
                    case .signedOut, .unsupportedAccount, .noLimits: snapshot = nil
                    default: break
                    }
                    self.error = usageError.localizedDescription
                } else {
                    self.error = UsageError.server.localizedDescription
                }
            }
            isLoading = false
            onChange?()
        }
    }

    func openCodex() {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
            ?? URL(fileURLWithPath: "/Applications/Codex.app")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else {
            NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex")!)
        }
    }

    static var example: UsageSnapshot {
        let json = """
        {"planType":"plus","primary":{"usedPercent":55,"windowDurationMins":300,"resetsAt":\(Date().addingTimeInterval(7800).timeIntervalSince1970)},"secondary":{"usedPercent":16,"windowDurationMins":10080,"resetsAt":\(Date().addingTimeInterval(280000).timeIntervalSince1970)}}
        """
        return UsageSnapshot(limits: try! JSONDecoder().decode(RateLimits.self, from: Data(json.utf8)), accountPlan: "plus")
    }
}
