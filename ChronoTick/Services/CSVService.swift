import Foundation

enum CSVImportMode: String, CaseIterable, Identifiable {
    case merge
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: return "合并导入"
        case .replace: return "覆盖导入"
        }
    }
}

enum CSVServiceError: LocalizedError {
    case invalidHeader(expected: [String])
    case invalidRow(String)

    var errorDescription: String? {
        switch self {
        case let .invalidHeader(expected):
            return "CSV 表头不正确，期望字段为：\(expected.joined(separator: ", "))"
        case let .invalidRow(message):
            return "CSV 数据存在问题：\(message)"
        }
    }
}

enum CSVService {
    static let taskHeaders = ["id", "date", "title", "start_datetime", "end_datetime", "has_time", "is_completed", "reminder_enabled", "reminder_offset_minutes", "notes", "created_at", "updated_at"]
    static let habitHeaders = ["id", "name", "date", "is_checked_in"]

    static func exportTasks(_ tasks: [TaskItem]) -> String {
        let rows = tasks.map { task in
            [
                task.id.uuidString,
                iso(task.date),
                escape(task.title),
                iso(task.startDateTime),
                iso(task.endDateTime),
                String(task.hasTime),
                String(task.isCompleted),
                String(task.reminderEnabled),
                String(task.reminderOffsetMinutes),
                escape(task.notes ?? ""),
                iso(task.createdAt),
                iso(task.updatedAt)
            ].joined(separator: ",")
        }
        return ([taskHeaders.joined(separator: ",")] + rows).joined(separator: "\n")
    }

