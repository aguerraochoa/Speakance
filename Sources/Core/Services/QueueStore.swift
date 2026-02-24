import Foundation

protocol QueueStoreProtocol: AnyObject {
    func loadQueue() -> [QueuedCapture]
    func saveQueue(_ queue: [QueuedCapture])
}

protocol ExpenseLedgerStoreProtocol: AnyObject {
    func loadExpenses() -> [ExpenseRecord]
    func saveExpenses(_ expenses: [ExpenseRecord])
}

final class InMemoryQueueStore: QueueStoreProtocol {
    private var queue: [QueuedCapture] = []

    func loadQueue() -> [QueuedCapture] {
        queue
    }

    func saveQueue(_ queue: [QueuedCapture]) {
        self.queue = queue
    }
}

final class InMemoryExpenseLedgerStore: ExpenseLedgerStoreProtocol {
    private var expenses: [ExpenseRecord] = []

    func loadExpenses() -> [ExpenseRecord] {
        expenses
    }

    func saveExpenses(_ expenses: [ExpenseRecord]) {
        self.expenses = expenses
    }
}

final class FileQueueStore: QueueStoreProtocol {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fm: FileManager

    init(fileManager: FileManager = .default) {
        self.fm = fileManager
        self.fileURL = Self.makeFileURL(fileManager: fileManager, filename: "queue.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadQueue() -> [QueuedCapture] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let queue = try? decoder.decode([QueuedCapture].self, from: data) else { return [] }
        return queue
    }

    func saveQueue(_ queue: [QueuedCapture]) {
        do {
            try ensureDirectoryExists()
            let data = try encoder.encode(queue)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("[Speakance] Failed to save queue: \(error)")
            #endif
        }
    }

    private func ensureDirectoryExists() throws {
        let dir = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
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
}

final class FileExpenseLedgerStore: ExpenseLedgerStoreProtocol {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fm: FileManager

    init(fileManager: FileManager = .default) {
        self.fm = fileManager
        self.fileURL = FileQueueStore.makeFileURL(fileManager: fileManager, filename: "expenses.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadExpenses() -> [ExpenseRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let expenses = try? decoder.decode([ExpenseRecord].self, from: data) else { return [] }
        return expenses
    }

    func saveExpenses(_ expenses: [ExpenseRecord]) {
        do {
            let dir = fileURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let data = try encoder.encode(expenses)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("[Speakance] Failed to save expenses: \(error)")
            #endif
        }
    }
}
