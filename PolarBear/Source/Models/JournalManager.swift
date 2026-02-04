import Combine
import Foundation
import SwiftUI

struct JournalEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var content: String
    var autoSummary: String
    let createdAt: Date

    init(
        id: UUID = UUID(), date: Date = Date(), content: String = "", autoSummary: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.content = content
        self.autoSummary = autoSummary
        self.createdAt = createdAt
    }
}

class JournalManager: ObservableObject {
    @Published var entries: [JournalEntry] = [] {
        didSet {
            save()
        }
    }

    private let storageKey = "journal_entries"

    init() {
        load()
    }

    func add(entry: JournalEntry) {
        entries.insert(entry, at: 0)  // Newest first
    }

    func update(entry: JournalEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        }
    }

    func delete(entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data)
        {
            entries = decoded.sorted(by: { $0.date > $1.date })
        }
    }
}
