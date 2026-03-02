import XCTest
@testable import Speakance

@MainActor
final class SpeakanceCriticalFlowsTests: XCTestCase {
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

    func testParseExpenseRetriesOnceAfterUnauthorizedWithRecoveredToken() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }

        let projectURL = URL(string: "https://pyramncggeecifntwlop.supabase.co")!
        let config = SupabaseAppConfig(url: projectURL, anonKey: "anon")

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

        var activeToken = "bad-token"
        var recoveryCalls = 0
        var failureHandlerCalls = 0
        let client = SupabaseFunctionExpenseAPIClient(
            config: config,
            accessTokenProvider: { activeToken },
            unauthorizedRecoveryProvider: {
                recoveryCalls += 1
                activeToken = "good-token"
                return activeToken
            },
            authenticationFailureHandler: { _ in
                failureHandlerCalls += 1
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

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(recoveryCalls, 1)
        XCTAssertEqual(failureHandlerCalls, 0)
        XCTAssertEqual(response.status, .saved)
        XCTAssertEqual(response.serverExpenseID, expectedExpenseID)
    }

    private func makeExpense(amount: Decimal) -> ExpenseRecord {
        ExpenseRecord(
            id: UUID(),
            clientExpenseID: UUID(),
            amount: amount,
            currency: "USD",
            category: "Food",
            categoryID: nil,
            description: "Test expense",
            merchant: "Cafe",
            tripID: nil,
            tripName: nil,
            paymentMethodID: nil,
            paymentMethodName: nil,
            expenseDate: .now,
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

    func loadQueue() -> [QueuedCapture] { [] }

    func saveQueue(_ queue: [QueuedCapture]) {
        onPersistenceError?("Could not save offline queue data.")
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
