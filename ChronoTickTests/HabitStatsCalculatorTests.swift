import XCTest
@testable import ChronoTick

final class HabitStatsCalculatorTests: XCTestCase {
    func testCurrentStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let dates = [today, today.adding(days: -1), today.adding(days: -2), today.adding(days: -4)]
        let streak = HabitStatsCalculator.currentStreak(from: dates, calendar: calendar)
        XCTAssertEqual(streak, 3)
    }
}
