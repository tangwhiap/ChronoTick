import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct TaskCSVRecord: Codable, Equatable {
    var id: UUID?
    var date: Date
    var title: String
    var startDateTime: Date?
    var endDateTime: Date?
    var hasTime: Bool
    var isCompleted: Bool
    var reminderEnabled: Bool
    var reminderOffsetMinutes: Int
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
}

struct HabitCSVRecord: Codable, Equatable {
    var id: UUID?
    var name: String
    var date: Date
    var isCheckedIn: Bool
}
