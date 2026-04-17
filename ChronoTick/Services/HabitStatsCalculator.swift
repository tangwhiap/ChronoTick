import Foundation

struct HabitStats: Equatable {
    let streak: Int
    let totalCompleted: Int
    let monthCompletionRate: Double
}

enum HabitStatsCalculator {
    static func stats(for dates: [Date], month: Date, calendar: Calendar = .chronoTick) -> HabitStats {
        let normalized = Set(dates.map { calendar.startOfDay(for: $0) })
        let streak = currentStreak(from: Array(normalized), calendar: calendar)
        let total = normalized.count

        let interval = calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month.startOfDay(in: calendar), duration: 30 * 24 * 3600)
        let monthDates = normalized.filter { interval.contains($0) }
        let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let rate = daysInMonth == 0 ? 0 : Double(monthDates.count) / Double(daysInMonth)
        return HabitStats(streak: streak, totalCompleted: total, monthCompletionRate: rate)
    }

    static func currentStreak(from dates: [Date], calendar: Calendar = .chronoTick) -> Int {
        let normalized = Set(dates.map { calendar.startOfDay(for: $0) })
        guard !normalized.isEmpty else { return 0 }

        var streak = 0
        var cursor = calendar.startOfDay(for: .now)
        if !normalized.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        while normalized.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }
}
