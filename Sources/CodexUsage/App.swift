import AppKit
import SwiftUI
import ServiceManagement
import CodexUsageCore

@main
struct CodexUsageApp {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--enable-login") {
            do {
                try SMAppService.mainApp.register()
                guard SMAppService.mainApp.status == .enabled else {
                    fputs("Autostart benötigt Freigabe in den Systemeinstellungen.\n", stderr)
                    exit(1)
                }
                print("Autostart aktiviert")
            } catch {
                fputs("Autostart konnte nicht aktiviert werden: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        if CommandLine.arguments.contains("--check") {
            do {
                guard let executable = CodexLocator.executable(customPath: UserDefaults.standard.string(forKey: "codexPath")) else { throw UsageError.missingCLI }
                let snapshot = try CodexClient(executable: executable).fetch()
                print("Plan: \(snapshot.planLabel)")
                if let weekly = snapshot.weekly { print("Woche: \(weekly.remaining)% verbleibend") }
                if let fiveHour = snapshot.fiveHour { print("5 Stunden: \(fiveHour.remaining)% verbleibend") }
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let store = UsageStore(demo: CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--render-preview"))

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            if CommandLine.arguments.contains("--live") {
                do {
                    guard let executable = CodexLocator.executable() else { throw UsageError.missingCLI }
                    store.snapshot = try CodexClient(executable: executable).fetch()
                } catch {
                    store.snapshot = nil
                    store.error = error.localizedDescription
                }
            }
            renderPreview(to: CommandLine.arguments[index + 1])
            NSApplication.shared.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("Codex verbleibende Nutzung")
        }
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(rootView: UsagePopover(store: store))
        store.onChange = { [weak self] in self?.updateStatus() }
        updateStatus()
        store.start()
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.togglePopover() }
        }
    }

    private func updateStatus() {
        statusItem.button?.title = store.menuTitle
        statusItem.button?.toolTip = "Codex · \(store.menuTitle) verbleibend" + (store.snapshot?.plan == "plus" ? " · WL = Wochenlimit, 5h = 5-Stunden-Limit" : " · Wochenlimit")
        statusItem.button?.setAccessibilityValue(store.menuTitle)
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        store.refresh()
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func renderPreview(to path: String) {
        let view = NSHostingView(rootView: UsagePopover(store: store))
        view.appearance = NSAppearance(named: .darkAqua)
        let size = view.fittingSize
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
