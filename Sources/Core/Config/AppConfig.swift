import Foundation

struct SupabaseAppConfig: Equatable {
    let url: URL
    let anonKey: String

    private static let fallbackScheme = "https"

    private static func sanitize(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "\\", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private static func resolveURL(_ rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let trimmed = sanitize(rawValue)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            return url
        }
        if trimmed.contains("://") {
            return nil
        }
        return URL(string: "\(fallbackScheme)://\(trimmed)")
    }

    static func loadFromBundle() -> SupabaseAppConfig? {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        else {
            #if DEBUG
            print("[Speakance][Config] Missing required Info.plist keys: SUPABASE_URL and/or SUPABASE_ANON_KEY")
            #endif
            return nil
        }

        let resolvedFromURL = resolveURL(urlString)
        let trimmedKey = sanitize(anonKey)
        #if DEBUG
        print("[Speakance][Config] SUPABASE_URL raw='\(urlString)'")
        print("[Speakance][Config] SUPABASE_ANON_KEY length=\(trimmedKey.count)")
        if let resolvedFromURL {
            print("[Speakance][Config] SUPABASE_URL resolved='\(resolvedFromURL.absoluteString)'")
        }
        #endif
        guard
            let url = resolvedFromURL,
            !trimmedKey.isEmpty,
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme)
        else {
            return nil
        }

        return SupabaseAppConfig(url: url, anonKey: trimmedKey)
    }
}

enum AppBootstrap {
    struct Bundle {
        let appStore: AppStore
        let authStore: AuthStore
    }

    @MainActor
    static func makeBundle() -> Bundle {
        makeBundle(config: SupabaseAppConfig.loadFromBundle())
    }

    @MainActor
    static func makeBundle(config: SupabaseAppConfig?) -> Bundle {
        guard let config else {
            print("[Speakance] Missing Supabase configuration. Running in local/offline mode.")
            let tokenStore = SharedAccessTokenStore()
            let authStore = AuthStore(client: nil, tokenStore: tokenStore)
            let appStore = AppStore(apiClient: MockExpenseAPIClient())
            return Bundle(appStore: appStore, authStore: authStore)
        }

        let tokenStore = SharedAccessTokenStore()
        let authStore = AuthStore(
            client: SupabaseAuthRESTClient(config: config),
            tokenStore: tokenStore
        )

        let remote = SupabaseFunctionExpenseAPIClient(
            config: config,
            accessTokenProvider: { await authStore.validAccessToken() },
            unauthorizedRecoveryProvider: { await authStore.recoverSessionAfterUnauthorized() },
            authenticationFailureHandler: { _ in
                // Re-validate auth state without force-signing out on a single API 401.
                await authStore.validateSessionWithServerIfNeeded()
            }
        )

        let apiClient: ExpenseAPIClientProtocol = remote
        let appStore = AppStore(
            apiClient: apiClient,
            cloudMutationPermissionProvider: { await MainActor.run { authStore.cloudMutationPermission } },
            persistenceScopeProvider: { authStore.persistenceScopeUserID }
        )
        return Bundle(appStore: appStore, authStore: authStore)
    }
}
