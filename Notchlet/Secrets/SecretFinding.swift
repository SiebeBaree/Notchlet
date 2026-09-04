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
/// the preview, never the secret and never the chat around it.
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
    var locations: [Location]
    let firstSeenAt: Date
    var status: Status

    /// Enough to place a finding, not a log of every paste.
    static let maxLocations = 20

    /// Folds raw matches into the known findings for one provider. A match
    /// of a known secret adds a location and nothing else, whatever its
    /// status, so an ignored key stays ignored wherever it turns up again.
    static func merge(
        _ matches: [SecretMatch],
        into known: [SecretFinding],
        providerID: String,
        now: Date
    ) -> (findings: [SecretFinding], new: Int) {
        var findings = known
        var index = Dictionary(findings.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
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
            findings.append(SecretFinding(
                id: id,
                ruleID: match.ruleID,
                kind: kind(from: match.description),
                preview: preview(of: match.secret),
                length: match.secret.count,
                providerID: providerID,
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
