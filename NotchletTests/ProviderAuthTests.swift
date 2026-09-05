import Foundation
@testable import Notchlet
import Testing

struct ProviderAuthTests {
    private let options = [
        AuthOption(id: "cli", label: "CLI"),
        AuthOption(id: "key", label: "Pasted key", secretName: "API key"),
    ]

    @Test func autoTriesEveryOptionInOrder() {
        #expect(AuthSelection.auto.resolve(options).map(\.id) == ["cli", "key"])
    }

    @Test func explicitChoiceTriesOnlyThatOption() {
        #expect(AuthSelection.option("key").resolve(options).map(\.id) == ["key"])
    }

    @Test func rawValueRoundTrips() {
        #expect(AuthSelection(rawValue: "key") == .option("key"))
        #expect(AuthSelection(rawValue: "auto") == .auto)
        #expect(AuthSelection.option("key").rawValue == "key")
    }

    @Test func unknownOptionValidatesToAuto() {
        #expect(AuthSelection.option("browser").validated(against: options) == .auto)
        #expect(AuthSelection.option("key").validated(against: options) == .option("key"))
    }

    @Test func firstUsableAnswersFromTheFirstOptionThatWorks() async throws {
        let answer = try await AuthSelection.auto.firstUsable(options) { option in
            if option.id == "cli" {
                throw ProviderError.notAvailable(.signedOut)
            }
            return option.id
        }
        #expect(answer == "key")
    }

    @Test func firstUsableReportsTheMostSpecificProblem() async {
        await #expect(throws: ProviderError.self) {
            try await AuthSelection.auto.firstUsable(options) { option in
                throw ProviderError.notAvailable(option.id == "cli" ? .expired : .signedOut)
            }
        }
        do {
            _ = try await AuthSelection.auto.firstUsable(options) { option in
                throw ProviderError.notAvailable(option.id == "cli" ? .expired : .signedOut)
            }
        } catch let ProviderError.notAvailable(problem) {
            #expect(problem == .expired)
        } catch {
            Issue.record("Expected notAvailable, got \(error)")
        }
    }

    @Test func firstUsableStopsOnAnyOtherError() async {
        var tried: [String] = []
        await #expect(throws: ProviderError.self) {
            try await AuthSelection.auto.firstUsable(options) { option in
                tried.append(option.id)
                throw ProviderError.requestFailed
            }
        }
        #expect(tried == ["cli"])
    }

    @Test func moreSpecificProblemWins() {
        #expect(max(AuthProblem.signedOut, .expired) == .expired)
        #expect(max(AuthProblem.expired, .rejected) == .rejected)
        #expect(max(AuthProblem.rejected, .signedOut) == .rejected)
    }
}
