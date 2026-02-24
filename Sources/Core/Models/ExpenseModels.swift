import Foundation

enum ExpenseSource: String, Codable, CaseIterable, Sendable {
    case voice
    case text
}

enum ParseStatus: String, Codable, Sendable {
    case auto
    case edited
    case failed
}

enum QueueStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case syncing
    case needsReview = "needs_review"
    case saved
    case failed
}

enum PaymentMethodType: String, Codable, CaseIterable, Sendable {
    case creditCard = "credit_card"
    case debitCard = "debit_card"
    case cash
    case applePay = "apple_pay"
    case bankTransfer = "bank_transfer"
    case other

    var title: String {
        switch self {
        case .creditCard: return "Credit"
        case .debitCard: return "Debit"
        case .cash: return "Cash"
        case .applePay: return "Apple Pay"
        case .bankTransfer: return "Bank"
        case .other: return "Other"
        }
    }
}

struct CategoryDefinition: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var colorHex: String?
    var isDefault: Bool
    var hintKeywords: [String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String? = nil,
        isDefault: Bool = false,
        hintKeywords: [String] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isDefault = isDefault
        self.hintKeywords = hintKeywords
        self.createdAt = createdAt
    }
}

struct TripRecord: Identifiable, Codable, Equatable, Sendable {
    enum Status: String, Codable, CaseIterable, Sendable {
        case planned
        case active
        case completed
    }

    let id: UUID
    var name: String
    var destination: String?
    var startDate: Date
    var endDate: Date?
    var baseCurrency: String?
    var status: Status
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        destination: String? = nil,
        startDate: Date = .now,
        endDate: Date? = nil,
        baseCurrency: String? = nil,
        status: Status = .planned,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.baseCurrency = baseCurrency
        self.status = status
        self.createdAt = createdAt
    }
}

struct PaymentMethod: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var type: PaymentMethodType
    var network: String?
    var last4: String?
    var aliases: [String]
    var isDefault: Bool
    var isActive: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        type: PaymentMethodType,
        network: String? = nil,
        last4: String? = nil,
        aliases: [String] = [],
        isDefault: Bool = false,
        isActive: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.network = network
        self.last4 = last4
        self.aliases = aliases
        self.isDefault = isDefault
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

struct ExpenseRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let clientExpenseID: UUID
    var amount: Decimal
    var currency: String
    var category: String
    var categoryID: UUID?
    var description: String?
    var merchant: String?
    var tripID: UUID?
    var tripName: String?
    var paymentMethodID: UUID?
    var paymentMethodName: String?
    var expenseDate: Date
    var capturedAtDevice: Date
    var syncedAt: Date?
    var source: ExpenseSource
    var parseStatus: ParseStatus
    var parseConfidence: Double?
    var rawText: String?
    var audioDurationSeconds: Int?
    var createdAt: Date
    var updatedAt: Date
}

struct ExpenseDraft: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let clientExpenseID: UUID
    var amountText: String
    var currency: String
    var category: String
    var categoryID: UUID?
    var description: String
    var merchant: String
    var tripID: UUID?
    var tripName: String?
    var paymentMethodID: UUID?
    var paymentMethodName: String?
    var expenseDate: Date
    var rawText: String
    var source: ExpenseSource
    var parseConfidence: Double?

    init(
        id: UUID = UUID(),
        clientExpenseID: UUID = UUID(),
        amountText: String = "",
        currency: String = "USD",
        category: String = "Other",
        categoryID: UUID? = nil,
        description: String = "",
        merchant: String = "",
        tripID: UUID? = nil,
        tripName: String? = nil,
        paymentMethodID: UUID? = nil,
        paymentMethodName: String? = nil,
        expenseDate: Date = .now,
        rawText: String = "",
        source: ExpenseSource,
        parseConfidence: Double? = nil
    ) {
        self.id = id
        self.clientExpenseID = clientExpenseID
        self.amountText = amountText
        self.currency = currency
        self.category = category
        self.categoryID = categoryID
        self.description = description
        self.merchant = merchant
        self.tripID = tripID
        self.tripName = tripName
        self.paymentMethodID = paymentMethodID
        self.paymentMethodName = paymentMethodName
        self.expenseDate = expenseDate
        self.rawText = rawText
        self.source = source
        self.parseConfidence = parseConfidence
    }
}

struct QueuedCapture: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let clientExpenseID: UUID
    let source: ExpenseSource
    let capturedAt: Date
    var localAudioFilePath: String?
    var audioDurationSeconds: Int?
    var rawText: String?
    var tripID: UUID?
    var tripName: String?
    var paymentMethodID: UUID?
    var paymentMethodName: String?
    var status: QueueStatus
    var retryCount: Int
    var lastError: String?
    var parsedDraft: ExpenseDraft?
    var serverExpenseID: UUID?

    init(
        id: UUID = UUID(),
        clientExpenseID: UUID = UUID(),
        source: ExpenseSource,
        capturedAt: Date = .now,
        localAudioFilePath: String? = nil,
        audioDurationSeconds: Int? = nil,
        rawText: String? = nil,
        tripID: UUID? = nil,
        tripName: String? = nil,
        paymentMethodID: UUID? = nil,
        paymentMethodName: String? = nil,
        status: QueueStatus = .pending,
        retryCount: Int = 0,
        lastError: String? = nil,
        parsedDraft: ExpenseDraft? = nil,
        serverExpenseID: UUID? = nil
    ) {
        self.id = id
        self.clientExpenseID = clientExpenseID
        self.source = source
        self.capturedAt = capturedAt
        self.localAudioFilePath = localAudioFilePath
        self.audioDurationSeconds = audioDurationSeconds
        self.rawText = rawText
        self.tripID = tripID
        self.tripName = tripName
        self.paymentMethodID = paymentMethodID
        self.paymentMethodName = paymentMethodName
        self.status = status
        self.retryCount = retryCount
        self.lastError = lastError
        self.parsedDraft = parsedDraft
        self.serverExpenseID = serverExpenseID
    }
}

struct ReviewContext: Identifiable, Equatable, Sendable {
    let id = UUID()
    let queueID: UUID?
    let expenseID: UUID?
    var draft: ExpenseDraft

    init(queueID: UUID? = nil, expenseID: UUID? = nil, draft: ExpenseDraft) {
        self.queueID = queueID
        self.expenseID = expenseID
        self.draft = draft
    }
}

enum AppTab: Hashable {
    case capture
    case feed
    case insights
    case settings
}
