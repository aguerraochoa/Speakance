import SwiftUI

@main
struct SpeakanceApp: App {
    @StateObject private var store: AppStore
    @StateObject private var authStore: AuthStore

    init() {
        let bundle = AppBootstrap.makeBundle()
        _store = StateObject(wrappedValue: bundle.appStore)
        _authStore = StateObject(wrappedValue: bundle.authStore)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(authStore)
        }
    }
}
