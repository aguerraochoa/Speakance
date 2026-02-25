import Foundation

struct ParseExpenseRequestDTO {
    let clientExpenseID: UUID
    let source: ExpenseSource
    let capturedAtDevice: Date
    let audioDurationSeconds: Int?
    let localAudioFilePath: String?
    let rawText: String
    let currencyHint: String?
    let languageHint: String?
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
        let currency = lower.contains("peso") ? "MXN" : (request.currencyHint ?? "USD")

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
        let merchant = Self.detectMerchant(in: request.rawText)
        let description = Self.makeDescription(
            rawText: request.rawText,
            category: category,
            merchant: merchant,
            languageHint: request.languageHint
        )
        let draft = ExpenseDraft(
            clientExpenseID: request.clientExpenseID,
            amountText: amountText,
            currency: currency,
            category: category,
            description: description,
            merchant: merchant ?? "",
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

    private static func detectMerchant(in rawText: String) -> String? {
        let patterns = [
            #"\b(?:at|en)\s+([A-Za-z0-9&'".\- ]{2,40})"#,
        ]
        for pattern in patterns {
            guard let range = rawText.range(of: pattern, options: .regularExpression) else { continue }
            let match = String(rawText[range])
            if let merchantRange = match.range(of: #"(?:at|en)\s+"#, options: .regularExpression) {
                let merchant = String(match[merchantRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
                if !merchant.isEmpty { return merchant }
            }
        }
        return nil
    }

    private static func makeDescription(rawText: String, category: String, merchant: String?, languageHint: String?) -> String {
        let lower = rawText.lowercased()
        let withFriends = lower.contains("friends") || lower.contains("amigos")
        let useSpanish = languageHint == "es"
        if let merchant, withFriends {
            return useSpanish ? "\(category) con amigos en \(merchant)" : "\(category) with friends at \(merchant)"
        }
        if let merchant {
            return useSpanish ? "\(category) en \(merchant)" : "\(category) at \(merchant)"
        }
        if withFriends {
            return useSpanish ? "\(category) con amigos" : "\(category) with friends"
        }
        return rawText
    }
}
