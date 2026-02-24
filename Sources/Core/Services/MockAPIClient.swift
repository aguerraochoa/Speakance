import Foundation

struct ParseExpenseRequestDTO {
    let clientExpenseID: UUID
    let source: ExpenseSource
    let capturedAtDevice: Date
    let audioDurationSeconds: Int?
    let localAudioFilePath: String?
    let rawText: String
    let timezone: String
    let tripID: UUID?
    let tripName: String?
    let paymentMethodID: UUID?
    let paymentMethodName: String?
}

struct ParseExpenseResponseDTO {
    let status: QueueStatus
    let draft: ExpenseDraft
    let serverExpenseID: UUID?
}

protocol ExpenseAPIClientProtocol {
    func parseExpense(_ request: ParseExpenseRequestDTO) async throws -> ParseExpenseResponseDTO
    func updateExpense(_ request: UpdateExpenseRequestDTO) async throws
    func deleteExpense(_ expenseID: UUID) async throws
    func syncMetadata(_ snapshot: UserMetadataSyncSnapshotDTO) async throws
    func fetchMetadata() async throws -> UserMetadataSyncSnapshotDTO?
    func fetchExpenses() async throws -> [ExpenseRecord]
}

struct UpdateExpenseRequestDTO {
    let expenseID: UUID
    let draft: ExpenseDraft
}

struct UserMetadataSyncSnapshotDTO {
    var categories: [CategoryDefinition]
    var trips: [TripRecord]
    var paymentMethods: [PaymentMethod]
    var activeTripID: UUID?
    var defaultCurrencyCode: String?
}

struct MockExpenseAPIClient: ExpenseAPIClientProtocol {
    func parseExpense(_ request: ParseExpenseRequestDTO) async throws -> ParseExpenseResponseDTO {
        try await Task.sleep(nanoseconds: 400_000_000)
        let lower = request.rawText.lowercased()

        let amountMatch = request.rawText.range(of: #"\d+(?:[.,]\d{1,2})?"#, options: .regularExpression)
        let amountText = amountMatch.map { String(request.rawText[$0]).replacingOccurrences(of: ",", with: ".") } ?? "1"
        let currency = lower.contains("peso") ? "MXN" : "USD"

        let category: String
        switch lower {
        case let s where s.contains("taco") || s.contains("coffee") || s.contains("food"):
            category = "Food"
        case let s where s.contains("uber") || s.contains("taxi") || s.contains("gas"):
            category = "Transport"
        case let s where s.contains("movie") || s.contains("bar"):
            category = "Entertainment"
        case let s where s.contains("amazon") || s.contains("shopping"):
            category = "Shopping"
        case let s where s.contains("rent") || s.contains("bill"):
            category = "Utilities"
        default:
            category = "Other"
        }

        let confidence = category == "Other" ? 0.82 : 0.96
        let draft = ExpenseDraft(
            clientExpenseID: request.clientExpenseID,
            amountText: amountText,
            currency: currency,
            category: category,
            description: request.rawText,
            merchant: "",
            expenseDate: request.capturedAtDevice,
            rawText: request.rawText,
            source: request.source,
            parseConfidence: confidence
        )

        return ParseExpenseResponseDTO(
            status: confidence >= 0.93 ? .saved : .needsReview,
            draft: draft,
            serverExpenseID: nil
        )
    }

    func updateExpense(_ request: UpdateExpenseRequestDTO) async throws {}
    func deleteExpense(_ expenseID: UUID) async throws {}
    func syncMetadata(_ snapshot: UserMetadataSyncSnapshotDTO) async throws {}
    func fetchMetadata() async throws -> UserMetadataSyncSnapshotDTO? { nil }
    func fetchExpenses() async throws -> [ExpenseRecord] { [] }
}
