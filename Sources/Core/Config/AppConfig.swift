import Foundation

struct SupabaseAppConfig: Equatable {
    let url: URL
    let anonKey: String

    static func loadFromBundle() -> SupabaseAppConfig? {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        else {
            return nil
        }

        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty, let url = URL(string: trimmedURL) else {
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
            #if DEBUG
            print("[Speakance] Missing Supabase configuration. Running in local/offline mode.")
            let tokenStore = SharedAccessTokenStore()
            let authStore = AuthStore(client: nil, tokenStore: tokenStore)
            let appStore = AppStore(apiClient: MockExpenseAPIClient())
            return Bundle(appStore: appStore, authStore: authStore)
            #else
            fatalError("Missing Supabase configuration. Set SUPABASE_URL and SUPABASE_ANON_KEY before shipping.")
            #endif
        }

        let tokenStore = SharedAccessTokenStore()
        let authStore = AuthStore(
            client: SupabaseAuthRESTClient(config: config),
            tokenStore: tokenStore
        )

        let remote = SupabaseFunctionExpenseAPIClient(
            config: config,
            accessTokenProvider: { await authStore.validAccessToken() }
        )

        let apiClient: ExpenseAPIClientProtocol = remote
        let appStore = AppStore(apiClient: apiClient)
        return Bundle(appStore: appStore, authStore: authStore)
    }
}
