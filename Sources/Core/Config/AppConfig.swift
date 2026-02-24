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
        let mock = MockExpenseAPIClient()
        guard let config = SupabaseAppConfig.loadFromBundle() else {
            return Bundle(
                appStore: AppStore(apiClient: mock),
                authStore: AuthStore(client: nil, tokenStore: SharedAccessTokenStore())
            )
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
