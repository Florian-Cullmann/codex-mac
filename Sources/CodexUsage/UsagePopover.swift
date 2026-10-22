import AppKit
import SwiftUI
import ServiceManagement
import CodexUsageCore

struct UsagePopover: View {
    @ObservedObject var store: UsageStore
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var settingsError: String?
    private let accent = Color(red: 0.35, green: 0.76, blue: 0.64)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text("VERBLEIBENDE NUTZUNG")
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1.25)
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isDemo { Text("DEMO").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange) }
            }
            .padding(.bottom, 18)

            HStack(alignment: .center) {
                HStack(spacing: 9) {
                    Image(systemName: "terminal").font(.system(size: 21, weight: .medium)).foregroundStyle(accent)
                    Text("Codex").font(.system(size: 24, weight: .semibold, design: .rounded))
                }
                Spacer()
                if let snapshot = store.snapshot {
                    Text(snapshot.planLabel).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(accent.opacity(0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(accent.opacity(0.18), lineWidth: 1))
                }
            }
            .padding(.bottom, 23)

            if let snapshot = store.snapshot {
                VStack(spacing: 22) {
                    if let fiveHour = snapshot.fiveHour {
                        windowRow(title: "5 Stunden", window: fiveHour)
                    }
                    if let weekly = snapshot.weekly {
                        windowRow(title: "Diese Woche", window: weekly)
                    }
                }
                .opacity(store.stale ? 0.5 : 1)
            } else if store.isLoading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Nutzung wird geladen …").font(.system(size: 13)).foregroundStyle(.secondary)
                }.padding(.vertical, 12)
            }

            if let error = store.error {
                VStack(alignment: .leading, spacing: 10) {
                    Label(store.snapshot == nil ? "Verbindung erforderlich" : "Werte nicht aktuell", systemImage: "exclamationmark.circle")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                    Text(error).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Codex öffnen", action: store.openCodex).font(.system(size: 12, weight: .medium))
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, store.snapshot == nil ? 0 : 18)
            }

            Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.top, 22).padding(.bottom, 13)
            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: UsageStore.refreshInterval)) { _ in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(updatedLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(store.snapshot?.plan == "plus" ? "WL = Woche · 5h = 5 Stunden" : "Wochenlimit in der Menüleiste")
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
                Button(action: store.refresh) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .disabled(store.isLoading).help("Jetzt aktualisieren")
                .accessibilityLabel("Nutzung aktualisieren")
                Menu {
                    Toggle("Beim Anmelden starten", isOn: Binding(get: { loginEnabled }, set: setLoginItem))
                    Button("Codex-CLI auswählen …", action: chooseCLI)
                    Button("Codex öffnen", action: store.openCodex)
                    Divider()
                    Button("Codex Usage beenden") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Image(systemName: "gearshape").font(.system(size: 13)).frame(width: 24, height: 26)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Einstellungen").accessibilityLabel("Einstellungen")
            }
            if let settingsError {
                Text(settingsError).font(.system(size: 11)).foregroundStyle(.orange).padding(.top, 10)
            }
            if let issue = store.notificationIssue {
                Text(issue).font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
        }
        .padding(22)
        .frame(width: 330)
        .background(Color(red: 0.115, green: 0.12, blue: 0.125))
        .environment(\.colorScheme, .dark)
    }

    private func windowRow(title: String, window: RateWindow) -> some View {
        let tint: Color = window.remaining <= 10 ? .red : window.remaining <= 25 ? Color(red: 1, green: 0.72, blue: 0.27) : accent
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.68))
                Spacer()
                Text("\(window.remaining)").font(.system(size: 25, weight: .medium, design: .rounded))
                    .monospacedDigit()
                + Text(" %").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.09))
                    Capsule().fill(tint).frame(width: geometry.size.width * Double(window.remaining) / 100)
                }
            }
            .frame(height: 7)
            .accessibilityLabel("\(title): \(window.remaining) Prozent verbleibend")
            if let date = window.resetDate {
                Text("Reset " + Self.resetFormatter.string(from: date))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text("Reset-Zeit nicht verfügbar").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var updatedLabel: String {
        if store.isLoading { return "Wird aktualisiert …" }
        guard let date = store.snapshot?.fetchedAt else { return "Automatisch alle \(Int(UsageStore.refreshInterval)) Sekunden" }
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        return minutes == 0 ? "Gerade aktualisiert" : "Vor \(minutes) Min. aktualisiert"
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEE, d. MMM · HH:mm"
        return formatter
    }()

    private func setLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
            settingsError = nil
        } catch {
            settingsError = "Autostart konnte nicht geändert werden. Starte die App aus dem Programme-Ordner."
        }
    }

    private func chooseCLI() {
        let panel = NSOpenPanel()
        panel.title = "Codex-CLI auswählen"
        panel.message = "Wähle die ausführbare Datei „codex“."
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                settingsError = "Bitte wähle eine ausführbare Codex-Datei."
                return
            }
            UserDefaults.standard.set(url.path, forKey: "codexPath")
            settingsError = nil
            store.refresh()
        }
    }
}
