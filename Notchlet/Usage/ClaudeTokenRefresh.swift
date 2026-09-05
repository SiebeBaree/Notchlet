import Foundation

/// The pure part of a Claude Code token refresh: whether a stored token
/// needs one, the request to send, and how to fold the response back into
/// the stored JSON, exactly as Claude Code 2.1 does it.
enum ClaudeTokenRefresh {
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    /// Claude Code's OAuth client; a refresh has to name the client the
    /// token was issued to.
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// The fields Notchlet reads from the `claudeAiOauth` object; `merge`
    /// carries everything else through untouched.
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

        /// Claude Code refreshes five minutes before expiry; waiting for the
        /// expiry itself means a running Claude Code always gets there first.
        func isExpired(now: Date = .now) -> Bool {
            expiresAt <= now
        }
    }

    /// Nil when the stored credentials cannot be refreshed. The scope list
    /// must be the stored one verbatim: a narrower request mints a narrower
    /// token, and after the write-back Claude Code would be stuck with it.
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
        /// Only a new sign-in through Claude Code fixes this.
        case invalidGrant
        /// Transient.
        case status(Int)
        case malformedStorage
    }

    /// A 400 or 401 naming `invalid_grant` is the dead-token case; anything
    /// else short of 200 is transient.
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

    /// Only the token fields change. A reply without a refresh token keeps
    /// the old one and one without a scope keeps the old scopes, as Claude
    /// Code does.
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

    /// For the compare-and-swap before a write-back.
    static func storedRefreshToken(in json: Data) -> String? {
        Credentials(json: json)?.refreshToken
    }
}
