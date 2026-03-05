import XCTest
@testable import Speakance

@MainActor
final class SpeakanceCriticalFlowsTests: XCTestCase {
    private let testProjectURL = URL(string: "https://example.supabase.co")!

    func testBootstrapFallsBackWhenConfigMissing() {
        let bundle = AppBootstrap.makeBundle(config: nil)

        XCTAssertFalse(bundle.authStore.isConfigured)
        XCTAssertEqual(bundle.authStore.state, .disabled)
    }

    func testSaveReviewParsesUSFormattedAmount() {
        let store = AppStore(
            queueStore: InMemoryQueueStore(),
            expenseLedgerStore: InMemoryExpenseLedgerStore(),
            apiClient: MockExpenseAPIClient(),
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )
        let expense = makeExpense(amount: Decimal(string: "12.34")!)
        store.expenses = [expense]

        store.openReview(for: expense)
        guard var context = store.activeReview else {
            XCTFail("Expected active review context")
            return
        }
        context.draft.amountText = "1,000.50"

        store.saveReview(context)

        XCTAssertNil(store.activeReview)
        XCTAssertEqual(store.expenses.first?.amount, Decimal(string: "1000.5")!)
    }

    func testSaveReviewParsesEUFormattedAmount() {
        let store = AppStore(
            queueStore: InMemoryQueueStore(),
            expenseLedgerStore: InMemoryExpenseLedgerStore(),
            apiClient: MockExpenseAPIClient(),
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )
        let expense = makeExpense(amount: Decimal(string: "15")!)
        store.expenses = [expense]

        store.openReview(for: expense)
        guard var context = store.activeReview else {
            XCTFail("Expected active review context")
            return
        }
        context.draft.amountText = "1.000,50"

        store.saveReview(context)

        XCTAssertNil(store.activeReview)
        XCTAssertEqual(store.expenses.first?.amount, Decimal(string: "1000.5")!)
    }

    func testSaveReviewParsesCurrencySymbolsAndGrouping() {
        let store = AppStore(
            queueStore: InMemoryQueueStore(),
            expenseLedgerStore: InMemoryExpenseLedgerStore(),
            apiClient: MockExpenseAPIClient(),
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )
        let expense = makeExpense(amount: Decimal(string: "15")!)
        store.expenses = [expense]

        store.openReview(for: expense)
        guard var context = store.activeReview else {
            XCTFail("Expected active review context")
            return
        }
        context.draft.amountText = "$1,000.50"

        store.saveReview(context)

        XCTAssertNil(store.activeReview)
        XCTAssertEqual(store.expenses.first?.amount, Decimal(string: "1000.5")!)
    }

    func testSaveReviewParsesApostropheGrouping() {
        let store = AppStore(
            queueStore: InMemoryQueueStore(),
            expenseLedgerStore: InMemoryExpenseLedgerStore(),
            apiClient: MockExpenseAPIClient(),
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )
        let expense = makeExpense(amount: Decimal(string: "15")!)
        store.expenses = [expense]

        store.openReview(for: expense)
        guard var context = store.activeReview else {
            XCTFail("Expected active review context")
            return
        }
        context.draft.amountText = "1'000.50"

        store.saveReview(context)

        XCTAssertNil(store.activeReview)
        XCTAssertEqual(store.expenses.first?.amount, Decimal(string: "1000.5")!)
    }

    func testSaveReviewInvalidAmountKeepsReviewOpenAndDoesNotMutateExpense() {
        let store = AppStore(
            queueStore: InMemoryQueueStore(),
            expenseLedgerStore: InMemoryExpenseLedgerStore(),
            apiClient: MockExpenseAPIClient(),
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )
        let originalAmount = Decimal(string: "24.5")!
        let expense = makeExpense(amount: originalAmount)
        store.expenses = [expense]

        store.openReview(for: expense)
        guard var context = store.activeReview else {
            XCTFail("Expected active review context")
            return
        }
        context.draft.amountText = "invalid"

        store.saveReview(context)

        XCTAssertNotNil(store.activeReview)
        XCTAssertEqual(store.expenses.first?.amount, originalAmount)
        XCTAssertEqual(store.lastOperationalErrorMessage, "Enter a valid amount greater than zero.")
    }

