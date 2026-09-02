import Foundation

/// The parts of a Claude Code token refresh that touch neither the keychain
/// nor the network: whether a stored token needs one, the request to send,
/// and how to fold the response back into the stored JSON. Mirrors what
/// Claude Code 2.1 does itself, so a token Notchlet refreshed is
/// indistinguishable from one Claude Code refreshed.
enum ClaudeTokenRefresh {
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    /// Claude Code's OAuth client. A refresh has to name the client the
    /// token was issued to, and Claude Code's storage only ever holds
    /// tokens for this one.
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// The `claudeAiOauth` object of Claude Code's credentials JSON, just
    /// the fields Notchlet reads. Everything else in that JSON is carried
    /// through untouched by `merge`.
    struct Credentials: Equatable, Sendable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date
        var scopes: [String]

        init?(json: Data) {
            guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                  let oauth = object["claudeAiOauth"] as? [String: Any],
                  let accessToken = oauth["accessToken"] as? String, !accessToken.isEmpty,
                  let expiresAt = oauth["expiresAt"] as? Double
            else {
                return nil
            }
            self.accessToken = accessToken
            refreshToken = (oauth["refreshToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            self.expiresAt = Date(timeIntervalSince1970: expiresAt / 1000)
            scopes = oauth["scopes"] as? [String] ?? []
        }

        /// Claude Code refreshes five minutes before expiry. Notchlet waits
        /// for the expiry itself, so a running Claude Code always gets there
        /// first and Notchlet only steps in when Claude Code is idle.
        func isExpired(now: Date = .now) -> Bool {
            expiresAt <= now
        }
    }

    /// The refresh request, or nil when the stored credentials cannot be
    /// refreshed. The scope list must be the stored one verbatim: a
    /// narrower request mints a narrower token, and after the write-back
    /// Claude Code would be stuck with it.
    static func request(for credentials: Credentials) -> URLRequest? {
        guard let refreshToken = credentials.refreshToken, !credentials.scopes.isEmpty else { return nil }
        var request = URLRequest(url: tokenURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "scope": credentials.scopes.joined(separator: " "),
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    struct Response: Decodable, Sendable {
        var accessToken: String
        var refreshToken: String?
        var expiresIn: TimeInterval
        var refreshTokenExpiresIn: TimeInterval?
        var scope: String?
    }

    enum Failure: Error, Equatable {
        /// The server no longer accepts this refresh token. Only a new sign-in
        /// through Claude Code fixes that; nothing Notchlet writes could.
        case invalidGrant
        /// Any other non-success reply, treated as transient.
        case status(Int)
        /// The stored JSON has no `claudeAiOauth` object to merge into.
        case malformedStorage
    }

    /// Reads a token endpoint reply. A 400 or 401 naming `invalid_grant` is
    /// the dead-token case; anything else short of 200 is transient.
    static func parse(status: Int, body: Data) throws -> Response {
        if status == 200 {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(Response.self, from: body)
        }
        if status == 400 || status == 401,
           let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           object["error"] as? String == "invalid_grant"
        {
            throw Failure.invalidGrant
        }
        throw Failure.status(status)
    }

    /// Folds a refresh response into the stored JSON. Only the token fields
    /// change; subscription, tier and MCP state stay as Claude Code wrote
    /// them. A reply without a refresh token keeps the old one and one
    /// without a scope keeps the old scopes, both as Claude Code does.
    static func merge(_ response: Response, into json: Data, now: Date) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              var oauth = object["claudeAiOauth"] as? [String: Any]
        else {
            throw Failure.malformedStorage
        }
        let nowMilliseconds = Int64(now.timeIntervalSince1970 * 1000)
        oauth["accessToken"] = response.accessToken
        if let refreshToken = response.refreshToken, !refreshToken.isEmpty {
            oauth["refreshToken"] = refreshToken
        }
        oauth["expiresAt"] = nowMilliseconds + Int64(response.expiresIn * 1000)
        if let refreshTokenExpiresIn = response.refreshTokenExpiresIn {
            oauth["refreshTokenExpiresAt"] = nowMilliseconds + Int64(refreshTokenExpiresIn * 1000)
        }
        let scopes = response.scope?.split(separator: " ").map(String.init) ?? []
        if !scopes.isEmpty {
            oauth["scopes"] = scopes
        }
        object["claudeAiOauth"] = oauth
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// The refresh token in stored JSON, for the compare-and-swap before a
    /// write-back. Nil when there is none, which also covers a record
    /// Claude Code cleared after its own failed refresh.
    static func storedRefreshToken(in json: Data) -> String? {
        Credentials(json: json)?.refreshToken
    }
}
