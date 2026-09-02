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

    @Test func storedValueRoundTrips() {
        #expect(AuthSelection(storedValue: "key", options: options) == .option("key"))
        #expect(AuthSelection(storedValue: "auto", options: options) == .auto)
        #expect(AuthSelection(storedValue: nil, options: options) == .auto)
        #expect(AuthSelection.option("key").storedValue == "key")
    }

    @Test func unknownStoredOptionFallsBackToAuto() {
        #expect(AuthSelection(storedValue: "browser", options: options) == .auto)
    }

    @Test func moreSpecificProblemWins() {
        #expect(max(AuthProblem.signedOut, .expired) == .expired)
        #expect(max(AuthProblem.expired, .rejected) == .rejected)
        #expect(max(AuthProblem.rejected, .signedOut) == .rejected)
    }
}
