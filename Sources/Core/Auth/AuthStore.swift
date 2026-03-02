import Foundation
import Security

@MainActor
final class AuthStore: ObservableObject {
    enum State: Equatable {
        case disabled
        case signedOut
        case loading
        case signedIn(UserSession)
        case pendingEmailVerification(String)
        case passwordResetEmailSent(String)
        case error(String)
    }

    enum SessionValidationState: Equatable {
        case unknown
        case validated
        case invalid
    }

    enum CloudMutationPermission: Equatable {
        case allowed
        case authPending
        case authRequired
    }

    @Published private(set) var state: State
    @Published private(set) var sessionValidationState: SessionValidationState
    @Published var isWorking = false

    private let client: SupabaseAuthRESTClient?
    private let sessionStorage: AuthSessionStorage
    private let tokenStore: SharedAccessTokenStore
    private let expectedSupabaseHost: String?
    private var refreshTask: Task<UserSession?, Never>?
    private var validationTask: Task<Void, Never>?
    private var lastAccessTokenReturnLogAt: Date = .distantPast
    private static let accessTokenReturnLogThrottleSeconds: TimeInterval = 20

    init(
        client: SupabaseAuthRESTClient?,
        sessionStorage: AuthSessionStorage = MigratingAuthSessionStorage(
            primary: KeychainAuthSessionStorage(),
            legacy: UserDefaultsAuthSessionStorage()
        ),
        tokenStore: SharedAccessTokenStore
    ) {
        self.client = client
        self.sessionStorage = sessionStorage
        self.tokenStore = tokenStore
        self.expectedSupabaseHost = client?.config.url.host?.lowercased()
        let expectedSupabaseHost = self.expectedSupabaseHost

        if client == nil {
            self.state = .disabled
            self.sessionValidationState = .validated
            logAuth("Initialized in disabled mode")
        } else {
            let existing = sessionStorage.load()
            if let existing, Self.isSessionCompatible(existing, expectedSupabaseHost: expectedSupabaseHost), !existing.isExpired {
                self.state = .loading
                self.sessionValidationState = .unknown
                tokenStore.set(nil)
                logAuth("Found stored session at launch (non-expired)", details: sessionDebugDetails(existing))
                Task { [weak self] in
                    await self?.bootstrapSessionValidation()
                }
            } else if let existing, Self.isSessionCompatible(existing, expectedSupabaseHost: expectedSupabaseHost), existing.refreshToken != nil {
                self.state = .loading
                self.sessionValidationState = .unknown
                tokenStore.set(nil)
                logAuth("Found stored session at launch (expired, has refresh token)", details: sessionDebugDetails(existing))
                Task { [weak self] in
                    await self?.bootstrapSessionValidation()
                }
            } else {
                self.state = .signedOut
                self.sessionValidationState = .invalid
                tokenStore.set(nil)
                if let existing {
                    logAuth("Discarded incompatible/invalid stored session at launch", details: sessionDebugDetails(existing))
                } else {
                    logAuth("No stored session at launch")
                }
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

    var cloudMutationPermission: CloudMutationPermission {
        guard isConfigured else { return .authRequired }
        switch state {
        case .signedIn:
            switch sessionValidationState {
            case .validated:
                return .allowed
            case .unknown:
                // Signed-in sessions remain usable while validation is pending.
                return .allowed
            case .invalid:
                return .authRequired
            }
        case .loading:
            return .authPending
        case .disabled, .signedOut, .pendingEmailVerification, .passwordResetEmailSent, .error:
            return .authRequired
        }
    }

    func validAccessToken() async -> String? {
        guard client != nil else { return nil }

        if case let .signedIn(session) = state {
            if session.expiresAtEpoch == nil {
                // Some auth responses may omit explicit expiry; use current session token
                // and let server validation/401 handling decide if re-auth is needed.
                tokenStore.set(session.accessToken)
                logAccessTokenReturnIfNeeded("Returning signed-in access token (no exp claim)", token: session.accessToken)
                return session.accessToken
            }
            if !session.isExpired {
                tokenStore.set(session.accessToken)
                logAccessTokenReturnIfNeeded("Returning signed-in access token", token: session.accessToken)
                return session.accessToken
            }
            logAuth("Signed-in access token expired, attempting refresh", details: sessionDebugDetails(session))
            if let refreshed = await tryRefresh(using: session.refreshToken) {
                return refreshed.accessToken
            }
            logAuth("Refresh failed for signed-in state")
            return nil
        }

        if case .loading = state, let stored = sessionStorage.load() {
            guard isSessionCompatible(stored) else {
                logAuth("Stored loading session is incompatible with expected project host", details: sessionDebugDetails(stored))
                clearSessionLocally()
                state = .signedOut
                sessionValidationState = .invalid
                return nil
            }

            if !stored.isExpired {
                applySignedIn(stored, sessionValidationState: .unknown)
                logAuth("Recovered access token while loading from non-expired stored session", details: tokenDebugDetails(stored.accessToken))
                return stored.accessToken
            }

            if let refreshed = await tryRefresh(using: stored.refreshToken) {
                logAuth("Recovered access token while loading via refresh", details: tokenDebugDetails(refreshed.accessToken))
                return refreshed.accessToken
            }
        }

        if let stored = sessionStorage.load() {
            guard isSessionCompatible(stored) else {
                logAuth("Stored session is incompatible with expected project host", details: sessionDebugDetails(stored))
                clearSessionLocally()
                state = .signedOut
                sessionValidationState = .invalid
                return nil
            }
            if !stored.isExpired {
                applySignedIn(stored, sessionValidationState: .unknown)
                logAccessTokenReturnIfNeeded("Returning stored access token while restoring session", token: stored.accessToken)
                return stored.accessToken
            }
            logAuth("Stored session expired, attempting refresh", details: sessionDebugDetails(stored))
            if let refreshed = await tryRefresh(using: stored.refreshToken) {
                return refreshed.accessToken
            }
        }

        // Avoid noisy repeated log/reset cycles when we are already signed out
        // and there is no persisted session/token to clear.
        if case .signedOut = state,
           sessionValidationState == .invalid,
           sessionStorage.load() == nil,
           tokenStore.get() == nil {
            return nil
        }

        logAuth("No valid access token available; clearing local session")
        clearSessionLocally()
        state = .signedOut
        sessionValidationState = .invalid
        return nil
    }

    func validateSessionWithServerIfNeeded() async {
        if let existingTask = validationTask {
            await existingTask.value
            return
        }

        let task = Task<Void, Never> {
            await performValidateSessionWithServerIfNeeded()
        }
        validationTask = task
        await task.value
        validationTask = nil
    }

    private func performValidateSessionWithServerIfNeeded() async {
        guard let client else { return }
        let shouldValidate: Bool = {
            if case .signedIn = state { return true }
            if case .loading = state { return true }
            return false
        }()
        guard shouldValidate else { return }
        guard let token = await validAccessToken(), !token.isEmpty else {
            logAuth("Server validation skipped because token is unavailable")
            clearSessionLocally()
            state = .signedOut
            sessionValidationState = .invalid
            return
        }

        logAuth("Validating session with Supabase /auth/v1/user", details: tokenDebugDetails(token))
        do {
            _ = try await client.fetchCurrentUser(accessToken: token)
            logAuth("Session validated with server")
            switch state {
            case .loading:
                if let stored = sessionStorage.load(),
                   isSessionCompatible(stored),
                   !stored.isExpired {
                    applySignedIn(stored, sessionValidationState: .validated)
                }
            case let .signedIn(session):
                applySignedIn(session, sessionValidationState: .validated)
            default:
                break
            }
        } catch let AuthError.unauthorized(message) {
            logAuth("Server validation returned unauthorized", details: [
                "reason": message,
                "state": describeState(state)
            ])
            clearSessionLocally()
            state = .signedOut
            sessionValidationState = .invalid
        } catch let AuthError.requestFailed(message) {
            logAuth("Server validation request failed (keeping local session)", details: [
                "reason": message,
                "state": describeState(state)
            ])
            // Keep local session on transient server/network failures.
            if case .loading = state,
               let stored = sessionStorage.load(),
               isSessionCompatible(stored),
               !stored.isExpired {
                applySignedIn(stored, sessionValidationState: .unknown)
            }
        } catch let error as URLError {
            logAuth("Server validation transport error (keeping local session)", details: [
                "reason": error.localizedDescription,
                "code": "\(error.code.rawValue)"
            ])
            // Keep local session on transport failures.
            if case .loading = state,
               let stored = sessionStorage.load(),
               isSessionCompatible(stored),
               !stored.isExpired {
                applySignedIn(stored, sessionValidationState: .unknown)
            }
        } catch {
            logAuth("Server validation unexpected error (keeping local session)", details: [
                "reason": error.localizedDescription
            ])
            // Default to preserving local session unless auth is explicitly invalid.
            if case .loading = state,
               let stored = sessionStorage.load(),
               isSessionCompatible(stored),
               !stored.isExpired {
                applySignedIn(stored, sessionValidationState: .unknown)
            }
        }
    }

    func recoverSessionAfterUnauthorized() async -> String? {
        guard client != nil else { return nil }

        let refreshToken: String? = {
            if case let .signedIn(session) = state, let token = session.refreshToken, !token.isEmpty {
                return token
            }
            if let token = sessionStorage.load()?.refreshToken, !token.isEmpty {
                return token
            }
            return nil
        }()

        if let refreshed = await tryRefresh(using: refreshToken) {
            return refreshed.accessToken
        }

        clearSessionLocally()
        state = .signedOut
        sessionValidationState = .invalid
        return nil
    }

    func signIn(email rawEmail: String, password rawPassword: String) async {
        guard let client else { return }
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = rawPassword
        guard !email.isEmpty, !password.isEmpty else {
            state = .error("Email and password are required.")
            return
        }

        // Ensure a fresh sign-in never reuses stale persisted credentials.
        clearSessionLocally()
        sessionValidationState = .unknown
        logAuth("Starting sign-in flow", details: ["email": email.lowercased()])

        isWorking = true
        defer { isWorking = false }
        state = .loading

        do {
            let session = try await client.signIn(email: email, password: password)
            applySignedIn(session)
            logAuth("Sign-in succeeded", details: sessionDebugDetails(session))
        } catch {
            logAuth("Sign-in failed", details: ["reason": error.localizedDescription])
            state = .error(Self.userFacingSignInErrorMessage(from: error))
        }
    }

    func signUp(email rawEmail: String, password rawPassword: String) async {
        guard let client else { return }
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = rawPassword
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
                sessionValidationState = .invalid
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func signOut() async {
        logAuth("Signing out current session", details: [
            "state": describeState(state)
        ])
        if let client, let token = currentAccessToken {
            _ = try? await client.signOut(accessToken: token)
        }
        clearSessionLocally()
        state = .signedOut
        sessionValidationState = .invalid
        logAuth("Signed out")
    }

    func deleteAccount() async {
        guard let client else { return }
        guard let token = await validAccessToken(), !token.isEmpty else {
            state = .error("You need an active session to delete your account.")
            return
        }

        isWorking = true
        defer { isWorking = false }
        state = .loading

        do {
            try await client.deleteAccount(accessToken: token)
            clearSessionLocally()
            state = .signedOut
            sessionValidationState = .invalid
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func sendPasswordReset(email rawEmail: String) async {
        guard let client else { return }
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            state = .error("Enter your email first so we can send a reset link.")
            return
        }

        isWorking = true
        defer { isWorking = false }
        state = .loading

        do {
            try await client.sendPasswordReset(email: email)
            state = .passwordResetEmailSent(email)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func dismissErrorIfNeeded() {
        if case .error = state {
            if sessionStorage.load() != nil, let session = sessionStorage.load(), !session.isExpired {
                applySignedIn(session, sessionValidationState: .unknown)
            } else {
                state = .signedOut
                sessionValidationState = .invalid
            }
        }
    }

    private func applySignedIn(_ session: UserSession, sessionValidationState: SessionValidationState = .validated) {
        guard isSessionCompatible(session) else {
            logAuth("Rejecting incompatible session", details: sessionDebugDetails(session))
            clearSessionLocally()
            state = .error("This login session belongs to a different Supabase project. Please sign in again.")
            self.sessionValidationState = .invalid
            return
        }
        sessionStorage.save(session)
        tokenStore.set(session.accessToken)
        state = .signedIn(session)
        self.sessionValidationState = sessionValidationState
        logAuth("Applied signed-in session", details: sessionDebugDetails(session))
    }

    private func clearSessionLocally() {
        let hadSession = sessionStorage.load() != nil
        let hadToken = tokenStore.get() != nil
        sessionStorage.clear()
        tokenStore.set(nil)
        sessionValidationState = .invalid
        if hadSession || hadToken {
            logAuth("Cleared local session/token cache")
        }
    }

    private func restoreSessionIfPossible() async {
        if let token = await validAccessToken(), !token.isEmpty {
            return
        }
        if case .loading = state {
            state = .signedOut
        }
    }

    private func bootstrapSessionValidation() async {
        logAuth("Bootstrapping session validation", details: ["state": describeState(state)])
        await validateSessionWithServerIfNeeded()
        if case .loading = state {
            if let stored = sessionStorage.load(), isSessionCompatible(stored), !stored.isExpired {
                // If we couldn't reach the server at boot, fall back to local session.
                applySignedIn(stored, sessionValidationState: .unknown)
                logAuth("Fell back to local session after bootstrap", details: sessionDebugDetails(stored))
            } else {
                // If validation couldn't establish a valid signed-in session, force explicit sign-in.
                clearSessionLocally()
                state = .signedOut
                logAuth("Bootstrap ended without valid session")
            }
        }
    }

    private func tryRefresh(using refreshToken: String?) async -> UserSession? {
        if let existingTask = refreshTask {
            return await existingTask.value
        }

        let task = Task<UserSession?, Never> {
            await performTryRefresh(using: refreshToken)
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func performTryRefresh(using refreshToken: String?) async -> UserSession? {
        guard let client, let refreshToken, !refreshToken.isEmpty else {
            logAuth("Refresh skipped: refresh token missing")
            return nil
        }
        logAuth("Attempting token refresh")
        do {
            let refreshed = try await client.refreshSession(refreshToken: refreshToken)
            applySignedIn(refreshed)
            logAuth("Token refresh succeeded", details: sessionDebugDetails(refreshed))
            return refreshed
        } catch {
            logAuth("Token refresh failed", details: ["reason": error.localizedDescription])
            clearSessionLocally()
            state = .signedOut
            return nil
        }
    }

    private func describeState(_ value: State) -> String {
        switch value {
        case .disabled:
            return "disabled"
        case .signedOut:
            return "signedOut"
        case .loading:
            return "loading"
        case .signedIn:
            return "signedIn"
        case .pendingEmailVerification:
            return "pendingEmailVerification"
        case .passwordResetEmailSent:
            return "passwordResetEmailSent"
        case .error:
            return "error"
        }
    }

    private func tokenDebugDetails(_ token: String?) -> [String: String] {
        guard let token, !token.isEmpty else { return ["token": "missing"] }
        let payload = Self.jwtPayload(from: token)
        let issuer = (payload?["iss"] as? String) ?? "<none>"
        let role = (payload?["role"] as? String) ?? "<none>"
        let audience = (payload?["aud"] as? String) ?? "<none>"
        let subject = (payload?["sub"] as? String) ?? "<none>"
        let expEpoch = payload?["exp"] as? TimeInterval
        let now = Date().timeIntervalSince1970
        let expiresInSec = expEpoch.map { Int($0 - now) }
        return [
            "iss": issuer,
            "role": role,
            "aud": audience,
            "subTail": String(subject.suffix(8)),
            "expiresInSec": expiresInSec.map(String.init) ?? "<none>",
            "tokenChars": "\(token.count)"
        ]
    }

    private func sessionDebugDetails(_ session: UserSession) -> [String: String] {
        var details = tokenDebugDetails(session.accessToken)
        details["hasRefresh"] = session.refreshToken?.isEmpty == false ? "yes" : "no"
        details["isExpiredLocal"] = session.isExpired ? "yes" : "no"
        details["expiresAtEpoch"] = session.expiresAtEpoch.map { String(Int($0)) } ?? "<none>"
        return details
    }

    private func logAuth(_ message: String, details: [String: String] = [:]) {
        #if DEBUG
        let suffix: String
        if details.isEmpty {
            suffix = ""
        } else {
            suffix = " " + details
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
        }
        print("[Speakance][Auth] \(message)\(suffix)")
        #endif
    }

    private func logAccessTokenReturnIfNeeded(_ message: String, token: String) {
        let now = Date()
        guard now.timeIntervalSince(lastAccessTokenReturnLogAt) >= Self.accessTokenReturnLogThrottleSeconds else {
            return
        }
        lastAccessTokenReturnLogAt = now
        logAuth(message, details: tokenDebugDetails(token))
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

    private static func userFacingSignInErrorMessage(from error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost:
                return "Couldn't connect right now. Check your connection and try again."
            default:
                break
            }
        }

        let rawMessage: String = {
            if let authError = error as? AuthError {
                return authError.errorDescription ?? String(describing: authError)
            }
            return error.localizedDescription
        }()

        let normalized = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.contains("invalid login credentials")
            || normalized.contains("invalid credentials")
            || normalized.contains("wrong password")
            || normalized.contains("user not found")
            || normalized.contains("invalid email or password") {
            return "Incorrect email or password. Try again or reset your password."
        }
        if normalized.contains("email not confirmed")
            || normalized.contains("email not verified") {
            return "Check your email to confirm your account, then try signing in."
        }
        if normalized.contains("too many requests")
            || normalized.contains("rate limit")
            || normalized.contains("429") {
            return "Too many attempts. Wait a minute and try again."
        }

        return "Sign-in failed. Please try again."
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

struct KeychainAuthSessionStorage: AuthSessionStorage {
    private let service = "com.speakance.auth"
    private let account = "session.v1"

    func load() -> UserSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(UserSession.self, from: data)
    }

    func save(_ session: UserSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
#if os(iOS)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
#endif

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let attributes = [kSecValueData as String: data] as CFDictionary
            _ = SecItemUpdate(baseQuery as CFDictionary, attributes)
        }
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct MigratingAuthSessionStorage: AuthSessionStorage {
    let primary: AuthSessionStorage
    let legacy: AuthSessionStorage

    func load() -> UserSession? {
        if let session = primary.load() {
            return session
        }
        guard let legacySession = legacy.load() else { return nil }
        primary.save(legacySession)
        legacy.clear()
        return legacySession
    }

    func save(_ session: UserSession) {
        primary.save(session)
        legacy.clear()
    }

    func clear() {
        primary.clear()
        legacy.clear()
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
    private let webAuthBaseURLString = "https://speakance.vercel.app"

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
        request.httpBody = try JSONEncoder().encode(SignUpRequestPayload(
            email: email,
            password: password,
            emailRedirectTo: webAuthRedirectURL(path: "/auth/confirmed")?.absoluteString
        ))

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

    func sendPasswordReset(email: String) async throws {
        let url = try authURL(path: "recover")
        var request = makeJSONRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(PasswordResetRequestPayload(
            email: email,
            redirectTo: webAuthRedirectURL(path: "/auth/reset")?.absoluteString
        ))

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)
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

    func deleteAccount(accessToken: String) async throws {
        let url = try functionsURL(path: "delete-account")
        var request = makeJSONRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)
    }

    func fetchCurrentUser(accessToken: String) async throws -> AuthUserPayload {
        let url = try authURL(path: "user")
        var request = makeJSONRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)
        return try JSONDecoder().decode(AuthUserPayload.self, from: data)
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

    private func functionsURL(path: String) throws -> URL {
        guard var components = URLComponents(url: config.url, resolvingAgainstBaseURL: false) else {
            throw AuthError.invalidResponse("Invalid Supabase URL.")
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, "functions", "v1", path]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.queryItems = nil
        guard let url = components.url else {
            throw AuthError.invalidResponse("Invalid Functions URL.")
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

    private func webAuthRedirectURL(path: String) -> URL? {
        guard var components = URLComponents(string: webAuthBaseURLString) else { return nil }
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        components.path = normalizedPath
        return components.url
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse("Invalid HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(SupabaseAuthErrorResponse.self, from: data).resolvedMessage) ??
                (String(data: data, encoding: .utf8) ?? "Auth request failed")
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AuthError.unauthorized(message)
            }
            throw AuthError.requestFailed(message)
        }
    }
}

struct SignUpResult {
    let session: UserSession?
}

private struct SignUpRequestPayload: Encodable {
    let email: String
    let password: String
    let emailRedirectTo: String?

    enum CodingKeys: String, CodingKey {
        case email
        case password
        case emailRedirectTo = "email_redirect_to"
    }
}

private struct PasswordResetRequestPayload: Encodable {
    let email: String
    let redirectTo: String?

    enum CodingKeys: String, CodingKey {
        case email
        case redirectTo = "redirect_to"
    }
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

struct AuthUserPayload: Decodable {
    let id: String?
    let email: String?
}

private struct SupabaseAuthErrorResponse: Decodable {
    let message: String?
    let error: String?
    let errorDescription: String?
    let msg: String?
    let code: String?

    var resolvedMessage: String {
        message?.nonEmpty
            ?? errorDescription?.nonEmpty
            ?? msg?.nonEmpty
            ?? error?.nonEmpty
            ?? code?.nonEmpty
            ?? "Auth request failed"
    }
}

enum AuthError: LocalizedError {
    case unauthorized(String)
    case requestFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case let .unauthorized(message), let .requestFailed(message), let .invalidResponse(message):
            return message
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
