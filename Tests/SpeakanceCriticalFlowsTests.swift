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
