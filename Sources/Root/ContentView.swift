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
        .fullScreenCover(isPresented: tutorialIsPresented) {
            OnboardingShowcaseView()
                .environmentObject(store)
                .interactiveDismissDisabled()
        }
        .task {
            store.beginInteractiveTutorialIfNeeded()
        }
        .task(id: authStore.currentAccessToken) {
            if case .signedIn = authStore.state, authStore.currentAccessToken != nil {
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

    private var tutorialIsPresented: Binding<Bool> {
        Binding(
            get: {
                if case .running = store.tutorialState { return true }
                return false
            },
            set: { newValue in
                if !newValue { store.skipTutorial() }
            }
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppStore())
            .environmentObject(AuthStore(client: nil, tokenStore: SharedAccessTokenStore()))
    }
}

private struct OnboardingShowcaseView: View {
    @EnvironmentObject private var store: AppStore

    private var step: TutorialStep {
        if case let .running(activeStep) = store.tutorialState { return activeStep }
        return .welcome
    }

    private var canGoBack: Bool {
        guard let index = TutorialStep.allCases.firstIndex(of: step) else { return false }
        return index > 0
    }

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        showcaseCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }

                footer
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.98, blue: 1.0), Color(red: 0.90, green: 0.96, blue: 0.99)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            OnboardingParticleField()
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack {
            Text("Speakance")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            Button("Skip") {
                store.skipTutorial()
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.faintText)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var showcaseCard: some View {
        SpeakCard(
            padding: 16,
            cornerRadius: 28,
            fill: AnyShapeStyle(Color.white.opacity(0.97)),
            stroke: AppTheme.cardStroke
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(step.title)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(step.message)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                mockScreen
            }
        }
    }

    @ViewBuilder
    private var mockScreen: some View {
        switch step {
        case .welcome:
            welcomeMock
        case .captureDemo:
            captureMock
        case .ledgerDemo:
            ledgerMock
        case .insightsDemo:
            insightsMock
        case .done:
            doneMock
        }
    }

    private var welcomeMock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpeakCard(padding: 14, cornerRadius: 20, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("One flow. Full control.")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Spacer()
                        StatusPill(text: "Voice + Text", color: AppTheme.accent)
                    }
                    HStack(spacing: 8) {
                        tourChip("Capture", tint: Color(uiColor: .systemBlue))
                        tourChip("Ledger", tint: AppTheme.success)
                        tourChip("Insights", tint: Color(uiColor: .systemOrange))
                    }
                    Text("Track spend, review details, and monitor trends with the same visual language you’ll use daily.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.muted)
                }
            }

            HStack(spacing: 10) {
                miniStatCard("Monthly spend", "$2,486")
                miniStatCard("Pending queue", "0")
                miniStatCard("Top category", "Food")
            }
        }
    }

    private var captureMock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speakance")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text("Add an expense fast")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                StatusPill(text: "Online", color: AppTheme.success)
            }

            HStack(spacing: 8) {
                mockSegment("Speak", selected: true)
                mockSegment("Text", selected: false)
            }

            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "airplane")
                        .font(.system(size: 13, weight: .semibold))
                    Text("No Trip")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.faintText)
                }
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.cardStrong, in: Capsule())
                .overlay(Capsule().stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1))

                Spacer()
            }

            SpeakCard(padding: 16, cornerRadius: 20, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
                VStack(spacing: 12) {
                    Text("Tap to record")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ZStack {
                        Circle()
                            .fill(AppTheme.accent.opacity(0.08))
                            .frame(width: 138, height: 138)
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.03, green: 0.11, blue: 0.28), Color(red: 0.01, green: 0.05, blue: 0.16)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 98, height: 98)
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(AppTheme.success)
                            .frame(width: 8, height: 8)
                        Text("Listening for your expense...")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.muted)
                        Spacer()
                    }

                    Text("Dinner and drinks 46.80")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
                        )
                }
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var ledgerMock: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpeakCard(padding: 14, cornerRadius: 20, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Expenses")
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .foregroundStyle(AppTheme.ink)
                            Text("Full history + offline queue in one timeline")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        StatusPill(text: "Up to date", color: AppTheme.success)
                    }

                    HStack(spacing: 10) {
                        MetricChip(title: "Month", value: "$2,486", tint: AppTheme.accent)
                        MetricChip(title: "Queue", value: "0", tint: AppTheme.sky)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    mockFilterChip(title: "Trip", value: "Mexico City")
                    mockFilterChip(title: "Card", value: "Chase Visa")
                    mockFilterChip(title: "Month", value: "February 2026")
                }
            }

            VStack(spacing: 8) {
                mockLedgerRow("Tacos El Pata", "Food", "$24.50", date: "Today")
                mockLedgerRow("Uber to airport", "Transport", "$18.20", date: "Yesterday")
                mockLedgerRow("Costco weekly groceries", "Groceries", "$126.40", date: "Feb 24")
                mockLedgerRow("Adobe Creative Cloud", "Subscriptions", "$22.99", date: "Feb 22")
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var insightsMock: some View {
        let segments: [OnboardingDonutSegment] = [
            OnboardingDonutSegment(category: "Food", amount: "$640", ratio: 0.26, color: AppTheme.categoryColor("Food")),
            OnboardingDonutSegment(category: "Groceries", amount: "$520", ratio: 0.21, color: AppTheme.categoryColor("Groceries")),
            OnboardingDonutSegment(category: "Transport", amount: "$280", ratio: 0.11, color: AppTheme.categoryColor("Transport")),
            OnboardingDonutSegment(category: "Subscriptions", amount: "$210", ratio: 0.08, color: AppTheme.categoryColor("Subscriptions")),
            OnboardingDonutSegment(category: "More", amount: "$836", ratio: 0.34, color: Color(uiColor: .systemGray4))
        ]

        return VStack(alignment: .leading, spacing: 10) {
            SpeakCard(padding: 14, cornerRadius: 20, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Insights")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundStyle(AppTheme.ink)
                            Text("Your spending, visually organized.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        StatusPill(text: "Synced", color: AppTheme.success)
                    }

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total spend")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.faintText)
                            Text("$2,486")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundStyle(AppTheme.ink)
                        }
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Top category")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.faintText)
                            HStack(spacing: 6) {
                                CategoryDot(category: "Food")
                                Text("Food")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(AppTheme.ink)
                            }
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    mockFilterChip(title: "Trip", value: "Mexico City")
                    mockFilterChip(title: "Card", value: "Chase Visa")
                    mockFilterChip(title: "Month", value: "February 2026")
                }
            }

            HStack(spacing: 10) {
                insightsMetricCard(title: "Daily Avg", value: "$83")
                insightsMetricCard(title: "Entries", value: "42")
                insightsMetricCard(title: "Queue", value: "0")
            }

            SpeakCard(padding: 18, cornerRadius: 24, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "Spending Mix", subtitle: "Category share for current filters")

                    VStack(alignment: .leading, spacing: 14) {
                        OnboardingDonutChartView(
                            segments: segments,
                            centerTitle: "$2,486",
                            centerSubtitle: "42 entries"
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: 220)
                        .padding(.vertical, 10)

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(segments.prefix(5))) { segment in
                                onboardingLegendRow(segment)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var doneMock: some View {
        SpeakCard(padding: 16, cornerRadius: 20, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ready to track with confidence.")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                checklistRow("Capture expenses in seconds")
                checklistRow("Review full history in Ledger")
                checklistRow("Monitor patterns in Insights")
                checklistRow("Replay this walkthrough from Settings")
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(TutorialStep.allCases, id: \.self) { dot in
                    Capsule()
                        .fill(dot == step ? AppTheme.accent : AppTheme.faintText.opacity(0.25))
                        .frame(width: dot == step ? 26 : 8, height: 8)
                        .animation(.easeInOut(duration: 0.18), value: step)
                }
            }

            HStack(spacing: 10) {
                Button("Back") {
                    store.backTutorial()
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.faintText)
                .frame(width: 92)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(uiColor: .separator).opacity(0.22), lineWidth: 1))
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0.55)

                Button(step.primaryButtonTitle) {
                    if step == .done { store.completeTutorial() }
                    else { store.advanceTutorial() }
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .padding(.top, 6)
        .background(.ultraThinMaterial)
    }

    private func tourChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(tint.opacity(0.95))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.18), in: Capsule())
    }

    private func mockFilterChip(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.faintText)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.faintText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AppTheme.cardStrong, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
        )
    }

    private func miniStatCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.faintText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 72)
        .padding(10)
        .background(AppTheme.cardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
        )
    }

    private func insightsMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.faintText)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.cardStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
        )
    }

    private func mockSegment(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? Color.white : AppTheme.cardStrong, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(selected ? 0.22 : 0.12), lineWidth: 1)
            )
    }

    private func mockLedgerRow(_ title: String, _ category: String, _ amount: String, date: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                HStack(spacing: 6) {
                    CategoryDot(category: category)
                    Text(category)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.faintText)
                    Text("• \(date)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.faintText)
                }
            }
            Spacer()
            Text(amount)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1))
    }

    private func onboardingLegendRow(_ segment: OnboardingDonutSegment) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(segment.color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(segment.category)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(segment.percentText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.faintText)
            }
            Spacer(minLength: 8)
            Text(segment.amount)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func checklistRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.success)
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
        }
    }
}

