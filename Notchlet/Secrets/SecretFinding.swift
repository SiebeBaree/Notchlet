import CryptoKit
import Foundation

/// One raw match as betterleaks reports it. The secret is here in full and
/// only here: `SecretFinding.merge` hashes and previews it and drops the
/// rest.
nonisolated struct SecretMatch: Equatable, Sendable {
    var ruleID: String
    var description: String
    var secret: String
    /// Nil for piped input.
    var file: URL?
    /// 1-based.
    var line: Int
}

/// One distinct secret, however many messages it turned up in. Keyed by a
/// hash of the secret, so a key pasted in forty chats is one finding and a
/// rescan of an unchanged file adds nothing. What is stored and shown is
/// the preview, never the secret.
nonisolated struct SecretFinding: Codable, Identifiable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending
        case ignored
        case falsePositive
    }

    struct Location: Codable, Hashable, Sendable {
        var file: String?
        var line: Int
    }

    /// First 16 hex characters of the secret's SHA-256.
    let id: String
    let ruleID: String
    /// What betterleaks thinks it is, e.g. "Stripe Access Token".
    let kind: String
    /// The first six and last two characters.
    let preview: String
    let length: Int
    let providerID: String
    /// The message text around the secret, with the secret replaced by the
    /// preview: the one line the pane shows.
    let context: String
    var locations: [Location]
    let firstSeenAt: Date
    var status: Status

    /// Enough to place a finding, not a log of every paste.
    static let maxLocations = 20

    /// Folds raw matches into the known findings for one provider. A match
    /// of a known secret adds a location and nothing else, whatever its
    /// status, so an ignored key stays ignored wherever it turns up again.
    /// `lineAt` reads the message a new secret sits in, for the context.
    static func merge(
        _ matches: [SecretMatch],
        into known: [SecretFinding],
        providerID: String,
        now: Date,
        lineAt: (SecretMatch) -> Data?
    ) -> (findings: [SecretFinding], new: Int) {
        var findings = known
        var index = Dictionary(findings.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Every secret betterleaks saw on a line, accepted or not, so none
        // of them can sit in another finding's context.
        let secretsByLine = Dictionary(grouping: matches, by: { Location(file: $0.file?.path, line: $0.line) })
            .mapValues { $0.map(\.secret) }
        var new = 0
        for match in matches where SecretPolicy.accepts(match, now: now) {
            let id = Self.id(of: match.secret)
            let location = Location(file: match.file?.path, line: match.line)
            if let existing = index[id] {
                if !findings[existing].locations.contains(location), findings[existing].locations.count < maxLocations {
                    findings[existing].locations.append(location)
                }
                continue
            }
            let preview = preview(of: match.secret)
            findings.append(SecretFinding(
                id: id,
                ruleID: match.ruleID,
                kind: kind(from: match.description),
                preview: preview,
                length: match.secret.count,
                providerID: providerID,
                context: lineAt(match).map {
                    context(around: match.secret, in: $0, preview: preview, masking: secretsByLine[location] ?? [])
                } ?? preview,
                locations: [location],
                firstSeenAt: now,
                status: .pending
            ))
            index[id] = findings.count - 1
            new += 1
        }
        return (findings, new)
    }

    static func id(of secret: String) -> String {
        SHA256.hash(data: Data(secret.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Enough to recognise your own key, useless to anyone else. A short
    /// secret shows only its head.
    static func preview(of secret: String) -> String {
        let characters = Array(secret)
        guard characters.count > 12 else { return String(characters.prefix(4)) + "…" }
        return String(characters.prefix(6)) + "…" + String(characters.suffix(2))
    }

    /// betterleaks describes a rule as "Found a Stripe Access Token, posing
    /// a risk to..." or "Detected an npm access token, which could...". The
    /// noun phrase is the label.
    static func kind(from description: String) -> String {
        var text = String(description.split(separator: ",", maxSplits: 1).first ?? "")
        for verb in ["Detected", "Identified", "Discovered", "Found", "Uncovered"] where text.hasPrefix(verb + " ") {
            text.removeFirst(verb.count + 1)
            for article in ["an ", "a ", "the "] where text.hasPrefix(article) {
                text.removeFirst(article.count)
                break
            }
            break
        }
        text = text.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return text.isEmpty ? "Unknown key" : text
    }

    /// Up to 40 bytes either side of the secret in a raw transcript line,
    /// JSON escapes undone and whitespace collapsed. Every occurrence of the
    /// secret becomes the preview first (a line can carry it twice), every
    /// other secret the scan found on the line is cut out, the window never
    /// cuts through a token, and any other long key-shaped run in the
    /// window is masked too, since an .env has neighbours the scanner may
    /// not know. Just the preview when the secret is not in the line as
    /// written (betterleaks also decodes base64 it finds).
    static func context(around secret: String, in line: Data, preview: String,
                        masking others: [String] = []) -> String
    {
        // A control byte stands in for the secret until the end, so a key
        // glued to another token never drags the preview into the masking.
        let sentinel = Data([0x01])
        var masked = line.replacing(Data(secret.utf8), with: sentinel)
        for other in others where other != secret {
            masked = masked.replacing(Data(other.utf8), with: Data("…".utf8))
        }
        guard let range = masked.range(of: sentinel) else { return preview }
        var start = max(masked.startIndex, range.lowerBound - contextReach)
        var end = min(masked.endIndex, range.upperBound + contextReach)
        var room = contextReach
        while start > masked.startIndex, room > 0, isTokenByte(masked[start - 1]) {
            start -= 1
            room -= 1
        }
        room = contextReach
        while end < masked.endIndex, room > 0, isTokenByte(masked[end]) {
            end += 1
            room -= 1
        }
        return maskOtherKeys(in: unescape(masked[start ..< end]))
            .replacing("\u{1}", with: preview)
            .trimmingCharacters(in: .whitespaces)
    }

    private static let contextReach = 40

    /// Letters, digits and what keys and base64 are made of.
    private static func isTokenByte(_ byte: UInt8) -> Bool {
        "_-+/=".utf8.contains(byte)
            || (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte)
            || (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(byte)
            || (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(byte)
    }

    /// Runs of twenty or more token characters mixing letters and digits
    /// keep their first four. Variable names have no digits and stay.
    private static func maskOtherKeys(in text: String) -> String {
        text.replacing(/[A-Za-z0-9_+\/=-]{20,}/) { match in
            let run = match.output
            guard run.contains(where: \.isNumber), run.contains(where: \.isLetter) else { return String(run) }
            return String(run.prefix(4)) + "…"
        }
    }

    private static func unescape(_ fragment: Data) -> String {
        String(decoding: fragment, as: UTF8.self)
            .replacing(/\\[ntr]/, with: " ")
            .replacing("\\\"", with: "\"")
            .replacing("\\/", with: "/")
            .replacing("\\\\", with: "\\")
            .replacing(/\s+/, with: " ")
    }
}

/// What betterleaks reports that is still not worth an alert.
nonisolated enum SecretPolicy {
    static func accepts(_ match: SecretMatch, now: Date) -> Bool {
        let secret = match.secret
        if secret.contains(/(?i)example|xxxx|your[_-]|placeholder|redacted|<[^>]*>|\.\.\./) {
            return false
        }
        // An environment variable name where a value should be.
        if secret.wholeMatch(of: /[A-Z0-9_]+/) != nil {
            return false
        }
        if match.ruleID == "jwt" {
            // Sessions and CI tokens expire within hours; only a token that
            // still works is a leak. One without an expiry is unknowable
            // and left alone.
            guard let expiry = CredentialSupport.jwtExpiry(of: secret) else { return false }
            return expiry > now
        }
        return true
    }
}

/// Reads the lines findings point at, once per file.
nonisolated enum SecretContext {
    /// The wanted lines of a file, 1-based, streamed in one pass.
    static func lines(_ wanted: Set<Int>, in url: URL) -> [Int: Data] {
        guard !wanted.isEmpty, let last = wanted.max() else { return [:] }
        var found: [Int: Data] = [:]
        var number = 0
        try? LineReader.forEachLine(in: url, from: 0) { line in
            number += 1
            if number <= last, wanted.contains(number) {
                found[number] = line
            }
        }
        return found
    }

    /// The wanted lines of piped text, 1-based.
    static func lines(_ wanted: Set<Int>, in text: Data) -> [Int: Data] {
        var found: [Int: Data] = [:]
        for (offset, line) in text.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).enumerated()
            where wanted.contains(offset + 1)
        {
            found[offset + 1] = Data(line)
        }
        return found
    }

    /// A line reader over the whole input for one merge: files are read
    /// once each, only for the lines with matches.
    static func reader(for input: SecretScanInput, matches: [SecretMatch]) -> (SecretMatch) -> Data? {
        var byFile: [String: [Int: Data]] = [:]
        switch input {
        case .files:
            let wanted = Dictionary(
                grouping: matches.compactMap { match in match.file.map { ($0, match.line) } },
                by: \.0
            )
            for (file, entries) in wanted {
                byFile[file.path] = lines(Set(entries.map(\.1)), in: file)
            }
        case let .text(data):
            byFile[""] = lines(Set(matches.map(\.line)), in: data)
        }
        return { match in byFile[match.file?.path ?? ""]?[match.line] }
    }
}
