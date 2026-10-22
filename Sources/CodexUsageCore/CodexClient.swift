import Foundation
import Darwin

public enum UsageError: LocalizedError {
    case missingCLI, signedOut, unsupportedAccount, noLimits, timeout, disconnected, protocolError, server

    public var errorDescription: String? {
        switch self {
        case .missingCLI: return "Codex wurde nicht gefunden. Installiere die Codex-App oder wähle die Codex-CLI in den Einstellungen."
        case .signedOut: return "Melde dich in Codex mit deinem ChatGPT-Konto an und aktualisiere anschließend die Anzeige."
        case .unsupportedAccount: return "Nutzungslimits sind nur mit einer ChatGPT-Anmeldung verfügbar. Bitte melde dich in Codex mit ChatGPT an."
        case .noLimits: return "Für dieses Konto wurden keine passenden Codex-Nutzungslimits übermittelt."
        case .timeout: return "Codex antwortet gerade nicht. Die Verbindung wird automatisch erneut versucht."
        case .disconnected: return "Die Verbindung zu Codex wurde unterbrochen. Bitte versuche es erneut."
        case .protocolError: return "Die Codex-Antwort konnte nicht gelesen werden. Aktualisiere bitte Codex."
        case .server: return "Die Nutzung konnte nicht abgerufen werden. Prüfe deine Internetverbindung und die Anmeldung in Codex."
        }
    }
}

public enum CodexLocator {
    public static func executable(customPath: String? = nil) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [customPath].compactMap { $0 }.filter { !$0.isEmpty }
        candidates += [
            "/Applications/Codex.app/Contents/Resources/codex",
            home + "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex", home + "/.local/bin/codex"
        ]
        candidates += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/codex" }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }
}

/// A short-lived stdio connection. It reads account data only; no thread or model turn is created.
public struct CodexClient: Sendable {
    public let executable: URL
    public let timeout: TimeInterval

    public init(executable: URL, timeout: TimeInterval = 25) {
        self.executable = executable
        self.timeout = timeout
    }

    public func fetch() throws -> UsageSnapshot {
        let session = try RPCSession(executable: executable, timeout: timeout)
        defer { session.close() }
        _ = try session.request(id: 1, method: "initialize", params: [
            "clientInfo": ["name": "codex_usage", "title": "Codex Usage", "version": "1.0.0"]
        ])
        try session.send(["method": "initialized"])
        let accountData = try session.request(id: 2, method: "account/read", params: ["refreshToken": false])
        let accountResponse = try JSONDecoder().decode(AccountResponse.self, from: accountData)
        guard let account = accountResponse.account else { throw UsageError.signedOut }
        guard account.type == "chatgpt" || account.type == "chatgptAuthTokens" else { throw UsageError.unsupportedAccount }
        let data = try session.request(id: 3, method: "account/rateLimits/read", params: [:])
        let response = try JSONDecoder().decode(LimitsResponse.self, from: data)
        guard let limits = response.codex else { throw UsageError.noLimits }
        let snapshot = UsageSnapshot(limits: limits, accountPlan: account.planType)
        guard snapshot.weekly != nil || snapshot.fiveHour != nil else { throw UsageError.noLimits }
        return snapshot
    }
}

private struct AccountResponse: Decodable {
    struct Account: Decodable { let type: String; let planType: String? }
    let account: Account?
}

private final class RPCSession {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private let deadline: Date
    private let watchdog: DispatchSourceTimer

    init(executable: URL, timeout: TimeInterval) throws {
        deadline = Date().addingTimeInterval(timeout)
        watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        do { try process.run() } catch {
            watchdog.cancel()
            watchdog.resume()
            throw error
        }
        // Only this owned child can be killed. No other Codex process is touched.
        let child = process
        watchdog.setEventHandler {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
        watchdog.schedule(deadline: .now() + timeout)
        watchdog.resume()
    }

    func close() {
        watchdog.cancel()
        try? input.fileHandleForWriting.close()
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }

    func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func request(id: Int, method: String, params: [String: Any]) throws -> Data {
        try send(["id": id, "method": method, "params": params])
        while true {
            if Date() >= deadline { throw UsageError.timeout }
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                guard !line.isEmpty else { continue }
                guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw UsageError.protocolError }
                guard let responseID = message["id"] as? Int, responseID == id else { continue }
                if message["error"] != nil { throw UsageError.server }
                guard let result = message["result"], JSONSerialization.isValidJSONObject(result) else { throw UsageError.protocolError }
                return try JSONSerialization.data(withJSONObject: result)
            }
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { throw Date() >= deadline ? UsageError.timeout : UsageError.disconnected }
            buffer.append(chunk)
            if buffer.count > 4 * 1024 * 1024 { throw UsageError.protocolError }
        }
    }
}
