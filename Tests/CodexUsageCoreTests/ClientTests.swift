import XCTest
@testable import CodexUsageCore

final class ClientTests: XCTestCase {
    private func withServer(_ script: String, test: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("codex")
        try Data(("#!/bin/sh\n" + script).utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        try test(url)
    }

    func testRealStdioHandshakeAndNotificationHandling() throws {
        try withServer("""
        read -r line
        echo "$line" | /usr/bin/grep -q 'initialize' || exit 1
        printf '%s\\n' '{"id":1,"result":{}}'
        read -r line
        echo "$line" | /usr/bin/grep -q 'initialized' || exit 1
        read -r line
        printf '%s\\n' '{"method":"account/updated","params":{}}' '{"id":2,"result":{"account":{"type":"chatgpt","planType":"plus"}}}'
        read -r line
        printf '%s\\n' '{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":55,"windowDurationMins":300},"secondary":{"usedPercent":16,"windowDurationMins":10080}}}}'
        """) { url in
            let snapshot = try CodexClient(executable: url, timeout: 3).fetch()
            XCTAssertEqual(snapshot.menuTitle, "84% WL / 45% 5h")
            XCTAssertEqual(snapshot.weekly?.remaining, 84)
        }
    }

    func testSignedOutIsReportedClearly() throws {
        try withServer("""
        read -r line
        printf '%s\\n' '{"id":1,"result":{}}'
        read -r line
        read -r line
        printf '%s\\n' '{"id":2,"result":{"account":null}}'
        """) { url in
            XCTAssertThrowsError(try CodexClient(executable: url, timeout: 3).fetch()) { error in
                guard case UsageError.signedOut = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }

    func testHungServerIsKilledByDeadline() throws {
        try withServer("exec /bin/sleep 10\n") { url in
            let start = Date()
            XCTAssertThrowsError(try CodexClient(executable: url, timeout: 0.2).fetch()) { error in
                guard case UsageError.timeout = error else { return XCTFail("Unexpected error: \(error)") }
            }
            XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        }
    }

    func testServerErrorIsNotShownAsZeroUsage() throws {
        try withServer("read -r line\nprintf '%s\\n' '{\"id\":1,\"error\":{\"code\":-1,\"message\":\"private server error\"}}'\n") { url in
            XCTAssertThrowsError(try CodexClient(executable: url).fetch()) { error in
                guard case UsageError.server = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }

    func testMissingExecutableDoesNotCrash() {
        XCTAssertThrowsError(try CodexClient(executable: URL(fileURLWithPath: "/nonexistent/codex")).fetch())
    }
}
