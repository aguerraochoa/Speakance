import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        Group {
            if !authStore.isConfigured {
                mainExperience
            } else {
                switch authStore.state {
                case .signedIn:
                    mainExperience
                case .loading:
                    ZStack {
                        AppCanvasBackground()
                        ProgressView()
                            .controlSize(.large)
                    }
                case .disabled:
                    mainExperience
                case .signedOut, .pendingEmailVerification, .passwordResetEmailSent, .error:
                    AuthGateView()
                }
            }
        }
        .fullScreenCover(isPresented: $store.shouldShowOnboarding) {
            OnboardingView()
                .environmentObject(store)
        }
        .task(id: authStore.state) {
            if authStore.currentAccessToken != nil {
                await store.refreshCloudStateFromServer()
                await store.syncQueueIfPossible()
            }
        }
    }

    private var mainExperience: some View {
        RootTabView()
            .sheet(item: $store.activeReview) { context in
                ExpenseReviewView(context: context)
                    .environmentObject(store)
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

private struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var page = 0

    private let slides: [(icon: String, title: String, body: String)] = [
        (
            "waveform.circle.fill",
            "Capture In Seconds",
            "Record or type one expense at a time. Speakance parses amount, category, and date for you."
        ),
        (
            "arrow.triangle.2.circlepath.circle.fill",
            "Reliable Offline Queue",
            "No internet? Captures stay local and sync automatically when connection returns."
        ),
        (
            "list.bullet.rectangle.portrait.fill",
            "Review With Confidence",
            "Use Ledger filters and quick edits to reconcile monthly spending in minutes."
        ),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TabView(selection: $page) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        SpeakCard(padding: 24, cornerRadius: 26, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
                            VStack(alignment: .leading, spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(AppTheme.accent.opacity(0.16))
                                        .frame(width: 62, height: 62)
                                    Image(systemName: slide.icon)
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundStyle(AppTheme.accent)
                                }
                                Text(slide.title)
                                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                                    .foregroundStyle(AppTheme.ink)
                                Text(slide.body)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.muted)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .tag(index)
                        .padding(.horizontal, 22)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button {
                    if page < slides.count - 1 {
                        page += 1
                    } else {
                        store.markOnboardingCompleted()
                    }
                } label: {
                    Text(page < slides.count - 1 ? "Continue" : "Start Using Speakance")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }
            .background(AppCanvasBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        store.markOnboardingCompleted()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }
}