    func testPersistenceWriteErrorSurfacesOperationalMessage() async {
        let queueStore = FailingQueueStore()
        let expenseStore = InMemoryExpenseLedgerStore()
        let store = AppStore(
            queueStore: queueStore,
            expenseLedgerStore: expenseStore,
            apiClient: MockExpenseAPIClient(),
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )

        store.createTextEntry(rawText: "coffee 5")
        await Task.yield()

        XCTAssertEqual(store.lastOperationalErrorMessage, "Could not save offline queue data.")
    }

    func testQueueAuthFailureUsesCooldownAndAvoidsImmediateRetryLoop() async {
        let apiClient = AlwaysUnauthorizedAPIClient()
        let store = AppStore(
            queueStore: InMemoryQueueStore(),
            expenseLedgerStore: InMemoryExpenseLedgerStore(),
            apiClient: apiClient,
            cloudMutationPermissionProvider: { .allowed },
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )

        store.queuedCaptures = [
            QueuedCapture(
                clientExpenseID: UUID(),
                source: .text,
                capturedAt: .now,
                rawText: "tacos 100"
            )
        ]

        await store.syncQueueIfPossible()
        await store.syncQueueIfPossible()

        XCTAssertEqual(apiClient.parseCalls, 1, "Second immediate sync attempt should be throttled by auth cooldown.")
        XCTAssertEqual(store.queuedCaptures.first?.status, .pending)
        XCTAssertEqual(store.queuedCaptures.first?.lastError, "Invalid JWT")
    }

    func testSyncQueuePreservesBackendTripAndPaymentMetadata() async {
        let expectedTripID = UUID()
        let expectedPaymentMethodID = UUID()
        let apiClient = ParseExpensePreservesMetadataMock(
            tripID: expectedTripID,
            tripName: "Weekend Trip",
            paymentMethodID: expectedPaymentMethodID,
            paymentMethodName: "Main Card"
        )

        let store = AppStore(
            queueStore: InMemoryQueueStore(),
            expenseLedgerStore: InMemoryExpenseLedgerStore(),
            apiClient: apiClient,
            cloudMutationPermissionProvider: { .allowed },
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )

        store.queuedCaptures = [
            QueuedCapture(
                clientExpenseID: UUID(),
                source: .text,
                capturedAt: .now,
                rawText: "lunch 10",
                tripID: nil,
                tripName: nil,
                paymentMethodID: nil,
                paymentMethodName: nil
            )
        ]
        store.expenses.removeAll()

        await store.syncQueueIfPossible()

        let savedExpense = store.expenses.first
        XCTAssertNotNil(savedExpense)
        XCTAssertEqual(savedExpense?.tripID, expectedTripID)
        XCTAssertEqual(savedExpense?.tripName, "Weekend Trip")
        XCTAssertEqual(savedExpense?.paymentMethodID, expectedPaymentMethodID)
        XCTAssertEqual(savedExpense?.paymentMethodName, "Main Card")
        XCTAssertEqual(store.queuedCaptures.first?.status, .saved)
    }

