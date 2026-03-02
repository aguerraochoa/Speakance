import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var store: AppStore

    private var queueNeedsReviewCount: Int {
        store.queuedCaptures.filter { $0.status == .needsReview }.count
    }

    private var queueNeedsReviewBadgeText: String? {
        guard queueNeedsReviewCount > 0 else { return nil }
        return "\(queueNeedsReviewCount)"
    }

    var body: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack {
                CaptureView()
            }
            .tabItem {
                Label("Capture", systemImage: "waveform.circle.fill")
            }
            .tag(AppTab.capture)

            NavigationStack {
                FeedView()
            }
            .tabItem {
                Label("Ledger", systemImage: "list.bullet.rectangle.portrait.fill")
            }
            .badge(queueNeedsReviewBadgeText)
            .tag(AppTab.feed)

            NavigationStack {
                InsightsView()
            }
            .tabItem {
                Label("Insights", systemImage: "chart.xyaxis.line")
            }
            .tag(AppTab.insights)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .tag(AppTab.settings)
        }
        .tint(AppTheme.accent)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color(uiColor: .systemBackground), for: .tabBar)
    }
}
