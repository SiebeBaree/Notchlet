import Foundation

/// The subscription a provider reports, with its list price in dollars a
/// month when the name maps to one. Team, enterprise and free tiers have a
/// name but no price, so the share image never guesses what they cost.
nonisolated struct UsagePlan: Equatable, Sendable {
    let name: String
    let monthlyPrice: Double?

    /// Claude Code's credentials carry `subscriptionType` ("pro", "max")
    /// and, on Max, `rateLimitTier` ("default_claude_max_20x").
    static func claude(subscriptionType: String?, rateLimitTier: String?) -> UsagePlan? {
        if let rateLimitTier {
            if rateLimitTier.hasSuffix("max_20x") {
                return UsagePlan(name: "Claude Max 20x", monthlyPrice: 200)
            }
            if rateLimitTier.hasSuffix("max_5x") {
                return UsagePlan(name: "Claude Max 5x", monthlyPrice: 100)
            }
        }
        switch subscriptionType {
        case "pro": return UsagePlan(name: "Claude Pro", monthlyPrice: 20)
        case "max": return UsagePlan(name: "Claude Max", monthlyPrice: nil)
        case "team": return UsagePlan(name: "Claude Team", monthlyPrice: nil)
        case "enterprise": return UsagePlan(name: "Claude Enterprise", monthlyPrice: nil)
        default: return nil
        }
    }

    /// The `plan_type` in Codex's usage response. Go's price differs per
    /// country, so it stays unpriced.
    static func chatGPT(planType: String?) -> UsagePlan? {
        switch planType {
        case "plus": UsagePlan(name: "ChatGPT Plus", monthlyPrice: 20)
        case "pro": UsagePlan(name: "ChatGPT Pro", monthlyPrice: 200)
        case "go": UsagePlan(name: "ChatGPT Go", monthlyPrice: nil)
        case "free": UsagePlan(name: "ChatGPT Free", monthlyPrice: nil)
        case "team": UsagePlan(name: "ChatGPT Team", monthlyPrice: nil)
        case "business": UsagePlan(name: "ChatGPT Business", monthlyPrice: nil)
        case "enterprise": UsagePlan(name: "ChatGPT Enterprise", monthlyPrice: nil)
        case "edu": UsagePlan(name: "ChatGPT Edu", monthlyPrice: nil)
        default: nil
        }
    }

    /// The `membershipType` in Cursor's usage response.
    static func cursor(membershipType: String?) -> UsagePlan? {
        switch membershipType?.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "pro": UsagePlan(name: "Cursor Pro", monthlyPrice: 20)
        case "pro_plus", "proplus": UsagePlan(name: "Cursor Pro+", monthlyPrice: 60)
        case "ultra": UsagePlan(name: "Cursor Ultra", monthlyPrice: 200)
        case "free", "free_trial": UsagePlan(name: "Cursor Free", monthlyPrice: nil)
        case "team", "teams": UsagePlan(name: "Cursor Teams", monthlyPrice: nil)
        case "enterprise": UsagePlan(name: "Cursor Enterprise", monthlyPrice: nil)
        default: nil
        }
    }
}
