import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var authStore: AuthStore

    @State private var defaultCurrency = "USD"
    @State private var newCategoryName = ""
    @State private var newCategoryHints = ""
    @State private var newTripName = ""
    @State private var newTripDestination = ""
    @State private var newPaymentMethodName = ""
    @State private var newPaymentMethodAliases = ""
    @State private var newPaymentMethodType: PaymentMethodType = .creditCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                accountCard
                preferencesCard
                categoriesCard
                tripsCard
                paymentMethodsCard
                syncCard
                aboutCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(AppCanvasBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var accountCard: some View {
        if authStore.isConfigured {
            SpeakCard(padding: 16, cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Account", subtitle: "Authentication and session")

                    if case let .signedIn(session) = authStore.state {
                        settingsRow("Email", session.userEmail ?? "Signed in")
                    } else {
                        settingsRow("Status", "Signed out")
                    }

                    Button {
                        Task { await authStore.signOut() }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .foregroundStyle(AppTheme.error)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.error.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppTheme.error.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(authStore.isWorking)
                }
            }
        }
    }

    private var headerCard: some View {
        SpeakCard(padding: 18, cornerRadius: 26, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.accent, AppTheme.accentDeep],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 52, height: 52)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    StatusPill(
                        text: store.isConnected ? "Connected" : "Offline",
                        color: store.isConnected ? AppTheme.success : AppTheme.warning
                    )
                }

                Text("Settings")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text("Configure categories, trips, and payment methods to personalize parsing and analytics.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.muted)
            }
        }
    }

    private var preferencesCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Preferences", subtitle: "Capture defaults and app behavior")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Default currency")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.faintText)
                    TextField("USD", text: $defaultCurrency)
                        .textInputAutocapitalization(.characters)
                        .modernField()
                }

                HStack(spacing: 10) {
                    MetricChip(title: "Voice / day", value: "50", tint: AppTheme.sky)
                    MetricChip(title: "Max length", value: "15s", tint: AppTheme.butter)
                }
            }
        }
    }

    private var categoriesCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Categories", subtitle: "Custom categories + parser hints")

                VStack(alignment: .leading, spacing: 8) {
                    TextField("New category (e.g. Hobbies)", text: $newCategoryName)
                        .modernField()
                    TextField("Hint keywords (comma-separated)", text: $newCategoryHints, axis: .vertical)
                        .lineLimit(2...4)
                        .modernField()
                    Button {
                        store.addCategory(name: newCategoryName, hints: [newCategoryHints])
                        newCategoryName = ""
                        newCategoryHints = ""
                    } label: {
                        Label("Add Category", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
                }

                ForEach(store.categoryDefinitions) { category in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            HStack(spacing: 8) {
                                CategoryDot(category: category.name)
                                Text(category.name)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                            Spacer()
                            if category.name.caseInsensitiveCompare("Other") != .orderedSame {
                                Button(role: .destructive) { store.removeCategory(category.id) } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                        if !category.hintKeywords.isEmpty {
                            Text(category.hintKeywords.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(AppTheme.faintText)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var tripsCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Trips", subtitle: "Use active trips to group travel expenses")

                TextField("Trip name", text: $newTripName)
                    .modernField()
                TextField("Destination (optional)", text: $newTripDestination)
                    .modernField()

                HStack(spacing: 10) {
                    Button {
                        store.addTrip(name: newTripName, destination: newTripDestination, setActive: true)
                        newTripName = ""
                        newTripDestination = ""
                    } label: {
                        Text("Add + Activate")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(newTripName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if store.activeTrip != nil {
                        Button("End Active") { store.endActiveTrip() }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppTheme.cardStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1))
                    }
                }

                ForEach(store.trips) { trip in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trip.name)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            if let destination = trip.destination {
                                Text(destination)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.faintText)
                            }
                        }
                        Spacer()
                        if store.activeTripID == trip.id {
                            StatusPill(text: "Active", color: AppTheme.accent)
                        } else {
                            Button("Activate") { store.selectTrip(trip.id) }
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
        }
    }

    private var paymentMethodsCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Payment Methods", subtitle: "Optional cards/cash for filtering and voice parsing")

                TextField("Name (e.g. AMEX Gold)", text: $newPaymentMethodName)
                    .modernField()
                Picker("Type", selection: $newPaymentMethodType) {
                    ForEach(PaymentMethodType.allCases, id: \.self) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Aliases (comma-separated, e.g. amex, gold)", text: $newPaymentMethodAliases)
                    .modernField()

                Button {
                    store.addPaymentMethod(name: newPaymentMethodName, type: newPaymentMethodType, aliases: [newPaymentMethodAliases])
                    newPaymentMethodName = ""
                    newPaymentMethodAliases = ""
                } label: {
                    Label("Add Payment Method", systemImage: "creditcard")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(newPaymentMethodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(newPaymentMethodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)

                if store.paymentMethods.isEmpty {
                    Text("No payment methods added. Expenses will stay unassigned by default.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                } else {
                    ForEach(store.paymentMethods) { method in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(method.name)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                Text(([method.type.title] + method.aliases.prefix(3)).joined(separator: " • "))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.faintText)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                store.removePaymentMethod(method.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var syncCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Offline & Sync", subtitle: "Queue uploads and parser retries")

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Network (debug)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text("Toggle to simulate offline queueing")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.faintText)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { store.isConnected },
                        set: { store.setNetworkConnectivity($0) }
                    ))
                    .labelsHidden()
                    .tint(AppTheme.accent)
                }

                HStack(spacing: 10) {
                    MetricChip(title: "Pending", value: "\(store.queuedCaptures.filter { $0.status == .pending || $0.status == .syncing }.count)", tint: AppTheme.butter)
                    MetricChip(title: "Failed", value: "\(store.queuedCaptures.filter { $0.status == .failed }.count)", tint: AppTheme.coral)
                }

                if store.isSyncingQueue {
                    ProgressView("Syncing queue...")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }

                Button {
                    store.retryFailedQueueItems()
                } label: {
                    Label("Retry Failed Queue Items", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.white)
                        .background(AppTheme.ink.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var aboutCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "About", subtitle: "Feature wave in progress")
                settingsRow("App Name", "Speakance")
                settingsRow("Platform", "iOS")
                settingsRow("Voice Limit (Paid)", "50 / day")
                settingsRow("Recording Length", "15 seconds")
                settingsRow("History", "Editable")
            }
        }
    }

    @ViewBuilder
    private func settingsRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SettingsView()
                .environmentObject(AppStore())
                .environmentObject(AuthStore(client: nil, tokenStore: SharedAccessTokenStore()))
        }
    }
}
