import Foundation

@MainActor
final class AuthStore: ObservableObject {
    enum State: Equatable {
        case disabled
        case signedOut
        case loading
        case signedIn(UserSession)
        case pendingEmailVerification(String)
        case error(String)
    }

    @Published private(set) var state: State
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isWorking = false

    private let client: SupabaseAuthRESTClient?
    private let sessionStorage: AuthSessionStorage
    private let tokenStore: SharedAccessTokenStore
    private let expectedSupabaseHost: String?

    init(
        client: SupabaseAuthRESTClient?,
        sessionStorage: AuthSessionStorage = UserDefaultsAuthSessionStorage(),
        tokenStore: SharedAccessTokenStore
    ) {
        self.client = client
        self.sessionStorage = sessionStorage
        self.tokenStore = tokenStore
        self.expectedSupabaseHost = client?.config.url.host?.lowercased()
        let expectedSupabaseHost = self.expectedSupabaseHost

        if client == nil {
            self.state = .disabled
        } else {
            let existing = sessionStorage.load()
            if let existing, Self.isSessionCompatible(existing, expectedSupabaseHost: expectedSupabaseHost), !existing.isExpired {
                self.state = .signedIn(existing)
                tokenStore.set(existing.accessToken)
            } else if let existing, Self.isSessionCompatible(existing, expectedSupabaseHost: expectedSupabaseHost), existing.refreshToken != nil {
                self.state = .loading
                tokenStore.set(nil)
                Task { [weak self] in
                    await self?.restoreSessionIfPossible()
                }
            } else {
                self.state = .signedOut
                tokenStore.set(nil)
            }
        }
    }

    var isConfigured: Bool {
        client != nil
    }

    var isAuthenticated: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var currentAccessToken: String? {
        if case let .signedIn(session) = state { return session.accessToken }
        return nil
    }

    func validAccessToken() async -> String? {
        guard client != nil else { return nil }

        if case let .signedIn(session) = state {
            if !session.isExpired {
                tokenStore.set(session.accessToken)
                return session.accessToken
            }
            if let refreshed = await tryRefresh(using: session.refreshToken) {
                return refreshed.accessToken
            }
            return nil
        }

        if case .loading = state, let stored = sessionStorage.load(), let refreshed = await tryRefresh(using: stored.refreshToken) {
            return refreshed.accessToken
        }

        if let stored = sessionStorage.load() {
            guard isSessionCompatible(stored) else {
                clearSessionLocally()
                state = .signedOut
                return nil
            }
            if !stored.isExpired {
                applySignedIn(stored)
                return stored.accessToken
            }
            if let refreshed = await tryRefresh(using: stored.refreshToken) {
                return refreshed.accessToken
            }
        }

        clearSessionLocally()
        state = .signedOut
        return nil
    }

