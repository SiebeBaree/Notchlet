import Foundation
@testable import Notchlet
import Testing

struct UsagePlanTests {
    @Test func claudePlanComesFromTheCredentials() throws {
        let json = Data("""
        {"claudeAiOauth": {"accessToken": "a", "refreshToken": "r", "expiresAt": 1790000000000,
         "scopes": ["user:inference"], "subscriptionType": "max", "rateLimitTier": "default_claude_max_20x"}}
        """.utf8)
        let credentials = try #require(ClaudeTokenRefresh.Credentials(json: json))
        #expect(credentials.plan == UsagePlan(name: "Claude Max 20x", monthlyPrice: 200))
        #expect(UsagePlan.claude(subscriptionType: "max", rateLimitTier: "default_claude_max_5x")?.monthlyPrice == 100)
        #expect(UsagePlan.claude(subscriptionType: "pro", rateLimitTier: nil) == UsagePlan(
            name: "Claude Pro",
            monthlyPrice: 20
        ))
        // A Max tier the table does not know is named but never priced.
        #expect(UsagePlan.claude(subscriptionType: "max", rateLimitTier: "default_claude_max_1x")?.monthlyPrice == nil)
        #expect(UsagePlan.claude(subscriptionType: nil, rateLimitTier: nil) == nil)
    }

    @Test func codexPlanComesFromTheResponse() {
        let data = Data(#"{"plan_type": "plus", "rate_limit": null}"#.utf8)
        #expect(CodexUsageProvider().plan(from: data) == UsagePlan(name: "ChatGPT Plus", monthlyPrice: 20))
        #expect(UsagePlan.chatGPT(planType: "pro")?.monthlyPrice == 200)
        #expect(UsagePlan.chatGPT(planType: "go")?.monthlyPrice == nil)
        #expect(UsagePlan.chatGPT(planType: "team")?.monthlyPrice == nil)
        #expect(CodexUsageProvider().plan(from: Data("{}".utf8)) == nil)
    }

    @Test func cursorPlanComesFromTheResponse() {
        let data = Data(#"{"membershipType": "pro", "individualUsage": {}}"#.utf8)
        #expect(CursorUsageProvider().plan(from: data) == UsagePlan(name: "Cursor Pro", monthlyPrice: 20))
        #expect(UsagePlan.cursor(membershipType: "pro_plus")?.monthlyPrice == 60)
        #expect(UsagePlan.cursor(membershipType: "ultra")?.monthlyPrice == 200)
        #expect(UsagePlan.cursor(membershipType: "enterprise")?.monthlyPrice == nil)
        #expect(UsagePlan.cursor(membershipType: nil) == nil)
    }
}