private struct OnboardingParticleField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let particles: [OnboardingParticle] = (0..<34).map { _ in
        OnboardingParticle(
            x: .random(in: 0...1),
            y: .random(in: 0...1),
            xVelocity: .random(in: -0.006...0.006),
            yVelocity: .random(in: -0.008...0.008)
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.2 : 1.0 / 30.0)) { context in
            Canvas { canvas, size in
                let t = CGFloat(context.date.timeIntervalSinceReferenceDate)
                let dotRadius: CGFloat = 3.8
                let connectionDistance: CGFloat = 92
                let points: [CGPoint] = particles.map { particle in
                    let x = wrapped(base: particle.x + (reduceMotion ? 0 : particle.xVelocity * t))
                    let y = wrapped(base: particle.y + (reduceMotion ? 0 : particle.yVelocity * t))
                    return CGPoint(x: x * size.width, y: y * size.height)
                }

                for i in points.indices {
                    for j in points.indices where j > i {
                        let dx = points[i].x - points[j].x
                        let dy = points[i].y - points[j].y
                        let distance = sqrt(dx * dx + dy * dy)
                        guard distance < connectionDistance else { continue }
                        let strength = 1 - (distance / connectionDistance)
                        var connection = Path()
                        connection.move(to: points[i])
                        connection.addLine(to: points[j])
                        canvas.stroke(
                            connection,
                            with: .color(Color(uiColor: .systemTeal).opacity(0.03 + (0.09 * strength))),
                            lineWidth: 0.9
                        )
                    }
                }

                for point in points {
                    let rect = CGRect(
                        x: point.x - dotRadius,
                        y: point.y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )

                    canvas.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color(uiColor: .systemTeal).opacity(0.20))
                    )
                }
            }
        }
    }

    private func wrapped(base: CGFloat) -> CGFloat {
        var value = base.truncatingRemainder(dividingBy: 1)
        if value < 0 { value += 1 }
        return value
    }
}

