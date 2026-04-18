import XCTest
@testable import ChronoTick

@MainActor
final class NotificationSchedulerTests: XCTestCase {
    func testNewlyMatchedTitleDoesNotRevivePastImmediateReminderInSameMinute() {
        let calendar = Calendar.chronoTick
        let owningDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 17))!
        let taskStart = calendar.date(from: DateComponents(year: 2026, month: 4, day: 17, hour: 16, minute: 0))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 17, hour: 16, minute: 0, second: 30))!
        let rules = [DailyTaskReminderRule(titlePattern: "&&$", rawRule: "0m;3m")]

        let task = TaskItem(title: "AAA &&", date: owningDate, startDateTime: taskStart, hasTime: true)
        let previousOffsets = Set(ReminderSettingsService.matchedOffsets(for: "AAA", rules: rules).map(\.seconds))
        let newOffsets = Set(ReminderSettingsService.matchedOffsets(for: task.title, rules: rules).map(\.seconds))

        let reminders = NotificationScheduler.shared.scheduledReminders(
            for: task,
            rules: rules,
            now: now,
            suppressCurrentMinuteRecoveryForRuleOffsets: newOffsets.subtracting(previousOffsets)
        )

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.identifier, "task-\(task.id.uuidString)-multi-rule-180")
        XCTAssertEqual(reminders.first?.fireDate, calendar.date(from: DateComponents(year: 2026, month: 4, day: 17, hour: 16, minute: 3)))
    }

    func testExistingMatchingRuleStillRecoversCurrentMinuteReminderAfterReschedule() {
        let calendar = Calendar.chronoTick
        let owningDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 17))!
        let taskStart = calendar.date(from: DateComponents(year: 2026, month: 4, day: 17, hour: 16, minute: 0))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 17, hour: 16, minute: 0, second: 30))!
        let rules = [DailyTaskReminderRule(titlePattern: "&&$", rawRule: "0m;3m")]

        let task = TaskItem(title: "AAA &&", date: owningDate, startDateTime: taskStart, hasTime: true)
        let reminders = NotificationScheduler.shared.scheduledReminders(for: task, rules: rules, now: now)

        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(reminders.map(\.identifier), [
            "task-\(task.id.uuidString)-multi-rule-0",
            "task-\(task.id.uuidString)-multi-rule-180"
        ])
        XCTAssertEqual(reminders.first?.fireDate, now.addingTimeInterval(1))
    }
}
