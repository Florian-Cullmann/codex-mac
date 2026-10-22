import XCTest
@testable import CodexUsageCore

final class UsageTests: XCTestCase {
    private func snapshot(plan: String = "plus", primary: String = "{\"usedPercent\":55,\"windowDurationMins\":300}", secondary: String = "{\"usedPercent\":16,\"windowDurationMins\":10080}") throws -> UsageSnapshot {
        let json = "{\"planType\":\"\(plan)\",\"primary\":\(primary),\"secondary\":\(secondary)}"
        return UsageSnapshot(limits: try JSONDecoder().decode(RateLimits.self, from: Data(json.utf8)), accountPlan: nil)
    }

    func testPlusShowsBothWindowsAndRemainingInsteadOfUsed() throws {
        let usage = try snapshot()
        XCTAssertEqual(usage.fiveHour?.remaining, 45)
        XCTAssertEqual(usage.weekly?.remaining, 84)
        XCTAssertEqual(usage.menuTitle, "84% WL / 45% 5h")
    }

    func testFiveHourWindowIsExclusiveToPlus() throws {
        for plan in ["pro", "prolite", "free", "team", "business", "enterprise", "unknown"] {
            let usage = try snapshot(plan: plan)
            XCTAssertNil(usage.fiveHour, plan)
            XCTAssertEqual(usage.menuTitle, "84%", plan)
        }
    }

    func testWeeklyWindowCanBePrimaryAndSecondaryCanBeNull() throws {
        let usage = try snapshot(plan: "prolite", primary: "{\"usedPercent\":50,\"windowDurationMins\":10080,\"resetsAt\":1789808892}", secondary: "null")
        XCTAssertEqual(usage.weekly?.remaining, 50)
        XCTAssertEqual(usage.weekly?.resetDate, Date(timeIntervalSince1970: 1789808892))
        XCTAssertNil(usage.fiveHour)
    }

    func testUnknownWindowIsNotMislabelledAsWeekly() throws {
        let usage = try snapshot(primary: "{\"usedPercent\":25,\"windowDurationMins\":15}", secondary: "null")
        XCTAssertNil(usage.weekly)
        XCTAssertNil(usage.fiveHour)
        XCTAssertEqual(usage.menuTitle, "—% WL / —% 5h")
    }

    func testPercentClampingAndConservativeRounding() {
        for (used, remaining) in [(-1.0, 100), (101.0, 0), (54.2, 45), (100.0, 0), (0.0, 100)] {
            XCTAssertEqual(RateWindow(usedPercent: used, windowDurationMins: nil, resetsAt: nil).remaining, remaining)
        }
    }

    func testCodexBucketPreferredOverOtherLimits() throws {
        let data = Data("""
        {"rateLimits":{"limitId":"codex_other","primary":{"usedPercent":99}},
         "rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":20,"windowDurationMins":10080}}}}
        """.utf8)
        let response = try JSONDecoder().decode(LimitsResponse.self, from: data)
        XCTAssertEqual(response.codex?.primary?.remaining, 80)
    }

    func testOtherBucketIsNeverUsedAsCodex() throws {
        let response = try JSONDecoder().decode(LimitsResponse.self, from: Data("{\"rateLimits\":{\"limitId\":\"codex_other\"}}".utf8))
        XCTAssertNil(response.codex)
    }

    func testAccountPlanFallback() throws {
        let limits = try JSONDecoder().decode(RateLimits.self, from: Data("{\"primary\":{\"usedPercent\":25,\"windowDurationMins\":300}}".utf8))
        XCTAssertEqual(UsageSnapshot(limits: limits, accountPlan: "plus").fiveHour?.remaining, 75)
        XCTAssertNil(UsageSnapshot(limits: limits, accountPlan: nil).fiveHour)
    }

    func testRefillNotificationsFollowTransitionsWithoutRepeating() throws {
        let used = try snapshot()
        let full = try snapshot(primary: "{\"usedPercent\":0,\"windowDurationMins\":300}",
                                secondary: "{\"usedPercent\":0,\"windowDurationMins\":10080}")
        XCTAssertEqual(full.refilledLimits(since: used), ["Wochenlimit", "5-Stunden-Limit"])
        XCTAssertEqual(full.refilledLimits(since: full), [])
        XCTAssertEqual(full.refilledLimits(since: nil), [])
        XCTAssertEqual(used.refilledLimits(since: full), [])
        XCTAssertEqual(full.refilledLimits(since: used), ["Wochenlimit", "5-Stunden-Limit"])
    }

    func testIndependentRefillsAndConservativeRounding() throws {
        let used = try snapshot()
        let weeklyFull = try snapshot(secondary: "{\"usedPercent\":0,\"windowDurationMins\":10080}")
        let fiveHourFull = try snapshot(primary: "{\"usedPercent\":0,\"windowDurationMins\":300}")
        let nearlyFull = try snapshot(primary: "{\"usedPercent\":0.01,\"windowDurationMins\":300}",
                                      secondary: "{\"usedPercent\":0.01,\"windowDurationMins\":10080}")
        XCTAssertEqual(weeklyFull.refilledLimits(since: used), ["Wochenlimit"])
        XCTAssertEqual(fiveHourFull.refilledLimits(since: used), ["5-Stunden-Limit"])
        XCTAssertEqual(nearlyFull.refilledLimits(since: used), [])
    }

    func testMissingWindowsAndPlanChangesDoNotTriggerRefill() throws {
        let missing = try snapshot(primary: "null", secondary: "null")
        let full = try snapshot(primary: "{\"usedPercent\":0,\"windowDurationMins\":300}",
                                secondary: "{\"usedPercent\":0,\"windowDurationMins\":10080}")
        XCTAssertEqual(full.refilledLimits(since: missing), [])
        XCTAssertEqual(missing.refilledLimits(since: try snapshot()), [])
        XCTAssertEqual(full.refilledLimits(since: try snapshot(plan: "pro")), [])
        let proFull = try snapshot(plan: "pro", secondary: "{\"usedPercent\":0,\"windowDurationMins\":10080}")
        XCTAssertEqual(proFull.refilledLimits(since: try snapshot(plan: "pro")), ["Wochenlimit"])
    }
}
