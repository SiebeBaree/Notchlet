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

    static func scan(_ input: SecretScanInput, executable: URL? = Self.executable) async throws -> [SecretMatch] {
        guard let executable else { throw ScanError.unavailable }
        switch input {
        case let .files(urls):
            var results: [SecretMatch] = []
            for paths in fileBatches(urls) {
                try Task.checkCancellation()
                let report = try await run(executable, ["dir"] + paths + options, input: nil)
                results += try matches(from: report)
            }
            return results
        case let .text(data):
            let report = try await run(executable, ["stdin"] + options, input: data)
            return try matches(from: report)
        }
    }

    /// Stay below both Foundation's 4096-argument limit and macOS's
    /// argument byte limit, leaving room for options and the environment.
    static func fileBatches(_ urls: [URL]) -> [[String]] {
        var batches: [[String]] = []
        var batch: [String] = []
        var bytes = 0
        for url in urls {
            let path = url.path
            let size = path.utf8.count + 1
            if !batch.isEmpty, batch.count >= 256 || bytes + size > 128 * 1024 {
                batches.append(batch)
                batch = []
                bytes = 0
            }
            batch.append(path)
            bytes += size
        }
        if !batch.isEmpty {
            batches.append(batch)
        }
        return batches
    }

    private static let options: [String] = {
        var arguments = [
            "--no-banner", "--exit-code", "0", "--log-level", "error",
            "--report-format", "json", "--report-path", "-",
            "--confidence", confidence,
            "--max-target-megabytes", String(maxFileMegabytes),
            "--timeout", String(timeoutSeconds),
        ]
        for rule in disabledRules {
            arguments += ["--disable-rule", rule]
        }
        return arguments
    }()

    /// Line numbers are 1-based; the file is empty for piped input.
    static func matches(from report: Data) throws -> [SecretMatch] {
        // betterleaks writes null when a scan has no matches.
        let findings = try JSONDecoder().decode([Finding]?.self, from: report) ?? []
        return findings.map { finding in
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