    static func exportHabitCheckIns(_ habits: [Habit]) -> String {
        var rows: [String] = [habitHeaders.joined(separator: ",")]
        for habit in habits {
            for checkIn in habit.checkIns
                .filter(\.isCheckedIn)
                .sorted(by: { $0.date < $1.date }) {
                rows.append([
                    checkIn.id.uuidString,
                    escape(habit.name),
                    iso(checkIn.date),
                    String(checkIn.isCheckedIn)
                ].joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n")
    }

    static func importTasks(from csv: String) throws -> [TaskCSVRecord] {
        let rows = try parseCSVRows(csv)
        guard rows.first == taskHeaders else {
            throw CSVServiceError.invalidHeader(expected: taskHeaders)
        }

        return try rows.dropFirst().enumerated().map { index, row in
            guard row.count >= taskHeaders.count else {
                throw CSVServiceError.invalidRow("第 \(index + 2) 行字段数量不足。")
            }
            guard let date = parseISO(row[1]),
                  let hasTime = Bool(row[5]),
                  let isCompleted = Bool(row[6]),
                  let reminderEnabled = Bool(row[7]),
                  let reminderOffset = Int(row[8]),
                  let createdAt = parseISO(row[10]),
                  let updatedAt = parseISO(row[11]) else {
                throw CSVServiceError.invalidRow("第 \(index + 2) 行的日期或布尔值格式不合法。")
            }
            return TaskCSVRecord(
                id: UUID(uuidString: row[0]),
                date: date,
                title: row[2],
                startDateTime: parseISOOptional(row[3]),
                endDateTime: parseISOOptional(row[4]),
                hasTime: hasTime,
                isCompleted: isCompleted,
                reminderEnabled: reminderEnabled,
                reminderOffsetMinutes: reminderOffset,
                notes: row[9].isEmpty ? nil : row[9],
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    static func importHabitCheckIns(from csv: String) throws -> [HabitCSVRecord] {
        let rows = try parseCSVRows(csv)
        guard rows.first == habitHeaders else {
            throw CSVServiceError.invalidHeader(expected: habitHeaders)
        }
        return try rows.dropFirst().enumerated().map { index, row in
            guard row.count >= habitHeaders.count else {
                throw CSVServiceError.invalidRow("第 \(index + 2) 行字段数量不足。")
            }
            let normalizedName = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedName.isEmpty else {
                throw CSVServiceError.invalidRow("第 \(index + 2) 行打卡项目名称为空。")
            }
            guard let date = parseISO(row[2]), let checked = Bool(row[3]) else {
                throw CSVServiceError.invalidRow("第 \(index + 2) 行日期或布尔值格式不合法。")
            }
            return HabitCSVRecord(id: UUID(uuidString: row[0]), name: normalizedName, date: Calendar.current.startOfDay(for: date), isCheckedIn: checked)
        }
    }

    /// Normalizes imported habit rows into the data shape used by the app:
    /// one habit per unique name, and at most one effective check-in state per day.
    ///
    /// If the CSV contains repeated rows for the same habit on the same day, we merge them instead
    /// of treating them as separate habits. A checked-in row wins over an unchecked row because the
    /// current product model represents "unchecked" by the absence of a stored record.
    static func normalizedHabitRecords(_ records: [HabitCSVRecord]) -> [HabitCSVRecord] {
        var grouped: [String: [Date: HabitCSVRecord]] = [:]

        for record in records {
            let day = Calendar.current.startOfDay(for: record.date)
            if let existing = grouped[record.name]?[day] {
                let preferredRecord: HabitCSVRecord
                if existing.isCheckedIn == record.isCheckedIn {
                    preferredRecord = existing.id != nil ? existing : record
                } else {
                    preferredRecord = existing.isCheckedIn ? existing : record
                }
                grouped[record.name]?[day] = HabitCSVRecord(
                    id: preferredRecord.id,
                    name: record.name,
                    date: day,
                    isCheckedIn: preferredRecord.isCheckedIn
                )
            } else {
                grouped[record.name, default: [:]][day] = HabitCSVRecord(
                    id: record.id,
                    name: record.name,
                    date: day,
                    isCheckedIn: record.isCheckedIn
                )
            }
        }

        return grouped
            .keys
            .sorted()
            .flatMap { name in
                grouped[name, default: [:]]
                    .values
                    .sorted { $0.date < $1.date }
            }
    }

    static func merge(taskRecords: [TaskCSVRecord], into existing: [TaskItem], mode: CSVImportMode) -> [TaskCSVRecord] {
        guard mode == .merge else { return taskRecords }

        var seen = Set(existing.map(taskFingerprint))
        var merged: [TaskCSVRecord] = []
        for record in taskRecords {
            let fingerprint = taskFingerprint(record)
            guard !seen.contains(fingerprint) else { continue }
            seen.insert(fingerprint)
            merged.append(record)
        }
        return merged
    }

    private static func taskFingerprint(_ task: TaskItem) -> String {
        "\(task.date.timeIntervalSince1970)|\(task.title.lowercased())|\(task.startDateTime?.timeIntervalSince1970 ?? -1)|\(task.endDateTime?.timeIntervalSince1970 ?? -1)"
    }

    private static func taskFingerprint(_ record: TaskCSVRecord) -> String {
        "\(record.date.timeIntervalSince1970)|\(record.title.lowercased())|\(record.startDateTime?.timeIntervalSince1970 ?? -1)|\(record.endDateTime?.timeIntervalSince1970 ?? -1)"
    }

    private static func iso(_ date: Date?) -> String {
        guard let date else { return "" }
        return ISO8601DateFormatter.chronoTick.string(from: date)
    }

    private static func parseISO(_ text: String) -> Date? {
        ISO8601DateFormatter.chronoTick.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func parseISOOptional(_ text: String) -> Date? {
        text.isEmpty ? nil : parseISO(text)
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func parseCSVRows(_ csv: String) throws -> [[String]] {
        let trimmed = csv.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        let characters = Array(trimmed)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        currentField.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case ",":
                    currentRow.append(currentField)
                    currentField = ""
                case "\n":
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                case "\r":
                    break
                default:
                    currentField.append(character)
                }
            }
            index += 1
        }

        currentRow.append(currentField)
        rows.append(currentRow)
        return rows
    }
}
