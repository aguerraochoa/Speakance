import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var selectedTab: AppTab = .capture
    @Published var expenses: [ExpenseRecord] = []
    @Published var queuedCaptures: [QueuedCapture] = []
    @Published var activeReview: ReviewContext?
    @Published var isSyncingQueue = false
    @Published var isConnected: Bool
    @Published var lastOperationalErrorMessage: String?
    @Published var lastQueueSyncAttemptAt: Date?
    @Published var lastQueueSyncSuccessAt: Date?
    @Published var shouldShowOnboarding: Bool = false

    @Published var categoryDefinitions: [CategoryDefinition] = []
    @Published var trips: [TripRecord] = []
    @Published var paymentMethods: [PaymentMethod] = []
    @Published var budgetRules: [BudgetRule] = []
    @Published var activeTripID: UUID?
    @Published var defaultCurrencyCode: String = "USD"
    @Published var parsingLanguage: ParsingLanguage = .auto
    @Published var dailyVoiceLimit: Int = AppStore.defaultDailyVoiceLimit
    @Published var recentlyDeletedExpenses: [RecentlyDeletedExpenseEntry] = []

    let networkMonitor: NetworkMonitor
    let audioCaptureService: AudioCaptureService

    private let queueStore: QueueStoreProtocol
    private let expenseLedgerStore: ExpenseLedgerStoreProtocol
    private let apiClient: ExpenseAPIClientProtocol
    private let syncEngine = SyncEngine()
    private let metaStore = LocalMetaStore()
    private let recentlyDeletedStore = LocalRecentlyDeletedStore()
    private var isSyncingMetadata = false
    private var metadataSyncDirty = false

    init(
        queueStore: QueueStoreProtocol = FileQueueStore(),
        expenseLedgerStore: ExpenseLedgerStoreProtocol = FileExpenseLedgerStore(),
        apiClient: ExpenseAPIClientProtocol = MockExpenseAPIClient(),
        networkMonitor: NetworkMonitor? = nil,
        audioCaptureService: AudioCaptureService? = nil
    ) {
        let resolvedNetworkMonitor = networkMonitor ?? NetworkMonitor()
        let resolvedAudioCaptureService = audioCaptureService ?? AudioCaptureService()
        self.queueStore = queueStore
        self.expenseLedgerStore = expenseLedgerStore
        self.apiClient = apiClient
        self.networkMonitor = resolvedNetworkMonitor
        self.audioCaptureService = resolvedAudioCaptureService
        self.isConnected = resolvedNetworkMonitor.isConnected
        self.queuedCaptures = Self.normalizedQueueForStartup(Self.deduplicatedQueue(queueStore.loadQueue()))
        self.expenses = Self.deduplicatedExpenses(expenseLedgerStore.loadExpenses())

        let persistedMeta = metaStore.load()
        self.categoryDefinitions = persistedMeta.categories
        self.trips = persistedMeta.trips
        self.paymentMethods = persistedMeta.paymentMethods
        self.budgetRules = persistedMeta.budgetRules
        self.activeTripID = persistedMeta.activeTripID
        self.defaultCurrencyCode = Self.normalizedCurrencyCode(persistedMeta.defaultCurrencyCode) ?? "USD"
        self.parsingLanguage = Self.normalizedParsingLanguage(persistedMeta.parsingLanguage) ?? .auto
        self.dailyVoiceLimit = Self.normalizedDailyVoiceLimit(persistedMeta.dailyVoiceLimit) ?? Self.defaultDailyVoiceLimit
        self.shouldShowOnboarding = persistedMeta.hasCompletedOnboarding != true
        self.recentlyDeletedExpenses = recentlyDeletedStore.load()
        resolvedAudioCaptureService.setPreferredSpeechLocaleIdentifier(self.parsingLanguage.speechLocaleIdentifier)
        purgeExpiredRecentlyDeletedExpenses()

        resolvedNetworkMonitor.onStatusChange = { [weak self] connected in
            guard let self else { return }
            self.handleNetworkConnectivityChange(connected)
        }

        seedDefaultsIfNeeded()
        Task {
            await refreshCloudStateFromServer()
            await syncQueueIfPossible()
        }
    }

    var categories: [String] {
        categoryDefinitions.map(\.name)
    }

    static let supportedCurrencyCodes = [
        "USD", "MXN", "EUR", "GBP", "CAD", "JPY", "BRL", "COP", "ARS", "CLP", "PEN"
    ]

    static let supportedParsingLanguages: [ParsingLanguage] = [.auto, .english, .spanish]
    static let defaultDailyVoiceLimit = 50

    var activeTrip: TripRecord? {
        guard let activeTripID else { return nil }
        return trips.first(where: { $0.id == activeTripID })
    }

    var activeTripChipText: String {
        activeTrip.map { "\($0.name) • Active" } ?? "No Trip"
    }

    var activeTripFilterOptions: [TripRecord] {
        trips.sorted { $0.createdAt > $1.createdAt }
    }

    var activePaymentMethodOptions: [PaymentMethod] {
        paymentMethods.filter(\.isActive).sorted { $0.createdAt > $1.createdAt }
    }

    var maxVoiceCaptureSeconds: Int {
        audioCaptureService.maxRecordingDurationSeconds
    }

    var activeBudgetRules: [BudgetRule] {
        budgetRules.filter(\.isEnabled).sorted { $0.categoryName.localizedCaseInsensitiveCompare($1.categoryName) == .orderedAscending }
    }

    func startRecording() {
        audioCaptureService.startRecording()
    }

    func stopRecordingAndCreateEntry() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let voiceResult = await audioCaptureService.stopRecording() else { return }
            createVoiceCapture(
                rawText: voiceResult.rawText,
                durationSeconds: voiceResult.durationSeconds,
                localAudioFilePath: voiceResult.localAudioFilePath
            )
        }
    }

    func cancelRecording() {
        audioCaptureService.cancelRecording()
    }

    func createVoiceCapture(rawText: String, durationSeconds: Int, localAudioFilePath: String?) {
        let clientExpenseID = UUID()
        let queueItem = QueuedCapture(
            clientExpenseID: clientExpenseID,
            source: .voice,
            capturedAt: .now,
            localAudioFilePath: localAudioFilePath,
            audioDurationSeconds: durationSeconds,
            rawText: rawText,
            tripID: activeTrip?.id,
            tripName: activeTrip?.name
        )
        queuedCaptures.insert(queueItem, at: 0)
        persistQueue()
        Task { await syncQueueIfPossible() }
    }

    func createTextEntry(rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let queueItem = QueuedCapture(
            clientExpenseID: UUID(),
            source: .text,
            capturedAt: .now,
            rawText: trimmed,
            tripID: activeTrip?.id,
            tripName: activeTrip?.name
        )
        queuedCaptures.insert(queueItem, at: 0)
        persistQueue()
        Task { await syncQueueIfPossible() }
    }

    func syncQueueIfPossible() async {
        guard await syncEngine.canSync(networkIsConnected: isConnected) else { return }
        guard !isSyncingQueue else { return }

        lastQueueSyncAttemptAt = .now
        isSyncingQueue = true
        var hadFailure = false
        var processedAnyItem = false
        defer {
            isSyncingQueue = false
            if processedAnyItem && !hadFailure {
                lastQueueSyncSuccessAt = .now
            }
            persistQueue()
        }

        let queueIDs = queuedCaptures.map(\.id)
        for queueID in queueIDs {
            guard let index = queuedCaptures.firstIndex(where: { $0.id == queueID }) else { continue }
            if queuedCaptures[index].status != .pending { continue }
            processedAnyItem = true

            queuedCaptures[index].status = .syncing
            queuedCaptures[index].lastError = nil

            do {
                guard let rawText = queuedCaptures[index].rawText else {
                    throw AppError.missingRawText
                }
                let request = ParseExpenseRequestDTO(
                    clientExpenseID: queuedCaptures[index].clientExpenseID,
                    source: queuedCaptures[index].source,
                    capturedAtDevice: queuedCaptures[index].capturedAt,
                    audioDurationSeconds: queuedCaptures[index].audioDurationSeconds,
                    localAudioFilePath: queuedCaptures[index].localAudioFilePath,
                    rawText: rawText,
                    currencyHint: defaultCurrencyCode,
                    languageHint: parsingLanguage.apiHint,
                    timezone: TimeZone.current.identifier,
                    tripID: queuedCaptures[index].tripID,
                    tripName: queuedCaptures[index].tripName,
                    paymentMethodID: queuedCaptures[index].paymentMethodID,
                    paymentMethodName: queuedCaptures[index].paymentMethodName
                )
                let response = try await apiClient.parseExpense(request)
                var draft = response.draft
                draft.tripID = queuedCaptures[index].tripID
                draft.tripName = queuedCaptures[index].tripName
                draft.paymentMethodID = queuedCaptures[index].paymentMethodID
                draft.paymentMethodName = queuedCaptures[index].paymentMethodName

                autoDetectPaymentMethodIfNeeded(&draft)
                autoAssignCategoryIDIfNeeded(&draft)
                autoAssignCurrencyIfNeeded(&draft)
                autoAssignExpenseDateIfNeeded(&draft)

                queuedCaptures[index].parsedDraft = draft
                queuedCaptures[index].serverExpenseID = response.serverExpenseID

                switch response.status {
                case .saved:
                    saveParsedDraft(draft, queueID: queuedCaptures[index].id, existingExpenseID: nil, markAsEdited: false)
                    if let savedIndex = queuedCaptures.firstIndex(where: { $0.id == queuedCaptures[index].id }) {
                        queuedCaptures[savedIndex].status = .saved
                        cleanupLocalAudioFileIfNeeded(for: queuedCaptures[savedIndex])
                        queuedCaptures[savedIndex].localAudioFilePath = nil
                    }
                case .needsReview:
                    queuedCaptures[index].status = .needsReview
                    logOperationalInfo("Queue item requires review", details: [
                        "queueID": queuedCaptures[index].id.uuidString,
                        "clientExpenseID": queuedCaptures[index].clientExpenseID.uuidString
                    ])
                case .pending, .syncing, .failed:
                    queuedCaptures[index].status = .failed
                    queuedCaptures[index].lastError = "Unexpected parser state"
                    hadFailure = true
                    logOperationalError("Unexpected parser state during sync", details: [
                        "queueID": queuedCaptures[index].id.uuidString
                    ])
                }
            } catch {
                if Self.isAuthenticationError(error) {
                    // Keep items pending when auth is missing/expired so they can recover after sign-in.
                    queuedCaptures[index].status = .pending
                    queuedCaptures[index].lastError = error.localizedDescription
                    hadFailure = true
                    logOperationalError("Queue sync paused (auth required)", details: [
                        "queueID": queuedCaptures[index].id.uuidString,
                        "clientExpenseID": queuedCaptures[index].clientExpenseID.uuidString,
                        "error": error.localizedDescription
                    ])
                    break
                }

                queuedCaptures[index].status = .failed
                queuedCaptures[index].retryCount += 1
                queuedCaptures[index].lastError = error.localizedDescription
                hadFailure = true
                logOperationalError("Queue sync failed", details: [
                    "queueID": queuedCaptures[index].id.uuidString,
                    "clientExpenseID": queuedCaptures[index].clientExpenseID.uuidString,
                    "error": error.localizedDescription
                ])
            }
        }
    }

    func retryFailedQueueItems() {
        for idx in queuedCaptures.indices where queuedCaptures[idx].status == .failed || queuedCaptures[idx].status == .pending {
            queuedCaptures[idx].status = .pending
            queuedCaptures[idx].lastError = nil
        }
        persistQueue()
        Task { await syncQueueIfPossible() }
    }

    func retryQueueItem(_ queueID: UUID) {
        guard let idx = queuedCaptures.firstIndex(where: { $0.id == queueID }) else { return }
        guard queuedCaptures[idx].status == .failed || queuedCaptures[idx].status == .pending else { return }
        queuedCaptures[idx].status = .pending
        queuedCaptures[idx].lastError = nil
        persistQueue()
        Task { await syncQueueIfPossible() }
    }

    func openReview(for queueItem: QueuedCapture) {
        guard let draft = queueItem.parsedDraft else { return }
        activeReview = ReviewContext(queueID: queueItem.id, draft: draft)
    }

    func openReview(for expense: ExpenseRecord) {
        var draft = ExpenseDraft(
            clientExpenseID: expense.clientExpenseID,
            amountText: NSDecimalNumber(decimal: expense.amount).stringValue,
            currency: expense.currency,
            category: expense.category,
            categoryID: expense.categoryID,
            description: expense.description ?? "",
            merchant: expense.merchant ?? "",
            tripID: expense.tripID,
            tripName: expense.tripName,
            paymentMethodID: expense.paymentMethodID,
            paymentMethodName: expense.paymentMethodName,
            expenseDate: expense.expenseDate,
            rawText: expense.rawText ?? "",
            source: expense.source,
            parseConfidence: expense.parseConfidence
        )
        autoAssignCategoryIDIfNeeded(&draft)
        activeReview = ReviewContext(expenseID: expense.id, draft: draft)
    }

    func saveReview(_ context: ReviewContext) {
        let previousDescription: String? = {
            if let expenseID = context.expenseID {
                return expenses.first(where: { $0.id == expenseID })?.description
            }
            if let queueID = context.queueID {
                return queuedCaptures.first(where: { $0.id == queueID })?.parsedDraft?.description
            }
            return nil
        }()

        var normalizedDraft = context.draft
        normalizedDraft.amountText = Self.normalizedAmountText(normalizedDraft.amountText)
        normalizedDraft.rawText = Self.rewrittenRawAmountText(
            in: normalizedDraft.rawText,
            amountText: normalizedDraft.amountText
        )
        normalizedDraft.rawText = Self.rewrittenRawDescriptionText(
            in: normalizedDraft.rawText,
            previousDescription: previousDescription,
            newDescription: normalizedDraft.description
        )

        saveParsedDraft(normalizedDraft, queueID: context.queueID, existingExpenseID: context.expenseID, markAsEdited: true)
        if let expenseID = context.expenseID {
            Task { [apiClient] in
                do {
                    try await apiClient.updateExpense(UpdateExpenseRequestDTO(expenseID: expenseID, draft: normalizedDraft))
                } catch {
                    await MainActor.run {
                        lastOperationalErrorMessage = "Could not update expense on server. Local changes were kept."
                        #if DEBUG
                        print("[Speakance] remote expense update failed id=\(expenseID.uuidString): \(error.localizedDescription)")
                        #endif
                    }
                }
            }
        }
        if let queueID = context.queueID, let idx = queuedCaptures.firstIndex(where: { $0.id == queueID }) {
            cleanupLocalAudioFileIfNeeded(for: queuedCaptures[idx])
            queuedCaptures[idx].localAudioFilePath = nil
            queuedCaptures[idx].status = .saved
        }
        activeReview = nil
        persistQueue()
    }

    func dismissReview() {
        activeReview = nil
    }

    func deleteQueueItem(_ item: QueuedCapture) {
        guard canDeleteQueueItem(item) else { return }
        if let idx = queuedCaptures.firstIndex(where: { $0.id == item.id }) {
            let removed = queuedCaptures.remove(at: idx)
            cleanupLocalAudioFileIfNeeded(for: removed)
            persistQueue()

            if activeReview?.queueID == removed.id {
                activeReview = nil
            }
        }
    }

    func canDeleteQueueItem(_ item: QueuedCapture) -> Bool {
        let hasLinkedExpense = expenses.contains { expense in
            if expense.clientExpenseID == item.clientExpenseID { return true }
            if let serverExpenseID = item.serverExpenseID, expense.id == serverExpenseID { return true }
            return false
        }
        return !hasLinkedExpense
    }

    func deleteExpense(_ expense: ExpenseRecord) {
        let removedQueueEntries = queuedCaptures
            .enumerated()
            .filter { _, item in
                item.clientExpenseID == expense.clientExpenseID || item.serverExpenseID == expense.id
            }
        let snapshot = RecentlyDeletedExpenseEntry(
            expense: expense,
            queueEntries: removedQueueEntries.map(\.element)
        )

        expenses.removeAll { $0.id == expense.id }
        persistExpenses()
        if !removedQueueEntries.isEmpty {
            let removedQueueIDs = Set(removedQueueEntries.map { $0.element.id })
            queuedCaptures.removeAll { removedQueueIDs.contains($0.id) }
            persistQueue()
        }
        for entry in removedQueueEntries {
            cleanupLocalAudioFileIfNeeded(for: entry.element)
        }
        addRecentlyDeleted(snapshot)
    }

    func restoreRecentlyDeletedExpense(_ expenseID: UUID) {
        guard let idx = recentlyDeletedExpenses.firstIndex(where: { $0.id == expenseID }) else { return }
        let entry = recentlyDeletedExpenses.remove(at: idx)

        if !expenses.contains(where: { $0.id == entry.expense.id }) {
            expenses.insert(entry.expense, at: 0)
            persistExpenses()
        }

        if !entry.queueEntries.isEmpty {
            var didRestoreQueue = false
            for queueEntry in entry.queueEntries {
                guard !queuedCaptures.contains(where: { $0.id == queueEntry.id }) else { continue }
                queuedCaptures.insert(queueEntry, at: 0)
                didRestoreQueue = true
            }
            if didRestoreQueue {
                persistQueue()
            }
        }
        persistRecentlyDeletedExpenses()
    }

    func permanentlyDeleteRecentlyDeletedExpense(_ expenseID: UUID) {
        guard let entry = recentlyDeletedExpenses.first(where: { $0.id == expenseID }) else { return }
        recentlyDeletedExpenses.removeAll { $0.id == expenseID }
        persistRecentlyDeletedExpenses()
        Task { [apiClient] in
            do {
                try await apiClient.deleteExpense(entry.expense.id)
            } catch {
                await MainActor.run {
                    recentlyDeletedExpenses.insert(entry, at: 0)
                    persistRecentlyDeletedExpenses()
                    lastOperationalErrorMessage = "Could not permanently delete expense on server."
                }
            }
        }
    }

    func clearAllRecentlyDeletedExpenses() {
        let entries = recentlyDeletedExpenses
        guard !entries.isEmpty else { return }
        recentlyDeletedExpenses.removeAll()
        persistRecentlyDeletedExpenses()

        Task { [apiClient] in
            var failed: [RecentlyDeletedExpenseEntry] = []
            for entry in entries {
                do {
                    try await apiClient.deleteExpense(entry.expense.id)
                } catch {
                    failed.append(entry)
                }
            }

            guard !failed.isEmpty else { return }
            await MainActor.run {
                recentlyDeletedExpenses = failed + recentlyDeletedExpenses
                persistRecentlyDeletedExpenses()
                lastOperationalErrorMessage = "Some items could not be permanently deleted on server."
            }
        }
    }

    func setDefaultCurrencyCode(_ code: String) {
        guard let normalized = Self.normalizedCurrencyCode(code) else { return }
        guard defaultCurrencyCode != normalized else { return }
        defaultCurrencyCode = normalized
        persistMeta()
        scheduleMetadataSync()
    }

    func setParsingLanguage(_ language: ParsingLanguage) {
        guard parsingLanguage != language else { return }
        parsingLanguage = language
        audioCaptureService.setPreferredSpeechLocaleIdentifier(language.speechLocaleIdentifier)
        persistMeta()
    }

    func refreshCloudStateFromServer() async {
        await refreshMetadataFromServer()
        await refreshExpensesFromServer()
    }

    func selectTrip(_ tripID: UUID?) {
        activeTripID = tripID
        if let id = tripID, let idx = trips.firstIndex(where: { $0.id == id }) {
            for tripIndex in trips.indices where trips[tripIndex].status == .active && trips[tripIndex].id != id {
                trips[tripIndex].status = .completed
            }
            trips[idx].status = .active
        }
        persistMeta()
        scheduleMetadataSync()
    }

    func endActiveTrip() {
        if let activeTripID, let idx = trips.firstIndex(where: { $0.id == activeTripID }) {
            trips[idx].status = .completed
            if trips[idx].endDate == nil { trips[idx].endDate = .now }
        }
        self.activeTripID = nil
        persistMeta()
        scheduleMetadataSync()
    }

    func addTrip(name: String, destination: String = "", startDate: Date = .now, endDate: Date? = nil, baseCurrency: String? = nil, setActive: Bool = true) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let trip = TripRecord(name: trimmed, destination: destination.nilIfBlank, startDate: startDate, endDate: endDate, baseCurrency: baseCurrency?.nilIfBlank, status: setActive ? .active : .planned)
        if setActive {
            for idx in trips.indices where trips[idx].status == .active { trips[idx].status = .completed }
            activeTripID = trip.id
        }
        trips.insert(trip, at: 0)
        persistMeta()
        scheduleMetadataSync()
    }

    func addCategory(name: String, colorHex: String? = nil, hints: [String] = []) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !categoryDefinitions.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        categoryDefinitions.append(CategoryDefinition(name: trimmed, colorHex: colorHex, isDefault: false, hintKeywords: normalizeKeywords(hints)))
        categoryDefinitions.sort { ($0.isDefault ? 0 : 1, $0.name.lowercased()) < ($1.isDefault ? 0 : 1, $1.name.lowercased()) }
        persistMeta()
        scheduleMetadataSync()
    }

    func updateCategory(_ categoryID: UUID, name: String, hints: [String]) {
        guard let idx = categoryDefinitions.firstIndex(where: { $0.id == categoryID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        categoryDefinitions[idx].name = trimmed
        categoryDefinitions[idx].hintKeywords = normalizeKeywords(hints)
        // Keep historical expenses readable by replacing display text locally.
        for expenseIndex in expenses.indices where expenses[expenseIndex].categoryID == categoryID {
            expenses[expenseIndex].category = trimmed
            expenses[expenseIndex].updatedAt = .now
        }
        persistExpenses()
        persistMeta()
        scheduleMetadataSync()
    }

    func removeCategory(_ categoryID: UUID) {
        guard let category = categoryDefinitions.first(where: { $0.id == categoryID }) else { return }
        guard category.name.caseInsensitiveCompare("Other") != .orderedSame else { return }
        categoryDefinitions.removeAll { $0.id == categoryID }
        for idx in expenses.indices where expenses[idx].categoryID == categoryID {
            expenses[idx].categoryID = nil
            expenses[idx].category = "Other"
            expenses[idx].parseStatus = .edited
            expenses[idx].updatedAt = .now
        }
        persistExpenses()
        persistMeta()
        scheduleMetadataSync()
    }

    func addPaymentMethod(name: String, network: String? = nil, last4: String? = nil, aliases: [String] = []) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let method = PaymentMethod(
            name: trimmed,
            network: network?.nilIfBlank,
            last4: last4?.nilIfBlank,
            aliases: normalizeKeywords(aliases)
        )
        paymentMethods.insert(method, at: 0)
        persistMeta()
        scheduleMetadataSync()
    }

    func updatePaymentMethod(_ updated: PaymentMethod) {
        guard let idx = paymentMethods.firstIndex(where: { $0.id == updated.id }) else { return }
        paymentMethods[idx] = updated
        for expenseIndex in expenses.indices where expenses[expenseIndex].paymentMethodID == updated.id {
            expenses[expenseIndex].paymentMethodName = updated.name
            expenses[expenseIndex].updatedAt = .now
        }
        persistExpenses()
        persistMeta()
        scheduleMetadataSync()
    }

    func removePaymentMethod(_ id: UUID) {
        paymentMethods.removeAll { $0.id == id }
        for idx in expenses.indices where expenses[idx].paymentMethodID == id {
            expenses[idx].paymentMethodID = nil
            expenses[idx].paymentMethodName = nil
            expenses[idx].updatedAt = .now
        }
        persistExpenses()
        persistMeta()
        scheduleMetadataSync()
    }

    func setBudgetLimit(categoryName: String, monthlyLimitText: String) {
        let normalizedCategory = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCategory.isEmpty else { return }

        let normalizedAmount = monthlyLimitText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard let amount = Decimal(string: normalizedAmount), amount > 0 else { return }
        if let idx = budgetRules.firstIndex(where: { $0.categoryName.caseInsensitiveCompare(normalizedCategory) == .orderedSame }) {
            budgetRules[idx].categoryName = normalizedCategory
            budgetRules[idx].monthlyLimit = amount
            budgetRules[idx].isEnabled = true
        } else {
            budgetRules.append(BudgetRule(categoryName: normalizedCategory, monthlyLimit: amount, isEnabled: true))
        }
        budgetRules.sort { $0.categoryName.localizedCaseInsensitiveCompare($1.categoryName) == .orderedAscending }
        persistMeta()
    }

    func removeBudgetRule(_ id: UUID) {
        budgetRules.removeAll { $0.id == id }
        persistMeta()
    }

    func budgetUsage(for categoryName: String, in month: Date = .now) -> Decimal {
        let calendar = Calendar.current
        return expenses
            .filter {
                $0.category.caseInsensitiveCompare(categoryName) == .orderedSame &&
                calendar.isDate($0.expenseDate, equalTo: month, toGranularity: .month)
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    func budgetSnapshot(in month: Date = .now) -> [BudgetUsageSnapshot] {
        activeBudgetRules.compactMap { rule in
            let spent = budgetUsage(for: rule.categoryName, in: month)
            return BudgetUsageSnapshot(rule: rule, spent: spent)
        }
        .sorted { lhs, rhs in
            if lhs.progressRatio != rhs.progressRatio { return lhs.progressRatio > rhs.progressRatio }
            return lhs.rule.categoryName.localizedCaseInsensitiveCompare(rhs.rule.categoryName) == .orderedAscending
        }
    }

    var budgetAlerts: [BudgetUsageSnapshot] {
        budgetSnapshot().filter { $0.progressRatio >= 0.8 }
    }

    func markOnboardingCompleted() {
        shouldShowOnboarding = false
        persistMeta()
    }

    func resetOnboardingForDebug() {
        shouldShowOnboarding = true
        persistMeta()
    }

    func exportExpensesCSV() -> String {
        let sorted = expenses.sorted { lhs, rhs in
            if lhs.expenseDate == rhs.expenseDate { return lhs.updatedAt > rhs.updatedAt }
            return lhs.expenseDate > rhs.expenseDate
        }
        var rows: [String] = []
        rows.append("expense_id,client_expense_id,expense_date,amount,currency,category,description,merchant,payment_method,trip,source,parse_status,raw_text,captured_at_device,updated_at")
        for item in sorted {
            let row = [
                item.id.uuidString,
                item.clientExpenseID.uuidString,
                Self.csvDateTimeFormatter.string(from: item.expenseDate),
                NSDecimalNumber(decimal: item.amount).stringValue,
                item.currency,
                item.category,
                item.description ?? "",
                item.merchant ?? "",
                item.paymentMethodName ?? "",
                item.tripName ?? "",
                item.source.rawValue,
                item.parseStatus.rawValue,
                item.rawText ?? "",
                Self.csvDateTimeFormatter.string(from: item.capturedAtDevice),
                Self.csvDateTimeFormatter.string(from: item.updatedAt),
            ].map(Self.escapeCSVField)
            rows.append(row.joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    func makeBackupJSONData() throws -> Data {
        let payload = LocalBackupPayload(
            exportedAt: .now,
            expenses: expenses,
            queuedCaptures: queuedCaptures,
            categories: categoryDefinitions,
            trips: trips,
            paymentMethods: paymentMethods,
            budgetRules: budgetRules,
            activeTripID: activeTripID,
            defaultCurrencyCode: defaultCurrencyCode,
            parsingLanguage: parsingLanguage.rawValue,
            recentlyDeletedExpenses: recentlyDeletedExpenses
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(payload)
    }

    func importBackupJSONData(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(LocalBackupPayload.self, from: data)

        expenses = Self.deduplicatedExpenses(payload.expenses)
        queuedCaptures = Self.normalizedQueueForStartup(Self.deduplicatedQueue(payload.queuedCaptures))
        categoryDefinitions = payload.categories
        trips = payload.trips
        paymentMethods = payload.paymentMethods
        budgetRules = payload.budgetRules
        activeTripID = payload.activeTripID
        defaultCurrencyCode = Self.normalizedCurrencyCode(payload.defaultCurrencyCode) ?? "USD"
        parsingLanguage = Self.normalizedParsingLanguage(payload.parsingLanguage) ?? .auto
        audioCaptureService.setPreferredSpeechLocaleIdentifier(parsingLanguage.speechLocaleIdentifier)
        recentlyDeletedExpenses = payload.recentlyDeletedExpenses

        if categoryDefinitions.isEmpty {
            seedDefaultsIfNeeded()
        }

        persistExpenses()
        persistQueue()
        persistMeta()
        persistRecentlyDeletedExpenses()
    }

    func tripTotal(_ tripID: UUID?) -> Decimal {
        filteredExpenses(tripID: tripID, paymentMethodID: nil).reduce(.zero) { $0 + $1.amount }
    }

    func filteredExpenses(tripID: UUID?, paymentMethodID: UUID?) -> [ExpenseRecord] {
        expenses.filter { expense in
            let tripMatches = tripID == nil || expense.tripID == tripID
            let paymentMatches = paymentMethodID == nil || expense.paymentMethodID == paymentMethodID
            return tripMatches && paymentMatches
        }
    }

    func categoryTotals(tripID: UUID? = nil, paymentMethodID: UUID? = nil) -> [(String, Decimal)] {
        let calendar = Calendar.current
        let now = Date()
        let filtered = filteredExpenses(tripID: tripID, paymentMethodID: paymentMethodID)
            .filter { tripID != nil || calendar.isDate($0.expenseDate, equalTo: now, toGranularity: .month) }
        let totals = filtered.reduce(into: [String: Decimal]()) { partial, expense in
            partial[expense.category, default: .zero] += expense.amount
        }
        return totals.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }
    }

    var monthlySpendTotal: Decimal {
        let calendar = Calendar.current
        let now = Date()
        return expenses
            .filter { calendar.isDate($0.expenseDate, equalTo: now, toGranularity: .month) }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    var categoryTotals: [(String, Decimal)] {
        categoryTotals(tripID: nil, paymentMethodID: nil)
    }

    private func saveParsedDraft(_ draft: ExpenseDraft, queueID: UUID?, existingExpenseID: UUID?, markAsEdited: Bool) {
        let amount = Decimal(string: draft.amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let now = Date()
        let capturedAtDevice = queueID
            .flatMap { qid in queuedCaptures.first(where: { $0.id == qid })?.capturedAt }
            ?? draft.expenseDate
        let audioDurationSeconds = queueID
            .flatMap { qid in queuedCaptures.first(where: { $0.id == qid })?.audioDurationSeconds }

        if let existingExpenseID, let idx = expenses.firstIndex(where: { $0.id == existingExpenseID }) {
            expenses[idx].amount = amount
            expenses[idx].currency = Self.normalizedCurrencyCode(draft.currency) ?? defaultCurrencyCode
            expenses[idx].category = draft.category
            expenses[idx].categoryID = draft.categoryID
            expenses[idx].description = draft.description.isEmpty ? nil : draft.description
            expenses[idx].merchant = draft.merchant.isEmpty ? nil : draft.merchant
            expenses[idx].tripID = draft.tripID
            expenses[idx].tripName = draft.tripName
            expenses[idx].paymentMethodID = draft.paymentMethodID
            expenses[idx].paymentMethodName = draft.paymentMethodName
            expenses[idx].expenseDate = draft.expenseDate
            expenses[idx].parseStatus = .edited
            expenses[idx].parseConfidence = draft.parseConfidence
            expenses[idx].rawText = draft.rawText.isEmpty ? nil : draft.rawText
            expenses[idx].updatedAt = now
            persistExpenses()
            return
        }

        let resolvedExpenseID = queueID
            .flatMap { qid in queuedCaptures.first(where: { $0.id == qid })?.serverExpenseID }
            ?? UUID()

        let record = ExpenseRecord(
            id: resolvedExpenseID,
            clientExpenseID: draft.clientExpenseID,
            amount: amount,
            currency: Self.normalizedCurrencyCode(draft.currency) ?? defaultCurrencyCode,
            category: draft.category,
            categoryID: draft.categoryID,
            description: draft.description.isEmpty ? nil : draft.description,
            merchant: draft.merchant.isEmpty ? nil : draft.merchant,
            tripID: draft.tripID,
            tripName: draft.tripName,
            paymentMethodID: draft.paymentMethodID,
            paymentMethodName: draft.paymentMethodName,
            expenseDate: draft.expenseDate,
            capturedAtDevice: capturedAtDevice,
            syncedAt: now,
            source: draft.source,
            parseStatus: markAsEdited ? .edited : .auto,
            parseConfidence: draft.parseConfidence,
            rawText: draft.rawText,
            audioDurationSeconds: audioDurationSeconds,
            createdAt: now,
            updatedAt: now
        )

        if let idx = expenses.firstIndex(where: { $0.id == record.id || $0.clientExpenseID == record.clientExpenseID }) {
            expenses[idx] = record
        } else {
            expenses.insert(record, at: 0)
        }
        expenses = Self.deduplicatedExpenses(expenses)
        persistExpenses()
    }

    private func autoAssignCategoryIDIfNeeded(_ draft: inout ExpenseDraft) {
        if let match = categoryDefinitions.first(where: { $0.name.caseInsensitiveCompare(draft.category) == .orderedSame }) {
            draft.categoryID = match.id
            draft.category = match.name
            return
        }

        let lowerText = [draft.description, draft.rawText].joined(separator: " ").lowercased()
        let best = categoryDefinitions
            .filter { !$0.hintKeywords.isEmpty }
            .map { category -> (CategoryDefinition, Int) in
                let score = category.hintKeywords.reduce(into: 0) { partial, keyword in
                    if lowerText.contains(keyword.lowercased()) { partial += 1 }
                }
                return (category, score)
            }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }

        if let best {
            draft.categoryID = best.0.id
            draft.category = best.0.name
        }
    }

    private func autoAssignExpenseDateIfNeeded(_ draft: inout ExpenseDraft) {
        let sourceText = [draft.rawText, draft.description]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else { return }

        let lower = sourceText.lowercased()
        let calendar = Calendar.current
        let baseDate = draft.expenseDate

        if lower.contains("yesterday") || lower.contains("last night") {
            if let date = calendar.date(byAdding: .day, value: -1, to: baseDate) {
                draft.expenseDate = calendar.startOfDay(for: date)
            }
            return
        }
        if lower.contains("today") || lower.contains("tonight") {
            draft.expenseDate = calendar.startOfDay(for: baseDate)
            return
        }
        if lower.contains("tomorrow") {
            if let date = calendar.date(byAdding: .day, value: 1, to: baseDate) {
                draft.expenseDate = calendar.startOfDay(for: date)
            }
            return
        }

        // Recurring phrasing like "weekly Tuesday tournament" should not be treated
        // as a specific date reference for this expense.
        if Self.containsRecurringWeekdayCue(in: lower) {
            draft.expenseDate = calendar.startOfDay(for: baseDate)
            return
        }

        guard Self.containsLikelyDateCue(in: lower) else { return }
        guard let detector = Self.dateDetector else { return }
        let range = NSRange(sourceText.startIndex..<sourceText.endIndex, in: sourceText)
        let matches = detector.matches(in: sourceText, options: [], range: range)
        guard let date = matches.compactMap(\.date).first else { return }
        draft.expenseDate = calendar.startOfDay(for: date)
    }

    private func autoAssignCurrencyIfNeeded(_ draft: inout ExpenseDraft) {
        let sourceText = [draft.rawText, draft.description, draft.merchant]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detected = Self.detectCurrencyCode(in: sourceText)

        if let detected {
            draft.currency = detected
            return
        }

        if let normalized = Self.normalizedCurrencyCode(draft.currency) {
            draft.currency = normalized
        } else {
            draft.currency = defaultCurrencyCode
        }
    }

    private func autoDetectPaymentMethodIfNeeded(_ draft: inout ExpenseDraft) {
        guard draft.paymentMethodID == nil else { return }
        guard !paymentMethods.isEmpty else { return }

        let lower = [draft.rawText, draft.description, draft.merchant].joined(separator: " ").lowercased()
        let matches = paymentMethods.filter { method in
            let aliases = ([method.name] + method.aliases + [method.network ?? ""]).map { $0.lowercased() }.filter { !$0.isEmpty }
            return aliases.contains { lower.contains($0) }
        }

        guard matches.count == 1, let method = matches.first else { return }
        draft.paymentMethodID = method.id
        draft.paymentMethodName = method.name
    }

    private func persistQueue() {
        queuedCaptures = Self.deduplicatedQueue(queuedCaptures)
        queueStore.saveQueue(queuedCaptures)
    }

    private func persistExpenses() {
        expenses = Self.deduplicatedExpenses(expenses)
        expenseLedgerStore.saveExpenses(expenses)
    }

    private func persistMeta() {
        metaStore.save(LocalMetaStore.Payload(
            categories: categoryDefinitions,
            trips: trips,
            paymentMethods: paymentMethods,
            budgetRules: budgetRules,
            activeTripID: activeTripID,
            defaultCurrencyCode: defaultCurrencyCode,
            parsingLanguage: parsingLanguage.rawValue,
            dailyVoiceLimit: dailyVoiceLimit,
            hasCompletedOnboarding: !shouldShowOnboarding
        ))
    }

    private func addRecentlyDeleted(_ entry: RecentlyDeletedExpenseEntry) {
        recentlyDeletedExpenses.removeAll { $0.id == entry.id }
        recentlyDeletedExpenses.insert(entry, at: 0)
        purgeExpiredRecentlyDeletedExpenses()
        persistRecentlyDeletedExpenses()
    }

    private func purgeExpiredRecentlyDeletedExpenses() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        let expired = recentlyDeletedExpenses.filter { $0.deletedAt < cutoff }
        recentlyDeletedExpenses.removeAll { $0.deletedAt < cutoff }
        persistRecentlyDeletedExpenses()
        guard !expired.isEmpty else { return }
        Task { [apiClient] in
            for entry in expired {
                try? await apiClient.deleteExpense(entry.expense.id)
            }
        }
    }

    private func persistRecentlyDeletedExpenses() {
        recentlyDeletedStore.save(recentlyDeletedExpenses)
    }

    private func handleNetworkConnectivityChange(_ isConnected: Bool) {
        self.isConnected = isConnected
        if isConnected {
            Task {
                await refreshCloudStateFromServer()
                await syncQueueIfPossible()
            }
        }
    }

    private func scheduleMetadataSync() {
        metadataSyncDirty = true
        Task { await syncMetadataToServerIfPossible() }
    }

    private func syncMetadataToServerIfPossible() async {
        guard isConnected else { return }
        guard !isSyncingMetadata else { return }
        isSyncingMetadata = true
        defer { isSyncingMetadata = false }
        while isConnected && metadataSyncDirty {
            metadataSyncDirty = false
            let snapshot = UserMetadataSyncSnapshotDTO(
                categories: categoryDefinitions,
                trips: trips,
                paymentMethods: paymentMethods,
                activeTripID: activeTripID,
                defaultCurrencyCode: defaultCurrencyCode,
                dailyVoiceLimit: dailyVoiceLimit
            )
            do {
                try await apiClient.syncMetadata(snapshot)
            } catch {
                logOperationalError("Metadata sync failed", details: ["error": error.localizedDescription])
                // Keep pending changes marked dirty so we can retry later.
                metadataSyncDirty = true
                break
            }
        }
    }

    private func refreshMetadataFromServer() async {
        guard isConnected else { return }
        do {
            guard let snapshot = try await apiClient.fetchMetadata() else { return }
            categoryDefinitions = mergeRemoteCategories(snapshot.categories)
            trips = snapshot.trips
            paymentMethods = snapshot.paymentMethods
            if let remoteDefault = Self.normalizedCurrencyCode(snapshot.defaultCurrencyCode) {
                defaultCurrencyCode = remoteDefault
            }
            if let remoteDailyVoiceLimit = Self.normalizedDailyVoiceLimit(snapshot.dailyVoiceLimit) {
                dailyVoiceLimit = remoteDailyVoiceLimit
            }
            if let active = snapshot.activeTripID, trips.contains(where: { $0.id == active }) {
                activeTripID = active
            } else if let current = activeTripID, !trips.contains(where: { $0.id == current }) {
                activeTripID = nil
            }
            persistMeta()
            relinkLocalExpenseReferences()
        } catch {
            logOperationalError("Metadata fetch failed", details: ["error": error.localizedDescription])
        }
    }

    private func refreshExpensesFromServer() async {
        guard isConnected else { return }
        purgeExpiredRecentlyDeletedExpenses()
        do {
            let remoteExpenses = try await apiClient.fetchExpenses()
            let hiddenIDs = Set(recentlyDeletedExpenses.map(\.id))
            let visibleRemoteExpenses = remoteExpenses.filter { !hiddenIDs.contains($0.id) }
            let deduplicatedRemote = Self.deduplicatedExpenses(visibleRemoteExpenses)
            if deduplicatedRemote != expenses {
                expenses = deduplicatedRemote
                persistExpenses()
            }
        } catch {
            logOperationalError("Expenses fetch failed", details: ["error": error.localizedDescription])
        }
    }

    private func mergeRemoteCategories(_ remote: [CategoryDefinition]) -> [CategoryDefinition] {
        guard !remote.isEmpty else { return categoryDefinitions }
        var merged = remote
        let remoteNames = Set(remote.map { $0.name.lowercased() })
        for local in categoryDefinitions where !remoteNames.contains(local.name.lowercased()) && local.isDefault {
            merged.append(local)
        }
        return merged.sorted { ($0.isDefault ? 0 : 1, $0.name.lowercased()) < ($1.isDefault ? 0 : 1, $1.name.lowercased()) }
    }

    private func relinkLocalExpenseReferences() {
        var didChange = false
        for idx in expenses.indices {
            if let category = categoryDefinitions.first(where: { $0.name.caseInsensitiveCompare(expenses[idx].category) == .orderedSame }) {
                if expenses[idx].categoryID != category.id {
                    expenses[idx].categoryID = category.id
                    didChange = true
                }
            }
            if let tripName = expenses[idx].tripName,
               let trip = trips.first(where: { $0.name.caseInsensitiveCompare(tripName) == .orderedSame }),
               expenses[idx].tripID != trip.id {
                expenses[idx].tripID = trip.id
                didChange = true
            }
            if let paymentName = expenses[idx].paymentMethodName,
               let method = paymentMethods.first(where: { $0.name.caseInsensitiveCompare(paymentName) == .orderedSame }),
               expenses[idx].paymentMethodID != method.id {
                expenses[idx].paymentMethodID = method.id
                didChange = true
            }
        }
        if didChange { persistExpenses() }
    }

    private func cleanupLocalAudioFileIfNeeded(for queueItem: QueuedCapture) {
        guard let path = queueItem.localAudioFilePath else { return }
        let url = URL(fileURLWithPath: path)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            #if DEBUG
            print("[Speakance] Failed to delete local audio file: \(error)")
            #endif
        }
    }

    private func logOperationalError(_ message: String, details: [String: String] = [:]) {
        lastOperationalErrorMessage = message
        #if DEBUG
        let suffix = details.isEmpty ? "" : " " + details.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        print("[Speakance] ERROR \(message)\(suffix)")
        #endif
    }

    private func logOperationalInfo(_ message: String, details: [String: String] = [:]) {
        #if DEBUG
        let suffix = details.isEmpty ? "" : " " + details.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        print("[Speakance] INFO \(message)\(suffix)")
        #endif
    }

    private func seedDefaultsIfNeeded() {
        if categoryDefinitions.isEmpty {
            categoryDefinitions = [
                CategoryDefinition(name: "Food", colorHex: "#F97316", isDefault: true, hintKeywords: ["restaurant", "cafe", "coffee", "meal", "lunch", "dinner", "breakfast"]),
                CategoryDefinition(name: "Groceries", colorHex: "#22C55E", isDefault: true, hintKeywords: ["grocery", "groceries", "supermarket", "market", "costco", "walmart"]),
                CategoryDefinition(name: "Transport", colorHex: "#0EA5E9", isDefault: true, hintKeywords: ["uber", "lyft", "taxi", "bus", "train", "metro", "gas", "fuel", "toll", "parking"]),
                CategoryDefinition(name: "Shopping", colorHex: "#EC4899", isDefault: true, hintKeywords: ["shopping", "amazon", "clothes", "shoes", "mall", "store"]),
                CategoryDefinition(name: "Utilities", colorHex: "#EF4444", isDefault: true, hintKeywords: ["bill", "electricity", "internet", "phone", "water", "utility", "insurance"]),
                CategoryDefinition(name: "Entertainment", colorHex: "#8B5CF6", isDefault: true, hintKeywords: ["movie", "concert", "games", "nightclub", "club", "bar", "table", "bottle", "cover"]),
                CategoryDefinition(name: "Subscriptions", colorHex: "#6366F1", isDefault: true, hintKeywords: ["subscription", "monthly", "netflix", "spotify", "icloud", "membership"]),
                CategoryDefinition(name: "Other", colorHex: "#64748B", isDefault: true, hintKeywords: [])
            ]
        }
        persistMeta()
    }

    private func normalizeKeywords(_ hints: [String]) -> [String] {
        Array(Set(hints
            .flatMap { $0.split(separator: ",") }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }))
            .sorted()
    }

    private static func containsLikelyDateCue(in lowerText: String) -> Bool {
        if lowerText.contains(" on ") || lowerText.contains(" at ") { /* weak cues, continue checks */ }
        let keywords = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
                        "today", "yesterday", "tomorrow", "last "]
        if keywords.contains(where: { lowerText.contains($0) }) { return true }
        if lowerText.range(
            of: #"\b(?:on|this|last|next)\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if lowerText.range(of: #"\b\d{1,2}[/-]\d{1,2}([/-]\d{2,4})?\b"#, options: .regularExpression) != nil {
            return true
        }
        if lowerText.range(of: #"\b\d{4}-\d{1,2}-\d{1,2}\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func containsRecurringWeekdayCue(in lowerText: String) -> Bool {
        let patterns = [
            #"\b(?:every|weekly)\b[\w\s,-]{0,24}\b(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#,
            #"\b(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b[\w\s,-]{0,24}\b(?:every week|weekly)\b"#
        ]

        return patterns.contains { pattern in
            lowerText.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func normalizedCurrencyCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard supportedCurrencyCodes.contains(normalized) else { return nil }
        return normalized
    }

    private static func normalizedParsingLanguage(_ raw: String?) -> ParsingLanguage? {
        guard let raw else { return nil }
        return ParsingLanguage(rawValue: raw)
    }

    private static func normalizedDailyVoiceLimit(_ raw: Int?) -> Int? {
        guard let raw, raw > 0 else { return nil }
        return raw
    }

    private static func detectCurrencyCode(in text: String) -> String? {
        let lower = text.lowercased()
        guard !lower.isEmpty else { return nil }

        // More specific phrases first to avoid false positives.
        if lower.contains("mexican peso") || lower.contains("mexican pesos") { return "MXN" }
        if lower.range(of: #"\bmxn\b"#, options: .regularExpression) != nil { return "MXN" }
        if lower.range(of: #"\bpeso\b|\bpesos\b"#, options: .regularExpression) != nil { return "MXN" }

        if lower.range(of: #"\beur\b"#, options: .regularExpression) != nil || lower.contains("euro") || lower.contains("euros") || text.contains("€") {
            return "EUR"
        }
        if lower.range(of: #"\bgbp\b"#, options: .regularExpression) != nil || lower.contains("pound") || lower.contains("pounds") || text.contains("£") {
            return "GBP"
        }
        if lower.range(of: #"\bjpy\b"#, options: .regularExpression) != nil || lower.contains("yen") || text.contains("¥") {
            return "JPY"
        }
        if lower.range(of: #"\bbrl\b"#, options: .regularExpression) != nil || lower.contains("real") || lower.contains("reais") {
            return "BRL"
        }
        if lower.range(of: #"\bcad\b"#, options: .regularExpression) != nil || lower.contains("canadian dollar") {
            return "CAD"
        }
        if lower.range(of: #"\busd\b"#, options: .regularExpression) != nil || lower.contains("dollar") || lower.contains("dollars") || text.contains("$") {
            return "USD"
        }

        return nil
    }
}

private extension AppStore {
    static let csvDateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func escapeCSVField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    static func normalizedAmountText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }
        let candidate = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let decimal = Decimal(string: candidate) else { return trimmed }
        return NSDecimalNumber(decimal: decimal).stringValue
    }

    static func rewrittenRawAmountText(in rawText: String, amountText: String) -> String {
        let trimmedRaw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty, !trimmedAmount.isEmpty else { return rawText }
        guard trimmedRaw.caseInsensitiveCompare("Voice capture") != .orderedSame else { return rawText }

        guard let regex = try? NSRegularExpression(
            pattern: #"\d{1,3}(?:[,\.\s]\d{3})*(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?"#
        ) else { return rawText }

        let range = NSRange(trimmedRaw.startIndex..<trimmedRaw.endIndex, in: trimmedRaw)
        guard let firstMatch = regex.firstMatch(in: trimmedRaw, options: [], range: range),
              let matchRange = Range(firstMatch.range, in: trimmedRaw) else {
            return rawText
        }

        var rewritten = trimmedRaw
        rewritten.replaceSubrange(matchRange, with: trimmedAmount)
        return rewritten
    }

    static func rewrittenRawDescriptionText(in rawText: String, previousDescription: String?, newDescription: String) -> String {
        let trimmedRaw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrevious = previousDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !trimmedRaw.isEmpty, !trimmedNew.isEmpty else { return rawText }
        guard trimmedRaw.caseInsensitiveCompare("Voice capture") != .orderedSame else { return rawText }
        guard !trimmedPrevious.isEmpty else { return rawText }
        guard trimmedPrevious.caseInsensitiveCompare(trimmedNew) != .orderedSame else { return rawText }

        if let range = trimmedRaw.range(of: trimmedPrevious, options: [.caseInsensitive, .diacriticInsensitive]) {
            var rewritten = trimmedRaw
            rewritten.replaceSubrange(range, with: trimmedNew)
            return rewritten
        }

        return rawText
    }

    static let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    static func deduplicatedQueue(_ items: [QueuedCapture]) -> [QueuedCapture] {
        var seenLocalIDs = Set<UUID>()
        var seenClientIDs = Set<UUID>()
        var result: [QueuedCapture] = []
        for item in items {
            if seenLocalIDs.contains(item.id) { continue }
            if seenClientIDs.contains(item.clientExpenseID), item.status == .saved { continue }
            seenLocalIDs.insert(item.id)
            seenClientIDs.insert(item.clientExpenseID)
            result.append(item)
        }
        return result
    }

    static func normalizedQueueForStartup(_ items: [QueuedCapture]) -> [QueuedCapture] {
        items.map { item in
            var normalized = item
            if normalized.status == .syncing {
                // App may have been killed while syncing; reset to pending so user can retry.
                normalized.status = .pending
            }
            return normalized
        }
    }

    static func isAuthenticationError(_ error: Error) -> Bool {
        switch error {
        case ExpenseAPIError.missingAuthSession, ExpenseAPIError.unauthorized:
            return true
        default:
            return false
        }
    }

    static func deduplicatedExpenses(_ items: [ExpenseRecord]) -> [ExpenseRecord] {
        var byServerID: [UUID: ExpenseRecord] = [:]
        var byClientID: [UUID: ExpenseRecord] = [:]

        for item in items.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            if byServerID[item.id] == nil {
                byServerID[item.id] = item
            }
            if byClientID[item.clientExpenseID] == nil {
                byClientID[item.clientExpenseID] = item
            }
        }

        var selected = Array(byServerID.values)
        selected = selected.filter { byClientID[$0.clientExpenseID]?.id == $0.id }
        return selected.sorted { lhs, rhs in
            if lhs.expenseDate == rhs.expenseDate {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.expenseDate > rhs.expenseDate
        }
    }
}

private enum AppError: LocalizedError {
    case missingRawText

    var errorDescription: String? {
        switch self {
        case .missingRawText:
            return "Queued item is missing text for parsing."
        }
    }
}

enum ParsingLanguage: String, Codable, CaseIterable {
    case auto
    case english
    case spanish

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .english: return "English"
        case .spanish: return "Spanish"
        }
    }

    var apiHint: String? {
        switch self {
        case .auto: return nil
        case .english: return "en"
        case .spanish: return "es"
        }
    }

    var speechLocaleIdentifier: String? {
        switch self {
        case .auto: return nil
        case .english: return "en-US"
        case .spanish: return "es-MX"
        }
    }
}

struct BudgetUsageSnapshot: Identifiable, Sendable {
    let id: UUID
    let rule: BudgetRule
    let spent: Decimal

    init(rule: BudgetRule, spent: Decimal) {
        self.id = rule.id
        self.rule = rule
        self.spent = spent
    }

    var remaining: Decimal {
        max(Decimal.zero, rule.monthlyLimit - spent)
    }

    var isOverBudget: Bool {
        spent > rule.monthlyLimit
    }

    var progressRatio: Double {
        let limit = NSDecimalNumber(decimal: rule.monthlyLimit).doubleValue
        guard limit > 0 else { return 0 }
        let spentValue = NSDecimalNumber(decimal: spent).doubleValue
        return spentValue / limit
    }
}

private struct LocalBackupPayload: Codable {
    var exportedAt: Date
    var expenses: [ExpenseRecord]
    var queuedCaptures: [QueuedCapture]
    var categories: [CategoryDefinition]
    var trips: [TripRecord]
    var paymentMethods: [PaymentMethod]
    var budgetRules: [BudgetRule]
    var activeTripID: UUID?
    var defaultCurrencyCode: String?
    var parsingLanguage: String?
    var recentlyDeletedExpenses: [RecentlyDeletedExpenseEntry]
}

private final class LocalMetaStore {
    struct Payload: Codable {
        var categories: [CategoryDefinition]
        var trips: [TripRecord]
        var paymentMethods: [PaymentMethod]
        var budgetRules: [BudgetRule]
        var activeTripID: UUID?
        var defaultCurrencyCode: String?
        var parsingLanguage: String?
        var dailyVoiceLimit: Int?
        var hasCompletedOnboarding: Bool?

        enum CodingKeys: String, CodingKey {
            case categories
            case trips
            case paymentMethods
            case budgetRules
            case activeTripID
            case defaultCurrencyCode
            case parsingLanguage
            case dailyVoiceLimit
            case hasCompletedOnboarding
        }

        init(
            categories: [CategoryDefinition],
            trips: [TripRecord],
            paymentMethods: [PaymentMethod],
            budgetRules: [BudgetRule],
            activeTripID: UUID?,
            defaultCurrencyCode: String?,
            parsingLanguage: String?,
            dailyVoiceLimit: Int?,
            hasCompletedOnboarding: Bool?
        ) {
            self.categories = categories
            self.trips = trips
            self.paymentMethods = paymentMethods
            self.budgetRules = budgetRules
            self.activeTripID = activeTripID
            self.defaultCurrencyCode = defaultCurrencyCode
            self.parsingLanguage = parsingLanguage
            self.dailyVoiceLimit = dailyVoiceLimit
            self.hasCompletedOnboarding = hasCompletedOnboarding
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            categories = try container.decodeIfPresent([CategoryDefinition].self, forKey: .categories) ?? []
            trips = try container.decodeIfPresent([TripRecord].self, forKey: .trips) ?? []
            paymentMethods = try container.decodeIfPresent([PaymentMethod].self, forKey: .paymentMethods) ?? []
            budgetRules = try container.decodeIfPresent([BudgetRule].self, forKey: .budgetRules) ?? []
            activeTripID = try container.decodeIfPresent(UUID.self, forKey: .activeTripID)
            defaultCurrencyCode = try container.decodeIfPresent(String.self, forKey: .defaultCurrencyCode)
            parsingLanguage = try container.decodeIfPresent(String.self, forKey: .parsingLanguage)
            dailyVoiceLimit = try container.decodeIfPresent(Int.self, forKey: .dailyVoiceLimit)
            hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
        }
    }

    private let key = "speakance.local-meta.v1"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() -> Payload {
        guard let data = UserDefaults.standard.data(forKey: key),
              let payload = try? decoder.decode(Payload.self, from: data) else {
            return Payload(
                categories: [],
                trips: [],
                paymentMethods: [],
                budgetRules: [],
                activeTripID: nil,
                defaultCurrencyCode: nil,
                parsingLanguage: nil,
                dailyVoiceLimit: nil,
                hasCompletedOnboarding: nil
            )
        }
        return payload
    }

    func save(_ payload: Payload) {
        guard let data = try? encoder.encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private final class LocalRecentlyDeletedStore {
    private let key = "speakance.recently-deleted-expenses.v1"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() -> [RecentlyDeletedExpenseEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let payload = try? decoder.decode([RecentlyDeletedExpenseEntry].self, from: data) else {
            return []
        }
        return payload
    }

    func save(_ payload: [RecentlyDeletedExpenseEntry]) {
        guard let data = try? encoder.encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
