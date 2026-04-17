import Foundation

struct ReminderOffset: Hashable, Identifiable {
    let seconds: Int

    var id: Int { seconds }

    var displayText: String {
        if seconds == 0 { return "准时提醒" }

        let direction = seconds < 0 ? "提前" : "延后"
        let magnitude = abs(seconds)
        let daySeconds = 24 * 60 * 60
        let hourSeconds = 60 * 60
        let minuteSeconds = 60

        var remaining = magnitude
        let days = remaining / daySeconds
        remaining %= daySeconds
        let hours = remaining / hourSeconds
        remaining %= hourSeconds
        let minutes = remaining / minuteSeconds
        let secs = remaining % minuteSeconds

        var parts: [String] = []
        if days > 0 { parts.append("\(days)天") }
        if hours > 0 { parts.append("\(hours)小时") }
        if minutes > 0 { parts.append("\(minutes)分钟") }
        if secs > 0 { parts.append("\(secs)秒") }

        return direction + parts.joined()
    }
}

enum ReminderRuleParseError: LocalizedError {
    case emptyRule
    case invalidToken(String)

    var errorDescription: String? {
        switch self {
        case .emptyRule:
            return "提醒规则不能为空。"
        case let .invalidToken(token):
            return "无法解析提醒规则片段：\(token)"
        }
    }
}

enum ReminderRuleParser {
    static func parse(_ raw: String) throws -> [ReminderOffset] {
        let normalized = raw
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "；", with: ";")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { throw ReminderRuleParseError.emptyRule }

        let tokens = normalized
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { throw ReminderRuleParseError.emptyRule }

        let offsets = try tokens.map(parseToken)
        return Array(Set(offsets)).sorted { $0.seconds < $1.seconds }
    }

    static func displayTexts(from raw: String) throws -> [String] {
        try parse(raw).map(\.displayText)
    }

    private static func parseToken(_ token: String) throws -> ReminderOffset {
        let pattern = #"^([+-]?)(\d+(?:\.\d+)?)([dhms]?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)),
              let numberRange = Range(match.range(at: 2), in: token),
              let value = Double(token[numberRange])
        else {
            throw ReminderRuleParseError.invalidToken(token)
        }

        let signRange = Range(match.range(at: 1), in: token)
        let unitRange = Range(match.range(at: 3), in: token)
        let signText = signRange.map { String(token[$0]) } ?? ""
        let unitText = unitRange.map { String(token[$0]) } ?? ""

        let unitSeconds: Double
        switch unitText {
        case "", "m":
            unitSeconds = 60
        case "s":
            unitSeconds = 1
        case "h":
            unitSeconds = 60 * 60
        case "d":
            unitSeconds = 24 * 60 * 60
        default:
            throw ReminderRuleParseError.invalidToken(token)
        }

        let sign: Double = signText == "-" ? -1 : 1
        let seconds = Int((sign * value * unitSeconds).rounded())
        return ReminderOffset(seconds: seconds)
    }
}
