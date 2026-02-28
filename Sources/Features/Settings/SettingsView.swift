import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var authStore: AuthStore

    @State private var showingCategoryBankPicker = false
    @State private var isEditingCategories = false
    @State private var newTripName = ""
    @State private var newPaymentMethodName = ""
    @State private var newPaymentMethodAliases = ""
    @State private var selectedBudgetCategory: String = "Food"
    @State private var budgetLimitText = ""
    @State private var backupExportDocument = BackupJSONDocument(data: Data())
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var csvShareItem: CSVShareItem?
    @State private var backupActionMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                accountCard
                preferencesCard
                budgetsCard
                categoriesCard
                tripsCard
                paymentMethodsCard
                syncCard
                dataCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(AppCanvasBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let firstCategory = store.categories.first {
                selectedBudgetCategory = firstCategory
            }
        }
        .fileExporter(
            isPresented: $isExportingBackup,
            document: backupExportDocument,
            contentType: .json,
            defaultFilename: "speakance-backup-\(exportDateStamp)"
        ) { result in
            switch result {
            case .success:
                backupActionMessage = "Backup exported."
            case let .failure(error):
                backupActionMessage = "Backup export failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case let .success(url):
                do {
                    let access = url.startAccessingSecurityScopedResource()
                    defer {
                        if access { url.stopAccessingSecurityScopedResource() }
                    }
                    let data = try Data(contentsOf: url)
                    try store.importBackupJSONData(data)
                    backupActionMessage = "Backup imported."
                } catch {
                    backupActionMessage = "Backup import failed: \(error.localizedDescription)"
                }
            case let .failure(error):
                backupActionMessage = "Backup import cancelled: \(error.localizedDescription)"
            }
        }
        .sheet(item: $csvShareItem) { item in
            ActivityShareSheet(activityItems: [item.url])
        }
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
                    Menu {
                        ForEach(AppStore.supportedCurrencyCodes, id: \.self) { code in
                            Button(code) { store.setDefaultCurrencyCode(code) }
                        }
                    } label: {
                        HStack {
                            Text(store.defaultCurrencyCode)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.faintText)
                        }
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AppTheme.cardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(uiColor: .separator).opacity(0.20), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Voice / parser language")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.faintText)
                    Menu {
                        ForEach(AppStore.supportedParsingLanguages, id: \.rawValue) { language in
                            Button(language.title) { store.setParsingLanguage(language) }
                        }
                    } label: {
                        HStack {
                            Text(store.parsingLanguage.title)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.faintText)
                        }
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AppTheme.cardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(uiColor: .separator).opacity(0.20), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    MetricChip(title: "Voice / day", value: "\(store.dailyVoiceLimit)", tint: AppTheme.sky)
                    MetricChip(title: "Max length", value: "\(store.maxVoiceCaptureSeconds)s", tint: AppTheme.butter)
                }
            }
        }
    }

    private var budgetsCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Budget Guardrails", subtitle: "Monthly category limits and overage alerts")

                HStack(spacing: 10) {
                    Menu {
                        ForEach(store.categories, id: \.self) { category in
                            Button(category) {
                                selectedBudgetCategory = category
                            }
                        }
                    } label: {
                        HStack {
                            Text(selectedBudgetCategory)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AppTheme.cardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(uiColor: .separator).opacity(0.20), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    TextField("Limit", text: $budgetLimitText)
                        .keyboardType(.decimalPad)
                        .modernField()
                        .frame(width: 120)
                }

                Button {
                    store.setBudgetLimit(categoryName: selectedBudgetCategory, monthlyLimitText: budgetLimitText)
                    budgetLimitText = ""
                } label: {
                    Label("Save Budget", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(budgetLimitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(budgetLimitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)

                if store.activeBudgetRules.isEmpty {
                    Text("No budgets configured yet.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.faintText)
                } else {
                    ForEach(store.budgetSnapshot()) { snapshot in
                        budgetRow(snapshot)
                    }
                }
            }
        }
    }

    private var categoriesCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Categories")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Text("Choose from curated categories for better parsing")
                            .font(.caption)
                            .foregroundStyle(AppTheme.faintText)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        iconCircleButton(systemName: "plus") {
                            showingCategoryBankPicker = true
                        }
                        .disabled(availableCategoryBank.isEmpty)
                        .opacity(availableCategoryBank.isEmpty ? 0.45 : 1)

                        iconCircleButton(systemName: isEditingCategories ? "checkmark" : "pencil") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isEditingCategories.toggle()
                            }
                        }
                    }
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
                            if isEditingCategories && category.name.caseInsensitiveCompare("Other") != .orderedSame {
                                Button(role: .destructive) { store.removeCategory(category.id) } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AppTheme.error)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if availableCategoryBank.isEmpty {
                    Text("All suggested categories are already added.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.faintText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
        }
        .confirmationDialog("Add Category", isPresented: $showingCategoryBankPicker, titleVisibility: .visible) {
            ForEach(availableCategoryBank, id: \.name) { template in
                Button(template.name) {
                    store.addCategory(name: template.name, hints: template.hints)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose from the curated category bank.")
        }
    }

    private func iconCircleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 34, height: 34)
                .background(AppTheme.cardStrong, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var availableCategoryBank: [CategoryBankTemplate] {
        let existing = Set(store.categoryDefinitions.map { $0.name.lowercased() })
        return Self.categoryBank.filter { !existing.contains($0.name.lowercased()) }
    }

    private static let categoryBank: [CategoryBankTemplate] = [
        .init(name: "Food", hints: ["restaurant, cafe, coffee, meal, lunch, dinner, breakfast"]),
        .init(name: "Groceries", hints: ["grocery, groceries, supermarket, market, costco, walmart"]),
        .init(name: "Transport", hints: ["uber, lyft, taxi, bus, train, metro, gas, fuel, toll, parking"]),
        .init(name: "Shopping", hints: ["shopping, amazon, clothes, shoes, mall, store"]),
        .init(name: "Utilities", hints: ["bill, electricity, internet, phone, water, utility, insurance"]),
        .init(name: "Entertainment", hints: ["movie, concert, games, nightclub, club, bar, table, bottle, cover"]),
        .init(name: "Subscriptions", hints: ["subscription, monthly, netflix, spotify, icloud, membership"])
    ]

    private var tripsCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Trips", subtitle: "Use active trips to group travel expenses")

                TextField("Trip name", text: $newTripName)
                    .modernField()

                HStack(spacing: 10) {
                    Button {
                        store.addTrip(name: newTripName, setActive: true)
                        newTripName = ""
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
                TextField("Aliases (comma-separated, e.g. amex, gold)", text: $newPaymentMethodAliases)
                    .modernField()

                Button {
                    store.addPaymentMethod(name: newPaymentMethodName, aliases: [newPaymentMethodAliases])
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
                                Text(methodAliasSummary(method))
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

                HStack(spacing: 10) {
                    MetricChip(title: "Pending", value: "\(store.queuedCaptures.filter { $0.status == .pending || $0.status == .syncing }.count)", tint: AppTheme.butter)
                    MetricChip(title: "Failed", value: "\(store.queuedCaptures.filter { $0.status == .failed }.count)", tint: AppTheme.coral)
                }

                if store.isSyncingQueue {
                    ProgressView("Syncing queue...")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }

                if let syncedAt = store.lastQueueSyncSuccessAt {
                    Text("Last successful sync: \(syncedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.faintText)
                } else if let attempted = store.lastQueueSyncAttemptAt {
                    Text("Last sync attempt: \(attempted.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.faintText)
                }

                if let operationalError = store.lastOperationalErrorMessage {
                    Text(operationalError)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.error)
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

    private var dataCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Data", subtitle: "Export CSV and backup/restore local data")

                Button {
                    exportCSVForSharing()
                } label: {
                    Label("Export Expenses CSV", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(AppTheme.ink.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Button {
                        do {
                            backupExportDocument = try BackupJSONDocument(data: store.makeBackupJSONData())
                            isExportingBackup = true
                        } catch {
                            backupActionMessage = "Backup export failed: \(error.localizedDescription)"
                        }
                    } label: {
                        Label("Export Backup", systemImage: "tray.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(AppTheme.ink)
                            .background(AppTheme.cardStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        isImportingBackup = true
                    } label: {
                        Label("Import Backup", systemImage: "tray.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(AppTheme.ink)
                            .background(AppTheme.cardStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                if let backupActionMessage {
                    Text(backupActionMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.faintText)
                }
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

    private func methodAliasSummary(_ method: PaymentMethod) -> String {
        let summary = method.aliases.prefix(3).joined(separator: " • ")
        return summary.isEmpty ? "No aliases" : summary
    }

    private func budgetRow(_ snapshot: BudgetUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(snapshot.rule.categoryName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text("\(CurrencyFormatter.string(snapshot.spent, currency: store.defaultCurrencyCode)) / \(CurrencyFormatter.string(snapshot.rule.monthlyLimit, currency: store.defaultCurrencyCode))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(snapshot.isOverBudget ? AppTheme.error : AppTheme.faintText)
            }

            ProgressView(value: min(1, snapshot.progressRatio))
                .tint(snapshot.isOverBudget ? AppTheme.error : AppTheme.accent)

            HStack {
                Text(snapshot.isOverBudget ? "Over budget" : "Remaining \(CurrencyFormatter.string(snapshot.remaining, currency: store.defaultCurrencyCode))")
                    .font(.caption)
                    .foregroundStyle(snapshot.isOverBudget ? AppTheme.error : AppTheme.faintText)
                Spacer()
                Button(role: .destructive) {
                    store.removeBudgetRule(snapshot.rule.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var exportDateStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }

    private func exportCSVForSharing() {
        do {
            let csv = store.exportExpensesCSV()
            guard let data = csv.data(using: .utf8) else {
                backupActionMessage = "CSV export failed: could not encode text."
                return
            }
            let filename = "speakance-expenses-\(exportDateStamp)-\(UUID().uuidString.prefix(8)).csv"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            csvShareItem = CSVShareItem(url: url)
        } catch {
            backupActionMessage = "CSV export failed: \(error.localizedDescription)"
        }
    }
}

private struct CategoryBankTemplate {
    let name: String
    let hints: [String]
}

private struct BackupJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct CSVShareItem: Identifiable {
    let id = UUID()
    let url: URL
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
