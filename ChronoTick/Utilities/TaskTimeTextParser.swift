import Foundation

struct ParsedTaskInput: Equatable {
    let title: String
    let startDateTime: Date?
    let endDateTime: Date?
    let hasTime: Bool
}

enum TaskTimeTextParserError: LocalizedError, Equatable {
    case emptyTitle
    case invalidTime
    case invalidRange

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "请输入任务标题。"
        case .invalidTime:
            return "时间格式无法识别，请使用如 09:00 或 23:30~23:50 的格式。"
        case .invalidRange:
            return "结束时间不能早于开始时间，请修改后再保存。"
        }
    }
}

enum TaskTimeTextParser {
    private static let timeToken = #"([+-]?\d{1,2}:\d{2})"#
    private static let rangePattern = try! NSRegularExpression(pattern: #"^\s*\#(timeToken)\s*(?:~|-)\s*\#(timeToken)\s+(.+?)\s*$"#)
    private static let pointPattern = try! NSRegularExpression(pattern: #"^\s*\#(timeToken)\s+(.+?)\s*$"#)

    static func parse(_ rawText: String, on date: Date, calendar: Calendar = .chronoTick) throws -> ParsedTaskInput {
        let text = normalizedInput(rawText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TaskTimeTextParserError.emptyTitle
        }

        if let groups = matchGroups(in: text, regex: rangePattern), groups.count == 4 {
            let start = groups[1]
            let end = groups[2]
            let title = groups[3].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw TaskTimeTextParserError.emptyTitle
            }
            guard let startDate = makeDate(from: start, baseDate: date, calendar: calendar),
                  let endDate = makeDate(from: end, baseDate: date, calendar: calendar) else {
                throw TaskTimeTextParserError.invalidTime
            }
            guard endDate >= startDate else {
                throw TaskTimeTextParserError.invalidRange
            }
            return ParsedTaskInput(title: title, startDateTime: startDate, endDateTime: endDate, hasTime: true)
        }

        if let groups = matchGroups(in: text, regex: pointPattern), groups.count == 3 {
            let start = groups[1]
            let title = groups[2].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw TaskTimeTextParserError.emptyTitle
            }
            guard let startDate = makeDate(from: start, baseDate: date, calendar: calendar) else {
                throw TaskTimeTextParserError.invalidTime
            }
            return ParsedTaskInput(title: title, startDateTime: startDate, endDateTime: nil, hasTime: true)
        }

        return ParsedTaskInput(title: text, startDateTime: nil, endDateTime: nil, hasTime: false)
    }

    private static func makeDate(from timeString: String, baseDate: Date, calendar: Calendar) -> Date? {
        let components = timeString.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return nil }
        let hour = components[0]
        let minute = components[1]
        guard (-47...47).contains(hour), (0...59).contains(minute) else { return nil }

        let totalMinutes = (hour * 60) + (hour >= 0 ? minute : -minute)
        return calendar.date(byAdding: .minute, value: totalMinutes, to: calendar.startOfDay(for: baseDate))
    }

    private static func normalizedInput(_ text: String) -> String {
        var normalized = text
        let replacements: [(String, String)] = [
            ("：", ":"),
            ("﹕", ":"),
            ("∶", ":"),
            ("～", "~"),
            ("〜", "~"),
            ("—", "-"),
            ("–", "-"),
            ("－", "-")
        ]

        for (source, target) in replacements {
            normalized = normalized.replacingOccurrences(of: source, with: target)
        }

        return normalized
    }

    private static func matchGroups(in text: String, regex: NSRegularExpression) -> [String]? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }
}