    func signIn() async {
        guard let client else { return }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = password
        guard !email.isEmpty, !password.isEmpty else {
            state = .error("Email and password are required.")
            return
        }

        isWorking = true
        defer { isWorking = false }
        state = .loading

        do {
            let session = try await client.signIn(email: email, password: password)
            applySignedIn(session)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func signUp() async {
        guard let client else { return }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = password
        guard !email.isEmpty, !password.isEmpty else {
            state = .error("Email and password are required.")
            return
        }

        isWorking = true
        defer { isWorking = false }
        state = .loading

        do {
            let result = try await client.signUp(email: email, password: password)
            if let session = result.session {
                applySignedIn(session)
            } else {
                clearSessionLocally()
                state = .pendingEmailVerification(email)
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func signOut() async {
        if let client, let token = currentAccessToken {
            _ = try? await client.signOut(accessToken: token)
        }
        clearSessionLocally()
        state = .signedOut
    }

    func dismissErrorIfNeeded() {
        if case .error = state {
            if sessionStorage.load() != nil, let session = sessionStorage.load(), !session.isExpired {
                state = .signedIn(session)
            } else {
                state = .signedOut
            }
        }
    }

    private func applySignedIn(_ session: UserSession) {
        guard isSessionCompatible(session) else {
            clearSessionLocally()
            state = .error("This login session belongs to a different Supabase project. Please sign in again.")
            return
        }
        sessionStorage.save(session)
        tokenStore.set(session.accessToken)
        state = .signedIn(session)
    }

    private func clearSessionLocally() {
        sessionStorage.clear()
        tokenStore.set(nil)
    }

    private func restoreSessionIfPossible() async {
        if let token = await validAccessToken(), !token.isEmpty {
            return
        }
        if case .loading = state {
            state = .signedOut
        }
    }

    private func tryRefresh(using refreshToken: String?) async -> UserSession? {
        guard let client, let refreshToken, !refreshToken.isEmpty else { return nil }
        do {
            let refreshed = try await client.refreshSession(refreshToken: refreshToken)
            applySignedIn(refreshed)
            return refreshed
        } catch {
            clearSessionLocally()
            state = .signedOut
            return nil
        }
    }

    private func isSessionCompatible(_ session: UserSession) -> Bool {
        Self.isSessionCompatible(session, expectedSupabaseHost: expectedSupabaseHost)
    }

    private func jwtIssuer(from token: String) -> String? {
        Self.jwtIssuer(from: token)
    }

    private static func isSessionCompatible(_ session: UserSession, expectedSupabaseHost: String?) -> Bool {
        guard let expectedSupabaseHost else { return true }
        guard let payload = jwtPayload(from: session.accessToken) else { return false }
        let issuer = (payload["iss"] as? String)?.lowercased() ?? ""
        let role = (payload["role"] as? String)?.lowercased() ?? ""
        let audience = (payload["aud"] as? String)?.lowercased() ?? ""
        guard issuer.contains(expectedSupabaseHost) else { return false }
        // Supabase user sessions should be authenticated user JWTs, not project anon/service tokens.
        if role != "authenticated" { return false }
        if !audience.isEmpty, audience != "authenticated" { return false }
        return true
    }

    private static func jwtIssuer(from token: String) -> String? {
        (jwtPayload(from: token)?["iss"] as? String)
    }

    private static func jwtPayload(from token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload.append(String(repeating: "=", count: 4 - remainder))
        }
        guard
            let data = Data(base64Encoded: payload),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return json
    }
}

struct UserSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String?
    let expiresAtEpoch: TimeInterval?
    let userEmail: String?
    let userId: String?

    var isExpired: Bool {
        guard let expiresAtEpoch else { return false }
        return Date().timeIntervalSince1970 >= (expiresAtEpoch - 30)
    }
}

protocol AuthSessionStorage {
    func load() -> UserSession?
    func save(_ session: UserSession)
    func clear()
}

struct UserDefaultsAuthSessionStorage: AuthSessionStorage {
    private let key = "speakance.auth.session.v1"

    func load() -> UserSession? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UserSession.self, from: data)
    }

    func save(_ session: UserSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

final class SharedAccessTokenStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func get() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: String?) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

struct SupabaseAuthRESTClient {
    let config: SupabaseAppConfig
    var session: URLSession = .shared

    func signIn(email: String, password: String) async throws -> UserSession {
        let url = try authURL(path: "token", queryItems: [URLQueryItem(name: "grant_type", value: "password")])
        var request = makeJSONRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)
        let payload = try JSONDecoder().decode(AuthSessionResponse.self, from: data)
        guard let userSession = payload.asUserSession else {
            throw AuthError.invalidResponse("Missing session in sign-in response.")
        }
        return userSession
    }

    func signUp(email: String, password: String) async throws -> SignUpResult {
        let url = try authURL(path: "signup")
        var request = makeJSONRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)
        let payload = try JSONDecoder().decode(AuthSessionResponse.self, from: data)
        return SignUpResult(session: payload.asUserSession)
    }

    func signOut(accessToken: String) async throws {
        let url = try authURL(path: "logout")
        var request = makeJSONRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.requestFailed("Failed to sign out.")
        }
    }

    func refreshSession(refreshToken: String) async throws -> UserSession {
        let url = try authURL(path: "token", queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")])
        var request = makeJSONRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)
        let payload = try JSONDecoder().decode(AuthSessionResponse.self, from: data)
        guard let userSession = payload.asUserSession else {
            throw AuthError.invalidResponse("Missing session in refresh response.")
        }
        return userSession
    }

    private func authURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: config.url, resolvingAgainstBaseURL: false) else {
            throw AuthError.invalidResponse("Invalid Supabase URL.")
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, "auth", "v1", path].filter { !$0.isEmpty }.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw AuthError.invalidResponse("Invalid Auth URL.")
        }
        return url
    }

    private func makeJSONRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse("Invalid HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(SupabaseAuthErrorResponse.self, from: data).message) ??
                (String(data: data, encoding: .utf8) ?? "Auth request failed")
            throw AuthError.requestFailed(message)
        }
    }
}

struct SignUpResult {
    let session: UserSession?
}

private struct AuthSessionResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: Int?
    let expiresAt: TimeInterval?
    let user: AuthUserPayload?

    var asUserSession: UserSession? {
        guard let accessToken else { return nil }
        let expiresAtEpoch: TimeInterval?
        if let expiresAt {
            expiresAtEpoch = expiresAt
        } else if let expiresIn {
            expiresAtEpoch = Date().timeIntervalSince1970 + TimeInterval(expiresIn)
        } else {
            expiresAtEpoch = nil
        }
        return UserSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresAtEpoch: expiresAtEpoch,
            userEmail: user?.email,
            userId: user?.id
        )
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }
}

private struct AuthUserPayload: Decodable {
    let id: String?
    let email: String?
}

private struct SupabaseAuthErrorResponse: Decodable {
    let message: String
}

enum AuthError: LocalizedError {
    case requestFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case let .requestFailed(message), let .invalidResponse(message):
            return message
        }
    }
}
