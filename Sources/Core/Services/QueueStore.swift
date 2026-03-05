import Foundation

protocol QueueStoreProtocol: AnyObject {
    var onPersistenceError: ((String) -> Void)? { get set }
    func loadQueue(scopeKey: String?) -> [QueuedCapture]
    func saveQueue(_ queue: [QueuedCapture], scopeKey: String?)
}

protocol ExpenseLedgerStoreProtocol: AnyObject {
    var onPersistenceError: ((String) -> Void)? { get set }
    func loadExpenses(scopeKey: String?) -> [ExpenseRecord]
    func saveExpenses(_ expenses: [ExpenseRecord], scopeKey: String?)
}

extension QueueStoreProtocol {
    func loadQueue() -> [QueuedCapture] {
        loadQueue(scopeKey: nil)
    }

    func saveQueue(_ queue: [QueuedCapture]) {
        saveQueue(queue, scopeKey: nil)
    }
}

extension ExpenseLedgerStoreProtocol {
    func loadExpenses() -> [ExpenseRecord] {
        loadExpenses(scopeKey: nil)
    }

    func saveExpenses(_ expenses: [ExpenseRecord]) {
        saveExpenses(expenses, scopeKey: nil)
    }
}

final class InMemoryQueueStore: QueueStoreProtocol {
    private var queue: [QueuedCapture] = []
    var onPersistenceError: ((String) -> Void)?

    func loadQueue(scopeKey _: String?) -> [QueuedCapture] {
        queue
    }

    func saveQueue(_ queue: [QueuedCapture], scopeKey _: String?) {
        self.queue = queue
    }
}

final class InMemoryExpenseLedgerStore: ExpenseLedgerStoreProtocol {
    private var expenses: [ExpenseRecord] = []
    var onPersistenceError: ((String) -> Void)?

    func loadExpenses(scopeKey _: String?) -> [ExpenseRecord] {
        expenses
    }

    func saveExpenses(_ expenses: [ExpenseRecord], scopeKey _: String?) {
        self.expenses = expenses
    }
}

final class FileQueueStore: QueueStoreProtocol {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fm: FileManager
    private let ioQueue = DispatchQueue(label: "com.speakance.queue-store-io", qos: .utility)
    var onPersistenceError: ((String) -> Void)?

    init(fileManager: FileManager = .default) {
        self.fm = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadQueue(scopeKey: String?) -> [QueuedCapture] {
        let fileURL = Self.makeFileURL(fileManager: fm, filename: Self.filename(base: "queue", scopeKey: scopeKey))
        return ioQueue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            guard let queue = try? decoder.decode([QueuedCapture].self, from: data) else { return [] }
            return queue
        }
    }

    func saveQueue(_ queue: [QueuedCapture], scopeKey: String?) {
        let fileURL = Self.makeFileURL(fileManager: fm, filename: Self.filename(base: "queue", scopeKey: scopeKey))
        ioQueue.sync { [fileURL, fm, encoder, onPersistenceError] in
            do {
                let dir = fileURL.deletingLastPathComponent()
                if !fm.fileExists(atPath: dir.path) {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                let data = try encoder.encode(queue)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                onPersistenceError?("Could not save offline queue data.")
                #if DEBUG
                print("[Speakance] Failed to save queue: \(error)")
                #endif
            }
        }
    }

    fileprivate static func makeFileURL(fileManager: FileManager, filename: String) -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        return base
            .appendingPathComponent("Speakance", isDirectory: true)
            .appendingPathComponent(filename)
    }

    fileprivate static func filename(base: String, scopeKey: String?) -> String {
        guard let scope = normalizedScope(scopeKey), scope != "local" else {
            return "\(base).json"
        }
        return "\(base).\(scope).json"
    }

    private static func normalizedScope(_ scopeKey: String?) -> String? {
        guard let raw = scopeKey?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let lowered = raw.lowercased()
        let invalid = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-").inverted
        let sanitized = lowered.unicodeScalars.map { invalid.contains($0) ? "-" : Character($0) }
        return String(sanitized)
    }
}

final class FileExpenseLedgerStore: ExpenseLedgerStoreProtocol {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fm: FileManager
    private let ioQueue = DispatchQueue(label: "com.speakance.expense-store-io", qos: .utility)
    var onPersistenceError: ((String) -> Void)?

    init(fileManager: FileManager = .default) {
        self.fm = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadExpenses(scopeKey: String?) -> [ExpenseRecord] {
        let fileURL = FileQueueStore.makeFileURL(
            fileManager: fm,
            filename: FileQueueStore.filename(base: "expenses", scopeKey: scopeKey)
        )
        return ioQueue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            guard let expenses = try? decoder.decode([ExpenseRecord].self, from: data) else { return [] }
            return expenses
        }
    }

    func saveExpenses(_ expenses: [ExpenseRecord], scopeKey: String?) {
        let fileURL = FileQueueStore.makeFileURL(
            fileManager: fm,
            filename: FileQueueStore.filename(base: "expenses", scopeKey: scopeKey)
        )
        ioQueue.sync { [fileURL, fm, encoder, onPersistenceError] in
            do {
                let dir = fileURL.deletingLastPathComponent()
                if !fm.fileExists(atPath: dir.path) {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                let data = try encoder.encode(expenses)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                onPersistenceError?("Could not save local expenses data.")
                #if DEBUG
                print("[Speakance] Failed to save expenses: \(error)")
                #endif
            }
        }
    }
}
