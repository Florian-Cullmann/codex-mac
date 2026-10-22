import Foundation

public struct RateWindow: Decodable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: Double?

    public init(usedPercent: Double, windowDurationMins: Int?, resetsAt: Double?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

    public var remaining: Int { Int(max(0, min(100, 100 - usedPercent)).rounded(.down)) }
    public var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
}

public struct RateLimits: Decodable, Sendable {
    public let limitId: String?
    public let primary: RateWindow?
    public let secondary: RateWindow?
    public let planType: String?
}

public struct LimitsResponse: Decodable, Sendable {
    public let rateLimits: RateLimits?
    public let rateLimitsByLimitId: [String: RateLimits]?

    public var codex: RateLimits? {
        if let specific = rateLimitsByLimitId?["codex"] { return specific }
        guard let rateLimits, rateLimits.limitId == nil || rateLimits.limitId == "codex" else { return nil }
        return rateLimits
    }
}

public struct UsageSnapshot: Sendable {
    public let plan: String
    public let weekly: RateWindow?
    public let fiveHour: RateWindow?
    public let fetchedAt: Date

    public init(limits: RateLimits, accountPlan: String?, fetchedAt: Date = Date()) {
        plan = (limits.planType ?? accountPlan ?? "unknown").lowercased()
        let windows = [limits.primary, limits.secondary].compactMap { $0 }
        weekly = windows.first { $0.windowDurationMins == 10_080 }
        fiveHour = plan == "plus" ? windows.first { $0.windowDurationMins == 300 } : nil
        self.fetchedAt = fetchedAt
    }

    public var menuTitle: String {
        let weeklyText = weekly.map { "\($0.remaining)%" } ?? "—%"
        if plan == "plus" {
            let fiveHourText = fiveHour.map { "\($0.remaining)%" } ?? "—%"
            return "\(weeklyText) WL / \(fiveHourText) 5h"
        }
        return weeklyText
    }

    /// Only a confirmed transition from a known value below 100 counts as a refill.
    public func refilledLimits(since previous: UsageSnapshot?) -> [String] {
        guard let previous, previous.plan == plan else { return [] }
        return [("Wochenlimit", previous.weekly, weekly),
                ("5-Stunden-Limit", previous.fiveHour, fiveHour)].compactMap { name, old, new in
            guard let old, let new, old.remaining < 100, new.remaining == 100 else { return nil }
            return name
        }
    }

    public var planLabel: String {
        switch plan {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "prolite": return "Pro Lite"
        case "free": return "Free"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu": return "Edu"
        default: return "Codex"
        }
    }
}
