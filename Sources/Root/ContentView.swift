import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        Group {
            if authStore.isConfigured && !authStore.isAuthenticated {
                AuthGateView()
            } else {
                RootTabView()
                    .sheet(item: $store.activeReview) { context in
                        ExpenseReviewView(context: context)
                            .environmentObject(store)
                    }
            }
        }
        .task(id: authStore.state) {
            if authStore.currentAccessToken != nil {
                await store.refreshCloudStateFromServer()
                await store.syncQueueIfPossible()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppStore())
            .environmentObject(AuthStore(client: nil, tokenStore: SharedAccessTokenStore()))
    }
}
