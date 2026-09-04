import Foundation
@testable import Notchlet
import Testing

struct SecretFindingTests {
    /// Two findings as betterleaks 1.8 reports them for `dir`, secrets and
    /// paths made up, fields the app ignores left in.
    private let report = """
    [
     {"RuleID":"stripe-access-token","Description":"Found a Stripe Access Token, posing a risk to payment processing services and sensitive financial data.","StartLine":181,"EndLine":181,"StartColumn":2995,"EndColumn":3020,"Match":"sk_demo_4eC39HqLyjWDarjtT1zdp7dc","Secret":"sk_demo_4eC39HqLyjWDarjtT1zdp7dc","Attributes":{"confidence":"high","path":"/Users/me/.claude/projects/-Users-me-umber/c06c.jsonl","resource":"fs.content"},"Tags":[],"Fingerprint":"/Users/me/.claude/projects/-Users-me-umber/c06c.jsonl:stripe-access-token:181","File":"/Users/me/.claude/projects/-Users-me-umber/c06c.jsonl","SymlinkFile":"","Commit":"","Entropy":4.1,"Author":"","Email":"","Date":"","Message":""},
     {"RuleID":"github-oauth","Description":"Discovered a GitHub OAuth Access Token, posing a risk of compromised GitHub account integrations and data leaks.","StartLine":3,"EndLine":3,"StartColumn":10,"EndColumn":50,"Match":"ghx_16C7e42F292c6912E7710c838347Ae178B4a","Secret":"ghx_16C7e42F292c6912E7710c838347Ae178B4a","Tags":[],"Fingerprint":"x","File":"","SymlinkFile":"","Commit":"","Entropy":3.9,"Author":"","Email":"","Date":"","Message":""}
    ]
    """

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func match(_ secret: String, rule: String = "stripe-access-token", line: Int = 1) -> SecretMatch {
        SecretMatch(
            ruleID: rule,
            description: "Found a Stripe Access Token, posing a risk.",
            secret: secret,
            file: URL(filePath: "/tmp/a.jsonl"),
            line: line
        )
    }

    @Test func decodesABetterleaksReport() throws {
        let matches = try Betterleaks.matches(from: Data(report.utf8))
        #expect(matches.count == 2)
        #expect(matches[0].ruleID == "stripe-access-token")
        #expect(matches[0].line == 181)
        #expect(matches[0].file?.path == "/Users/me/.claude/projects/-Users-me-umber/c06c.jsonl")
        #expect(matches[1].file == nil)
        #expect(try Betterleaks.matches(from: Data("[]".utf8)).isEmpty)
    }

    @Test func oneSecretIsOneFindingHoweverOftenItAppears() {
        let matches = [
            match("sk_demo_4eC39HqLyjWDarjtT1zdp7dc", line: 1),
            match("sk_demo_4eC39HqLyjWDarjtT1zdp7dc", line: 9),
            match("sk_demo_4eC39HqLyjWDarjtT1zdp7dc", line: 9),
            match("sk_demo_ZZC39HqLyjWDarjtT1zdp7dc", line: 2),
        ]
        let merged = SecretFinding.merge(matches, into: [], providerID: "claude-code", now: now) { _ in nil }
        #expect(merged.new == 2)
        #expect(merged.findings.count == 2)
        #expect(merged.findings[0].locations.map(\.line) == [1, 9])
        #expect(merged.findings[0].status == .pending)
        #expect(merged.findings[0].id == SecretFinding.id(of: "sk_demo_4eC39HqLyjWDarjtT1zdp7dc"))
        #expect(merged.findings[0].id.count == 16)
    }

    @Test func aKnownSecretKeepsItsStatusAndCountsAsNothingNew() {
        let first = SecretFinding.merge(
            [match("sk_demo_4eC39HqLyjWDarjtT1zdp7dc")],
            into: [],
            providerID: "p",
            now: now
        ) { _ in nil }
        var known = first.findings
        known[0].status = .ignored

        let again = SecretFinding.merge(
            [match("sk_demo_4eC39HqLyjWDarjtT1zdp7dc", line: 40)], into: known, providerID: "p", now: now
        ) { _ in nil }
        #expect(again.new == 0)
        #expect(again.findings[0].status == .ignored)
        #expect(again.findings[0].locations.map(\.line) == [1, 40])
    }

