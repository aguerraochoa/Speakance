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

    @Published var categoryDefinitions: [CategoryDefinition] = []
    @Published var trips: [TripRecord] = []
    @Published var paymentMethods: [PaymentMethod] = []
    @Published var activeTripID: UUID?
    @Published var defaultCurrencyCode: String = "USD"

    let networkMonitor: NetworkMonitor
    let audioCaptureService: AudioCaptureService

    private let queueStore: QueueStoreProtocol
    private let expenseLedgerStore: ExpenseLedgerStoreProtocol
    private let apiClient: ExpenseAPIClientProtocol
    private let syncEngine = SyncEngine()
    private let metaStore = LocalMetaStore()
    private var isSyncingMetadata = false

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
        self.activeTripID = persistedMeta.activeTripID
        self.defaultCurrencyCode = Self.normalizedCurrencyCode(persistedMeta.defaultCurrencyCode) ?? "USD"

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

        isSyncingQueue = true
        defer {
            isSyncingQueue = false
            persistQueue()
        }

        let queueIDs = queuedCaptures.map(\.id)
        for queueID in queueIDs {
            guard let index = queuedCaptures.firstIndex(where: { $0.id == queueID }) else { continue }
            if queuedCaptures[index].status != .pending { continue }

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
                    logOperationalError("Unexpected parser state during sync", details: [
                        "queueID": queuedCaptures[index].id.uuidString
                    ])
                }
            } catch {
                if Self.isAuthenticationError(error) {
                    // Keep items pending when auth is missing/expired so they can recover after sign-in.
                    queuedCaptures[index].status = .pending
                    queuedCaptures[index].lastError = error.localizedDescription
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
        saveParsedDraft(context.draft, queueID: context.queueID, existingExpenseID: context.expenseID, markAsEdited: true)
        if let expenseID = context.expenseID {
            Task { [apiClient] in
                do {
                    try await apiClient.updateExpense(UpdateExpenseRequestDTO(expenseID: expenseID, draft: context.draft))
                } catch {
                    #if DEBUG
                    print("[Speakance] remote expense update failed id=\(expenseID.uuidString): \(error.localizedDescription)")
                    #endif
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

    func deleteExpense(_ expense: ExpenseRecord) {
        let removed = expense
        let originalIndex = expenses.firstIndex(where: { $0.id == expense.id })
        let removedQueueEntries = queuedCaptures
            .enumerated()
            .filter { _, item in
                item.clientExpenseID == expense.clientExpenseID || item.serverExpenseID == expense.id
            }

        expenses.removeAll { $0.id == expense.id }
        persistExpenses()
        if !removedQueueEntries.isEmpty {
            let removedQueueIDs = Set(removedQueueEntries.map { $0.element.id })
            queuedCaptures.removeAll { removedQueueIDs.contains($0.id) }
            persistQueue()
        }

        Task { [apiClient] in
            do {
                try await apiClient.deleteExpense(expense.id)
                await MainActor.run {
                    for entry in removedQueueEntries {
                        cleanupLocalAudioFileIfNeeded(for: entry.element)
                    }
                }
            } catch {
                #if DEBUG
                print("[Speakance] remote expense delete failed id=\(expense.id.uuidString): \(error.localizedDescription)")
                #endif
                await MainActor.run {
                    if let originalIndex, !expenses.contains(where: { $0.id == removed.id }) {
                        let insertIndex = min(max(0, originalIndex), expenses.count)
                        expenses.insert(removed, at: insertIndex)
                    } else if !expenses.contains(where: { $0.id == removed.id }) {
                        expenses.insert(removed, at: 0)
                    }
                    persistExpenses()
                    if !removedQueueEntries.isEmpty {
                        for entry in removedQueueEntries.sorted(by: { $0.offset < $1.offset }) {
                            guard !queuedCaptures.contains(where: { $0.id == entry.element.id }) else { continue }
                            let insertIndex = min(max(0, entry.offset), queuedCaptures.count)
                            queuedCaptures.insert(entry.element, at: insertIndex)
                        }
                        persistQueue()
                    }
                    lastOperationalErrorMessage = "Could not delete expense on server. Restored locally."
                }
            }
        }
    }

    func setNetworkConnectivity(_ isConnected: Bool) {
        networkMonitor.setDebugConnectivity(isConnected)
    }

    func setDefaultCurrencyCode(_ code: String) {
        guard let normalized = Self.normalizedCurrencyCode(code) else { return }
        guard defaultCurrencyCode != normalized else { return }
        defaultCurrencyCode = normalized
        persistMeta()
        scheduleMetadataSync()
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

        guard Self.containsLikelyDateCue(in: lower) else { return }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return }
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
            activeTripID: activeTripID,
            defaultCurrencyCode: defaultCurrencyCode
        ))
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
        Task { await syncMetadataToServerIfPossible() }
    }

    private func syncMetadataToServerIfPossible() async {
        guard isConnected else { return }
        guard !isSyncingMetadata else { return }
        isSyncingMetadata = true
        defer { isSyncingMetadata = false }
        let snapshot = UserMetadataSyncSnapshotDTO(
            categories: categoryDefinitions,
            trips: trips,
            paymentMethods: paymentMethods,
            activeTripID: activeTripID,
            defaultCurrencyCode: defaultCurrencyCode
        )
        do {
            try await apiClient.syncMetadata(snapshot)
        } catch {
            logOperationalError("Metadata sync failed", details: ["error": error.localizedDescription])
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
        do {
            let remoteExpenses = try await apiClient.fetchExpenses()
            if !remoteExpenses.isEmpty || expenses.isEmpty {
                expenses = Self.deduplicatedExpenses(remoteExpenses)
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
                        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                        "today", "yesterday", "tomorrow", "last "]
        if keywords.contains(where: { lowerText.contains($0) }) { return true }
        if lowerText.range(of: #"\b\d{1,2}[/-]\d{1,2}([/-]\d{2,4})?\b"#, options: .regularExpression) != nil {
            return true
        }
        if lowerText.range(of: #"\b\d{4}-\d{1,2}-\d{1,2}\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func normalizedCurrencyCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard supportedCurrencyCodes.contains(normalized) else { return nil }
        return normalized
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

private final class LocalMetaStore {
    struct Payload: Codable {
        var categories: [CategoryDefinition]
        var trips: [TripRecord]
        var paymentMethods: [PaymentMethod]
        var activeTripID: UUID?
        var defaultCurrencyCode: String?
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
            return Payload(categories: [], trips: [], paymentMethods: [], activeTripID: nil, defaultCurrencyCode: nil)
        }
        return payload
    }

    func save(_ payload: Payload) {
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