private struct OnboardingParticle {
    let x: CGFloat
    let y: CGFloat
    let xVelocity: CGFloat
    let yVelocity: CGFloat
}

private struct OnboardingDonutSegment: Identifiable {
    let id = UUID()
    let category: String
    let amount: String
    let ratio: Double
    let color: Color

    var percentText: String {
        "\(Int((ratio * 100).rounded()))%"
    }
}

private struct OnboardingDonutChartView: View {
    let segments: [OnboardingDonutSegment]
    let centerTitle: String
    let centerSubtitle: String

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let ringThickness = max(18, size * 0.16)
            let inset = ringThickness / 2

            ZStack {
                Circle()
                    .stroke(Color(uiColor: .systemGray5), lineWidth: ringThickness)

                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    let start = startAngle(for: index)
                    let end = start + .degrees(max(2, 360 * segment.ratio))
                    OnboardingDonutArc(startAngle: start, endAngle: end)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: ringThickness, lineCap: .round))
                        .padding(inset)
                }

                VStack(spacing: 4) {
                    Text(centerTitle)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                    Text(centerSubtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func startAngle(for index: Int) -> Angle {
        let previousRatio = segments.prefix(index).reduce(0.0) { $0 + $1.ratio }
        return .degrees(-90 + (360 * previousRatio))
    }
}

private struct OnboardingDonutArc: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}