    @Test func previewShowsHeadAndTailOnly() {
        #expect(SecretFinding.preview(of: "sk_demo_4eC39HqLyjWDarjtT1zdp7dc") == "sk_dem…dc")
        #expect(SecretFinding.preview(of: "short-key") == "shor…")
        #expect(!SecretFinding.preview(of: "sk_demo_4eC39HqLyjWDarjtT1zdp7dc").contains("4eC39"))
    }

    @Test func kindIsTheNounPhraseOfTheDescription() {
        #expect(SecretFinding
            .kind(from: "Found a Stripe Access Token, posing a risk to payment processing.") == "Stripe Access Token")
        #expect(SecretFinding
            .kind(from: "Uncovered an npm access token, potentially compromising packages.") == "npm access token")
        #expect(SecretFinding
            .kind(
                from: "Identified an AWS access key ID paired with a secret access key, which together can provide full access."
            ) ==
            "AWS access key ID paired with a secret access key")
        #expect(SecretFinding.kind(from: "Zoho OAuth refresh token") == "Zoho OAuth refresh token")
        #expect(SecretFinding.kind(from: "") == "Unknown key")
    }

    @Test func contextIsTheMaskedLineAroundTheSecret() {
        let line = Data(#"{"type":"user","content":"$ cat .env\nSTRIPE_SECRET_KEY=sk_demo_4eC39HqLyjWDarjtT1zdp7dc\nSTRIPE_WEBHOOK_SECRET=whsek_abc\"quoted\""}"#
            .utf8)
        let context = SecretFinding.context(around: "sk_demo_4eC39HqLyjWDarjtT1zdp7dc", in: line, preview: "sk_dem…dc")
        // Newlines become spaces and escaped quotes come back as quotes.
        #expect(context.contains("$ cat .env STRIPE_SECRET_KEY=sk_dem…dc STRIPE_WEBHOOK_SECRET=whsek_abc\"quote"))
        #expect(!context.contains("4eC39"))
        #expect(!context.contains("\\"))
        #expect(SecretFinding.context(around: "missing", in: line, preview: "mi…") == "mi…")
    }

    @Test func contextMasksEveryOccurrenceAndTheNeighbours() {
        let line = Data(#"{"STRIPE_WEBHOOK_SECRET":"whsek_9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c","m":"sk_demo_4eC39HqLyjWDarjtT1zdp7dc","s":"sk_demo_4eC39HqLyjWDarjtT1zdp7dc"}"#
            .utf8)
        let context = SecretFinding.context(around: "sk_demo_4eC39HqLyjWDarjtT1zdp7dc", in: line, preview: "sk_dem…dc")
        #expect(context.components(separatedBy: "sk_dem…dc").count == 3)
        #expect(!context.contains("4eC39"))
        // The window cut into the webhook key, so it grew to the whole key and masked it.
        #expect(context.contains("whse…"))
        #expect(!context.contains("9f8e7d6c"))
        // A long name without digits is a variable, not a key.
        let named = Data("SOME_VERY_LONG_VARIABLE_NAME=sk_demo_4eC39HqLyjWDarjtT1zdp7dc".utf8)
        #expect(SecretFinding.context(around: "sk_demo_4eC39HqLyjWDarjtT1zdp7dc", in: named, preview: "sk_dem…dc")
            == "SOME_VERY_LONG_VARIABLE_NAME=sk_dem…dc")
        // Glued to another key, the preview keeps its head and the neighbour loses its own.
        let glued = Data("u5KYabcdef1234567890abcdefsk_demo_4eC39HqLyjWDarjtT1zdp7dc".utf8)
        #expect(SecretFinding.context(around: "sk_demo_4eC39HqLyjWDarjtT1zdp7dc", in: glued, preview: "sk_dem…dc")
            == "u5KY…sk_dem…dc")
    }

    @Test func otherSecretsOnTheLineAreCutOutWhateverTheirShape() {
        // A base64 neighbour with / and + in it, which the run heuristic alone would split.
        let other = "ab/cd+ef12/gh+ij34kl=="
        let line = Data("key=sk_demo_4eC39HqLyjWDarjtT1zdp7dc other=\(other) end".utf8)
        let context = SecretFinding.context(
            around: "sk_demo_4eC39HqLyjWDarjtT1zdp7dc", in: line, preview: "sk_dem…dc", masking: [other]
        )
        #expect(context == "key=sk_dem…dc other=… end")

        // Through merge, every match on the line masks the others.
        let matches = [
            SecretMatch(
                ruleID: "a",
                description: "Found a Key A, x.",
                secret: "sk_demo_4eC39HqLyjWDarjtT1zdp7dc",
                file: nil,
                line: 1
            ),
            SecretMatch(ruleID: "b", description: "Found a Key B, x.", secret: other, file: nil, line: 1),
        ]
        let merged = SecretFinding.merge(matches, into: [], providerID: "p", now: now) { _ in line }
        #expect(merged.findings.count == 2)
        #expect(!merged.findings[0].context.contains("cd+ef"))
        #expect(!merged.findings[1].context.contains("4eC39"))
        #expect(merged.findings[1].context.contains("ab/cd+…=="))
    }

    @Test func mergeReadsContextThroughTheLineReader() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "notchlet-secrets-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("first line\ntoken=sk_demo_4eC39HqLyjWDarjtT1zdp7dc here\nthird\n".utf8).write(to: file)
        var match = match("sk_demo_4eC39HqLyjWDarjtT1zdp7dc", line: 2)
        match.file = file

        let input = SecretScanInput.files([file])
        let merged = SecretFinding.merge(
            [match], into: [], providerID: "p", now: now,
            lineAt: SecretContext.reader(for: input, matches: [match])
        )
        #expect(merged.findings[0].context == "token=sk_dem…dc here")

        let piped = SecretContext.reader(for: .text(Data("a\nb=sk_demo_4eC39HqLyjWDarjtT1zdp7dc\n".utf8)), matches: [
            SecretMatch(ruleID: "r", description: "d", secret: "s", file: nil, line: 2),
        ])
        #expect(piped(SecretMatch(ruleID: "r", description: "d", secret: "s", file: nil, line: 2)) ==
            Data("b=sk_demo_4eC39HqLyjWDarjtT1zdp7dc".utf8))
    }

    @Test func placeholdersAndVariableNamesAreNotSecrets() {
        #expect(!SecretPolicy.accepts(match("sk_demo_YOUR_KEY_HERE_xxxxxxxx"), now: now))
        #expect(!SecretPolicy.accepts(match("sk_demo_example1234567890abcd"), now: now))
        #expect(!SecretPolicy.accepts(match("ACCESS_TOKEN"), now: now))
        #expect(!SecretPolicy.accepts(match("<your-token>"), now: now))
        #expect(SecretPolicy.accepts(match("sk_demo_4eC39HqLyjWDarjtT1zdp7dc"), now: now))
    }

    @Test func onlyAJWTThatStillWorksCounts() {
        func jwt(exp: Int?) -> String {
            let payload = exp.map { "{\"sub\":\"me\",\"exp\":\($0)}" } ?? "{\"sub\":\"me\"}"
            let body = Data(payload.utf8).base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
            return "eyJhbGciOiJIUzI1NiJ9.\(body).c2lnbmF0dXJl"
        }
        let live = Int(now.timeIntervalSince1970) + 3600
        let dead = Int(now.timeIntervalSince1970) - 3600
        #expect(SecretPolicy.accepts(match(jwt(exp: live), rule: "jwt"), now: now))
        #expect(!SecretPolicy.accepts(match(jwt(exp: dead), rule: "jwt"), now: now))
        #expect(!SecretPolicy.accepts(match(jwt(exp: nil), rule: "jwt"), now: now))
    }

    @Test func stateRoundTripsThroughTheStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "notchlet-secrets-\(UUID().uuidString)/findings.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SecretStateStore(url: url)
        #expect(store.load() == nil)

        var state = SecretScanState()
        state.findings = SecretFinding.merge(
            [match("sk_demo_4eC39HqLyjWDarjtT1zdp7dc")],
            into: [],
            providerID: "p",
            now: now
        ) { _ in nil }.findings
        state.lastScanAt["p"] = now
        try store.save(state)

        let loaded = try #require(store.load())
        #expect(loaded == state)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(!raw.contains("4eC39HqLyjWDarjtT1zdp7dc"))
        #expect(raw.contains("sk_dem…dc"))
    }

    @Test func paneTitleNamesTheProviderWhenThereIsOne() {
        #expect(SecretsPane.title(count: 1, providerName: "Claude") == "1 leaked secret in Claude chats")
        #expect(SecretsPane.title(count: 3, providerName: nil) == "3 leaked secrets in your chats")
    }
}