    func testParseExpenseRetriesOnceAfterUnauthorizedWithRecoveredToken() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }

        let config = SupabaseAppConfig(url: testProjectURL, anonKey: "anon")

        let expectedExpenseID = UUID()
        let expectedClientExpenseID = UUID()
        var requestCount = 0
        StubURLProtocol.requestHandler = { request in
            let authHeader = request.value(forHTTPHeaderField: "Authorization") ?? ""
            requestCount += 1
            if authHeader == "Bearer bad-token" {
                let data = Data(#"{"status":"error","error":"Invalid JWT"}"#.utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }
            if authHeader == "Bearer good-token" {
                let body = """
                {
                  "status": "saved",
                  "expense": {
                    "id": "\(expectedExpenseID.uuidString)",
                    "client_expense_id": "\(expectedClientExpenseID.uuidString)",
                    "amount": 100,
                    "currency": "MXN",
                    "category": "Food",
                    "expense_date": "2026-03-02"
                  }
                }
                """
                let data = Data(body.utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }

            XCTFail("Unexpected auth header: \(authHeader)")
            let data = Data(#"{"status":"error","error":"Unexpected"}"#.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)

        let authState = ParseExpenseAuthState(activeToken: "bad-token")
        let client = SupabaseFunctionExpenseAPIClient(
            config: config,
            accessTokenProvider: { await authState.currentToken() },
            unauthorizedRecoveryProvider: {
                await authState.recover(with: "good-token")
            },
            authenticationFailureHandler: { _ in
                await authState.registerFailure()
            },
            session: session
        )

        let response = try await client.parseExpense(ParseExpenseRequestDTO(
            clientExpenseID: expectedClientExpenseID,
            source: .text,
            capturedAtDevice: .now,
            audioDurationSeconds: nil,
            localAudioFilePath: nil,
            rawText: "100 tacos",
            currencyHint: "MXN",
            languageHint: "es",
            timezone: "America/Monterrey",
            tripID: nil,
            tripName: nil,
            paymentMethodID: nil,
            paymentMethodName: nil
        ))
        let recoveryCalls = await authState.recoveryCallCount()
        let failureHandlerCalls = await authState.failureHandlerCallCount()

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(recoveryCalls, 1)
        XCTAssertEqual(failureHandlerCalls, 0)
        XCTAssertEqual(response.status, .saved)
        XCTAssertEqual(response.serverExpenseID, expectedExpenseID)
    }

    func testParseExpenseRetriesOnceAfterUnauthorizedWithNonJSONBody() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }

        let config = SupabaseAppConfig(url: testProjectURL, anonKey: "anon")

        let expectedExpenseID = UUID()
        let expectedClientExpenseID = UUID()
        var requestCount = 0
        StubURLProtocol.requestHandler = { request in
            let authHeader = request.value(forHTTPHeaderField: "Authorization") ?? ""
            requestCount += 1
            if authHeader == "Bearer bad-token" {
                let data = Data("Unauthorized".utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: [
                    "Content-Type": "text/plain"
                ])!
                return (response, data)
            }
            if authHeader == "Bearer good-token" {
                let body = """
                {
                  "status": "saved",
                  "expense": {
                    "id": "\(expectedExpenseID.uuidString)",
                    "client_expense_id": "\(expectedClientExpenseID.uuidString)",
                    "amount": 250,
                    "currency": "USD",
                    "category": "Food",
                    "expense_date": "2026-03-02"
                  }
                }
                """
                let data = Data(body.utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }

            XCTFail("Unexpected auth header: \(authHeader)")
            let data = Data(#"{"status":"error","error":"Unexpected"}"#.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)

        let authState = ParseExpenseAuthState(activeToken: "bad-token")
        let client = SupabaseFunctionExpenseAPIClient(
            config: config,
            accessTokenProvider: { await authState.currentToken() },
            unauthorizedRecoveryProvider: {
                await authState.recover(with: "good-token")
            },
            authenticationFailureHandler: { _ in
                await authState.registerFailure()
            },
            session: session
        )

        let response = try await client.parseExpense(ParseExpenseRequestDTO(
            clientExpenseID: expectedClientExpenseID,
            source: .text,
            capturedAtDevice: .now,
            audioDurationSeconds: nil,
            localAudioFilePath: nil,
            rawText: "250 tacos",
            currencyHint: "USD",
            languageHint: "en",
            timezone: "America/Monterrey",
            tripID: nil,
            tripName: nil,
            paymentMethodID: nil,
            paymentMethodName: nil
        ))
        let recoveryCalls = await authState.recoveryCallCount()
        let failureHandlerCalls = await authState.failureHandlerCallCount()

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(recoveryCalls, 1)
        XCTAssertEqual(failureHandlerCalls, 0)
        XCTAssertEqual(response.status, .saved)
        XCTAssertEqual(response.serverExpenseID, expectedExpenseID)
    }

    func testFetchExpensesThrowsMissingAuthSessionWhenTokenUnavailable() async {
        let client = SupabaseFunctionExpenseAPIClient(
            config: SupabaseAppConfig(url: URL(string: "https://example.supabase.co")!, anonKey: "anon"),
            accessTokenProvider: { nil }
        )

        do {
            _ = try await client.fetchExpenses()
            XCTFail("Expected missing auth session error")
        } catch ExpenseAPIError.missingAuthSession {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRefreshCloudStatePreservesLocalEditsWhenRemoteUpdateFails() async {
        let queueStore = InMemoryQueueStore()
        let expenseStore = InMemoryExpenseLedgerStore()
        let apiClient = FailingExpenseUpdateAPIClient()
        let scopeKey = "tests-\(UUID().uuidString.lowercased())"
        let store = AppStore(
            queueStore: queueStore,
            expenseLedgerStore: expenseStore,
            apiClient: apiClient,
            cloudMutationPermissionProvider: { .allowed },
            persistenceScopeProvider: { scopeKey },
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )

        let expenseID = UUID()
        let clientExpenseID = UUID()
        let baseDate = Date()
        let original = ExpenseRecord(
            id: expenseID,
            clientExpenseID: clientExpenseID,
            amount: Decimal(string: "10")!,
            currency: "USD",
            category: "Food",
            categoryID: nil,
            description: "Lunch",
            merchant: "Cafe",
            tripID: nil,
            tripName: nil,
            paymentMethodID: nil,
            paymentMethodName: nil,
            expenseDate: baseDate,
            capturedAtDevice: baseDate,
            syncedAt: baseDate,
            source: .text,
            parseStatus: .auto,
            parseConfidence: 0.95,
            rawText: "lunch 10",
            audioDurationSeconds: nil,
            createdAt: baseDate,
            updatedAt: baseDate
        )

        let staleRemote = ExpenseRecord(
            id: expenseID,
            clientExpenseID: clientExpenseID,
            amount: Decimal(string: "10")!,
            currency: "USD",
            category: "Food",
            categoryID: nil,
            description: "Lunch",
            merchant: "Cafe",
            tripID: nil,
            tripName: nil,
            paymentMethodID: nil,
            paymentMethodName: nil,
            expenseDate: baseDate,
            capturedAtDevice: baseDate,
            syncedAt: baseDate,
            source: .text,
            parseStatus: .auto,
            parseConfidence: 0.95,
            rawText: "lunch 10",
            audioDurationSeconds: nil,
            createdAt: baseDate,
            updatedAt: baseDate
        )

        apiClient.remoteExpenses = [staleRemote]
        store.expenses = [original]

        store.openReview(for: original)
        guard var context = store.activeReview else {
            XCTFail("Expected active review context")
            return
        }
        context.draft.amountText = "20.00"
        store.saveReview(context)
        await Task.yield()

        XCTAssertEqual(store.expenses.first?.amount, Decimal(string: "20")!)

        let reloadedStore = AppStore(
            queueStore: queueStore,
            expenseLedgerStore: expenseStore,
            apiClient: apiClient,
            cloudMutationPermissionProvider: { .allowed },
            persistenceScopeProvider: { scopeKey },
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )

        XCTAssertEqual(reloadedStore.expenses.first?.amount, Decimal(string: "20")!)

        await reloadedStore.refreshCloudStateFromServer()

        XCTAssertEqual(reloadedStore.expenses.first?.amount, Decimal(string: "20")!, "Remote refresh should not overwrite pending local edit.")
        XCTAssertGreaterThanOrEqual(apiClient.updateCalls, 1, "Pending update should retry after refresh.")
    }

    func testSwitchingPersistenceScopeLoadsAccountSpecificLocalData() async {
        let queueStore = ScopedInMemoryQueueStore()
        let expenseStore = ScopedInMemoryExpenseLedgerStore()
        let firstScope = "user-a"
        let secondScope = "user-b"

        let firstClientExpenseID = UUID()
        let secondClientExpenseID = UUID()
        queueStore.byScope[firstScope] = [
            QueuedCapture(
                clientExpenseID: firstClientExpenseID,
                source: .text,
                capturedAt: .now,
                rawText: "first scope"
            ),
        ]
        queueStore.byScope[secondScope] = [
            QueuedCapture(
                clientExpenseID: secondClientExpenseID,
                source: .text,
                capturedAt: .now,
                rawText: "second scope"
            ),
        ]

        expenseStore.byScope[firstScope] = [makeExpense(amount: Decimal(string: "10")!)]
        expenseStore.byScope[secondScope] = [makeExpense(amount: Decimal(string: "20")!)]

        var activeScope: String? = firstScope
        let store = AppStore(
            queueStore: queueStore,
            expenseLedgerStore: expenseStore,
            apiClient: MockExpenseAPIClient(),
            cloudMutationPermissionProvider: { .allowed },
            persistenceScopeProvider: { activeScope },
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )

        XCTAssertEqual(store.queuedCaptures.first?.clientExpenseID, firstClientExpenseID)
        XCTAssertEqual(store.expenses.first?.amount, Decimal(string: "10")!)

        activeScope = secondScope
        await store.synchronizePersistenceScopeWithAuthIfNeeded()

        XCTAssertEqual(store.queuedCaptures.first?.clientExpenseID, secondClientExpenseID)
        XCTAssertEqual(store.expenses.first?.amount, Decimal(string: "20")!)
    }

    func testPersistQueuePrunesSavedEntries() {
        let store = AppStore(
            queueStore: InMemoryQueueStore(),
            expenseLedgerStore: InMemoryExpenseLedgerStore(),
            apiClient: MockExpenseAPIClient(),
            cloudMutationPermissionProvider: { .authRequired },
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )
        let baseline = Date()
        store.queuedCaptures = (0..<250).map { offset in
            QueuedCapture(
                clientExpenseID: UUID(),
                source: .text,
                capturedAt: baseline.addingTimeInterval(TimeInterval(-offset)),
                rawText: "saved-\(offset)",
                status: .saved
            )
        }

        store.createTextEntry(rawText: "fresh item")

        let savedCount = store.queuedCaptures.filter { $0.status == .saved }.count
        let pendingCount = store.queuedCaptures.filter { $0.status == .pending }.count

        XCTAssertEqual(savedCount, 200)
        XCTAssertEqual(pendingCount, 1)
        XCTAssertEqual(store.queuedCaptures.count, 201)
    }

    func testAddPaymentMethodRejectsDuplicateNamesCaseInsensitive() {
        let store = AppStore(
            queueStore: InMemoryQueueStore(),
            expenseLedgerStore: InMemoryExpenseLedgerStore(),
            apiClient: MockExpenseAPIClient(),
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )

        store.addPaymentMethod(name: "AMEX Gold")
        store.addPaymentMethod(name: "  amex gold  ")

        XCTAssertEqual(store.paymentMethods.count, 1)
        XCTAssertEqual(store.lastOperationalErrorMessage, "A payment method with that name already exists.")
    }

    func testUpdatePaymentMethodRejectsDuplicateNamesCaseInsensitive() {
        let store = AppStore(
            queueStore: InMemoryQueueStore(),
            expenseLedgerStore: InMemoryExpenseLedgerStore(),
            apiClient: MockExpenseAPIClient(),
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )

        store.addPaymentMethod(name: "AMEX Gold")
        store.addPaymentMethod(name: "Visa Infinite")
        XCTAssertEqual(store.paymentMethods.count, 2)

        guard let method = store.paymentMethods.first(where: { $0.name == "Visa Infinite" }) else {
            XCTFail("Expected Visa method")
            return
        }
        var updated = method
        updated.name = " amex gold "
        store.updatePaymentMethod(updated)

        XCTAssertEqual(store.paymentMethods.count, 2)
        XCTAssertEqual(store.paymentMethods.first(where: { $0.id == method.id })?.name, "Visa Infinite")
        XCTAssertEqual(store.lastOperationalErrorMessage, "A payment method with that name already exists.")
    }

    func testMonthlySpendTotalAndCategoryTotalsUseCurrentMonth() {
        let store = AppStore(
            queueStore: InMemoryQueueStore(),
            expenseLedgerStore: InMemoryExpenseLedgerStore(),
            apiClient: MockExpenseAPIClient(),
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )

        let calendar = Calendar.current
        let now = Date()
        let startOfCurrentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: startOfCurrentMonth) ?? now

        store.expenses = [
            makeExpense(amount: Decimal(string: "10")!, category: "Food", expenseDate: now),
            makeExpense(amount: Decimal(string: "5")!, category: "Transport", expenseDate: now),
            makeExpense(amount: Decimal(string: "99")!, category: "Food", expenseDate: previousMonth),
        ]

        XCTAssertEqual(store.monthlySpendTotal, Decimal(string: "15")!)
        XCTAssertEqual(store.categoryTotals.count, 2)
        XCTAssertEqual(store.categoryTotals.first?.0, "Food")
        XCTAssertEqual(store.categoryTotals.first?.1, Decimal(string: "10")!)
        XCTAssertEqual(store.categoryTotals.last?.0, "Transport")
        XCTAssertEqual(store.categoryTotals.last?.1, Decimal(string: "5")!)
    }

    func testMetadataSyncFailureSurfacesOperationalMessage() async {
        let apiClient = MetadataSyncFailingAPIClient()
        let store = AppStore(
            queueStore: InMemoryQueueStore(),
            expenseLedgerStore: InMemoryExpenseLedgerStore(),
            apiClient: apiClient,
            cloudMutationPermissionProvider: { .allowed },
            persistenceScopeProvider: { "metadata-sync-test" },
            networkMonitor: NetworkMonitor(),
            audioCaptureService: AudioCaptureService()
        )

        await store.performInitialCloudSyncIfNeeded()
        store.setDefaultCurrencyCode("EUR")
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertGreaterThanOrEqual(apiClient.syncMetadataCalls, 1)
        XCTAssertEqual(store.lastOperationalErrorMessage, "Metadata sync failed")
    }

    private func makeExpense(
        id: UUID = UUID(),
        clientExpenseID: UUID = UUID(),
        amount: Decimal,
        category: String = "Food",
        expenseDate: Date = .now
    ) -> ExpenseRecord {
        ExpenseRecord(
            id: id,
            clientExpenseID: clientExpenseID,
            amount: amount,
            currency: "USD",
            category: category,
            categoryID: nil,
            description: "Test expense",
            merchant: "Cafe",
            tripID: nil,
            tripName: nil,
            paymentMethodID: nil,
            paymentMethodName: nil,
            expenseDate: expenseDate,
            capturedAtDevice: .now,
            syncedAt: .now,
            source: .text,
            parseStatus: .auto,
            parseConfidence: nil,
            rawText: "coffee",
            audioDurationSeconds: nil,
            createdAt: .now,
            updatedAt: .now
        )
    }
}

private final class FailingQueueStore: QueueStoreProtocol {
    var onPersistenceError: ((String) -> Void)?

    func loadQueue(scopeKey _: String?) -> [QueuedCapture] { [] }

    func saveQueue(_ queue: [QueuedCapture], scopeKey _: String?) {
        onPersistenceError?("Could not save offline queue data.")
    }
}

private final class ScopedInMemoryQueueStore: QueueStoreProtocol {
    var onPersistenceError: ((String) -> Void)?
    var byScope: [String: [QueuedCapture]] = [:]

    func loadQueue(scopeKey: String?) -> [QueuedCapture] {
        byScope[scope(scopeKey)] ?? []
    }

    func saveQueue(_ queue: [QueuedCapture], scopeKey: String?) {
        byScope[scope(scopeKey)] = queue
    }

    private func scope(_ scopeKey: String?) -> String {
        let trimmed = scopeKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "local" : trimmed
    }
}

private final class ScopedInMemoryExpenseLedgerStore: ExpenseLedgerStoreProtocol {
    var onPersistenceError: ((String) -> Void)?
    var byScope: [String: [ExpenseRecord]] = [:]

    func loadExpenses(scopeKey: String?) -> [ExpenseRecord] {
        byScope[scope(scopeKey)] ?? []
    }

    func saveExpenses(_ expenses: [ExpenseRecord], scopeKey: String?) {
        byScope[scope(scopeKey)] = expenses
    }

    private func scope(_ scopeKey: String?) -> String {
        let trimmed = scopeKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "local" : trimmed
    }
}

private final class AlwaysUnauthorizedAPIClient: ExpenseAPIClientProtocol {
    private(set) var parseCalls = 0

    func parseExpense(_ request: ParseExpenseRequestDTO) async throws -> ParseExpenseResponseDTO {
        parseCalls += 1
        throw ExpenseAPIError.unauthorized("Invalid JWT")
    }

    func updateExpense(_ request: UpdateExpenseRequestDTO) async throws {}
    func deleteExpense(_ expenseID: UUID) async throws {}
    func syncMetadata(_ snapshot: UserMetadataSyncSnapshotDTO) async throws {}
    func fetchMetadata() async throws -> UserMetadataSyncSnapshotDTO? { nil }
    func fetchExpenses() async throws -> [ExpenseRecord] { [] }
}

private final class FailingExpenseUpdateAPIClient: ExpenseAPIClientProtocol {
    var remoteExpenses: [ExpenseRecord] = []
    private(set) var updateCalls = 0

    func parseExpense(_ request: ParseExpenseRequestDTO) async throws -> ParseExpenseResponseDTO {
        throw ExpenseAPIError.server("Not implemented")
    }

    func updateExpense(_ request: UpdateExpenseRequestDTO) async throws {
        updateCalls += 1
        throw ExpenseAPIError.server("Simulated update failure")
    }

    func deleteExpense(_ expenseID: UUID) async throws {}
    func syncMetadata(_ snapshot: UserMetadataSyncSnapshotDTO) async throws {}
    func fetchMetadata() async throws -> UserMetadataSyncSnapshotDTO? { nil }
    func fetchExpenses() async throws -> [ExpenseRecord] { remoteExpenses }
}

private final class ParseExpensePreservesMetadataMock: ExpenseAPIClientProtocol {
    let tripID: UUID
    let tripName: String
    let paymentMethodID: UUID
    let paymentMethodName: String

    init(tripID: UUID, tripName: String, paymentMethodID: UUID, paymentMethodName: String) {
        self.tripID = tripID
        self.tripName = tripName
        self.paymentMethodID = paymentMethodID
        self.paymentMethodName = paymentMethodName
    }

    func parseExpense(_ request: ParseExpenseRequestDTO) async throws -> ParseExpenseResponseDTO {
        let draft = ExpenseDraft(
            clientExpenseID: request.clientExpenseID,
            amountText: "10",
            currency: request.currencyHint ?? "USD",
            category: "Food",
            description: "Lunch",
            merchant: "Cafe",
            tripID: tripID,
            tripName: tripName,
            paymentMethodID: paymentMethodID,
            paymentMethodName: paymentMethodName,
            expenseDate: request.capturedAtDevice,
            rawText: request.rawText,
            source: request.source,
            parseConfidence: 0.96
        )
        return ParseExpenseResponseDTO(
            status: .saved,
            draft: draft,
            serverExpenseID: UUID()
        )
    }

    func updateExpense(_ request: UpdateExpenseRequestDTO) async throws {}
    func deleteExpense(_ expenseID: UUID) async throws {}
    func syncMetadata(_ snapshot: UserMetadataSyncSnapshotDTO) async throws {}
    func fetchMetadata() async throws -> UserMetadataSyncSnapshotDTO? { nil }
    func fetchExpenses() async throws -> [ExpenseRecord] { [] }
}

private final class MetadataSyncFailingAPIClient: ExpenseAPIClientProtocol {
    private(set) var syncMetadataCalls = 0

    func parseExpense(_ request: ParseExpenseRequestDTO) async throws -> ParseExpenseResponseDTO {
        throw ExpenseAPIError.server("Not implemented")
    }

    func updateExpense(_ request: UpdateExpenseRequestDTO) async throws {}
    func deleteExpense(_ expenseID: UUID) async throws {}

    func syncMetadata(_ snapshot: UserMetadataSyncSnapshotDTO) async throws {
        syncMetadataCalls += 1
        throw ExpenseAPIError.server("Simulated metadata failure")
    }

    func fetchMetadata() async throws -> UserMetadataSyncSnapshotDTO? {
        UserMetadataSyncSnapshotDTO(
            categories: [],
            trips: [],
            paymentMethods: [],
            deletedCategoryIDs: [],
            deletedTripIDs: [],
            deletedPaymentMethodIDs: [],
            activeTripID: nil,
            defaultCurrencyCode: "USD",
            parsingLanguage: "auto",
            dailyVoiceLimit: 50,
            profileUpdatedAt: .now
        )
    }

    func fetchExpenses() async throws -> [ExpenseRecord] { [] }
}

private actor ParseExpenseAuthState {
    private var activeToken: String
    private var recoveryCalls = 0
    private var failureHandlerCalls = 0

    init(activeToken: String) {
        self.activeToken = activeToken
    }

    func currentToken() -> String {
        activeToken
    }

    func recover(with token: String) -> String {
        recoveryCalls += 1
        activeToken = token
        return activeToken
    }

    func registerFailure() {
        failureHandlerCalls += 1
    }

    func recoveryCallCount() -> Int {
        recoveryCalls
    }

    func failureHandlerCallCount() -> Int {
        failureHandlerCalls
    }
}

private final class StubURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "StubURLProtocol", code: -1))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
