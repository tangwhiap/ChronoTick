import Foundation

extension DateFormatter {
    static let displayTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let displayMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()

    static let numericMonthDayYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd/yy"
        return formatter
    }()

    static let projectTaskDeadlineDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    static let projectTaskDeadlineTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}

extension ISO8601DateFormatter {
    static let chronoTick: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }()
}

extension Calendar {
    static let chronoTick = Calendar(identifier: .gregorian)
}

extension Date {
    func startOfDay(in calendar: Calendar = .chronoTick) -> Date {
        calendar.startOfDay(for: self)
    }

    func adding(days: Int, calendar: Calendar = .chronoTick) -> Date {
        calendar.date(byAdding: .day, value: days, to: self) ?? self
    }

    func adding(minutes: Int, calendar: Calendar = .chronoTick) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: self) ?? self
    }

    func setting(hour: Int, minute: Int, calendar: Calendar = .chronoTick) -> Date? {
        let components = calendar.dateComponents([.year, .month, .day], from: self)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.date(from: components) ?? self)
    }

    var isTodayInCurrentCalendar: Bool {
        Calendar.current.isDateInToday(self)
    }

    func chronoTickClockString(relativeTo anchorDate: Date, calendar: Calendar = .chronoTick) -> String {
        let anchorStart = calendar.startOfDay(for: anchorDate)
        let actualStart = calendar.startOfDay(for: self)
        let dayOffset = calendar.dateComponents([.day], from: anchorStart, to: actualStart).day ?? 0
        let components = calendar.dateComponents([.hour, .minute], from: self)
        let totalHour = dayOffset * 24 + (components.hour ?? 0)
        let minute = components.minute ?? 0
        return String(format: "%02d:%02d", totalHour, minute)
    }
}
