import Foundation

/// The betterleaks binary shipped next to the app binary;
/// `Scripts/fetch-betterleaks.sh` pins the version. Validation stays off:
/// the scanner never calls a vendor's API to test a key.
nonisolated enum Betterleaks {
    /// Nil without the vendored binary, and always on Intel: the helper
    /// ships as arm64 only.
    static let executable: URL? = {
        #if arch(x86_64)
            return nil
        #else
            guard let url = Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "betterleaks"),
                  FileManager.default.isExecutableFile(atPath: url.path)
            else { return nil }
            return url
        #endif
    }()

    static var isAvailable: Bool { executable != nil }

    /// Noise on real transcripts, or public by design: Brave's rule is a
    /// bare `BSA` prefix and matched random strings, the curl header rule
    /// matches placeholders like YOUR_TOKEN, IBM's matched an ordinary
    /// word, PostHog project keys are meant to be embedded client side, and
    /// base64-encoded JWTs cannot be checked for expiry. The false positive
    /// reports say what joins this list next.
    static let disabledRules = [
        "brave-search-api-key",
        "curl-auth-header",
        "ibm-cloud-user-api-key",
        "posthog-project-api-key",
        "jwt-base64",
    ]

    /// Lower confidence rules matched test fixtures far more than keys.
    private static let confidence = "high"
    private static let maxFileMegabytes = 256
    private static let timeoutSeconds = 600

    enum ScanError: Error {
        case unavailable
        case failed(status: Int32)
    }

    static func scan(_ input: SecretScanInput) async throws -> [SecretMatch] {
        guard let executable else { throw ScanError.unavailable }
        var arguments: [String]
        var stdin: Data?
        switch input {
        case let .files(urls):
            arguments = ["dir"] + urls.map(\.path)
        case let .text(data):
            arguments = ["stdin"]
            stdin = data
        }
        arguments += [
            "--no-banner", "--exit-code", "0", "--log-level", "error",
            "--report-format", "json", "--report-path", "-",
            "--confidence", confidence,
            "--max-target-megabytes", String(maxFileMegabytes),
            "--timeout", String(timeoutSeconds),
        ]
        for rule in disabledRules {
            arguments += ["--disable-rule", rule]
        }
        let report = try await run(executable, arguments, input: stdin)
        return try matches(from: report)
    }

    /// Line numbers are 1-based; the file is empty for piped input.
    static func matches(from report: Data) throws -> [SecretMatch] {
        try JSONDecoder().decode([Finding].self, from: report).map { finding in
            SecretMatch(
                ruleID: finding.ruleID,
                description: finding.description,
                secret: finding.secret,
                file: finding.file.isEmpty ? nil : URL(filePath: finding.file),
                line: finding.startLine
            )
        }
    }

    private struct Finding: Decodable {
        var ruleID: String
        var description: String
        var secret: String
        var startLine: Int
        var file: String

        enum CodingKeys: String, CodingKey {
            case ruleID = "RuleID"
            case description = "Description"
            case secret = "Secret"
            case startLine = "StartLine"
            case file = "File"
        }
    }

    /// The working directory is a temporary one so a `.betterleaks.toml`
    /// or ignore file of the user's never changes the rules, and the
    /// environment is minimal for the same reason.
    private static func run(_ executable: URL, _ arguments: [String], input: Data?) async throws -> Data {
        let exit = try await ChildProcess.run(
            executable,
            arguments,
            input: input,
            background: true,
            environment: ["HOME": FileManager.default.homeDirectoryForCurrentUser.path],
            currentDirectory: FileManager.default.temporaryDirectory
        )
        guard exit.status == 0 else { throw ScanError.failed(status: exit.status) }
        return exit.output
    }
}
