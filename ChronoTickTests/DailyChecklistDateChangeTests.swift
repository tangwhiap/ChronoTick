import SwiftData
import XCTest
@testable import ChronoTick

@MainActor
final class DailyChecklistDateChangeTests: XCTestCase {
    func testChangingDailyChecklistDateMovesOwnershipWithoutChangingActualTimes() throws {
        let context = try makeModelContext()
        let calendar = Calendar.chronoTick
        let sourceDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 17))!
        let targetDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 19))!
        let actualStart = calendar.date(from: DateComponents(year: 2026, month: 4, day: 18, hour: 1, minute: 30))!
        let actualEnd = calendar.date(from: DateComponents(year: 2026, month: 4, day: 18, hour: 2, minute: 15))!

        let timedTask = TaskItem(
            title: "Cross-midnight work",
            date: sourceDay,
            startDateTime: actualStart,
            endDateTime: actualEnd,
            hasTime: true
        )
        let untimedTask = TaskItem(title: "Untimed", date: sourceDay)
        context.insert(timedTask)
        context.insert(untimedTask)
        try context.save()

        try TaskMutationCoordinator.changeDailyChecklistDate(
            from: sourceDay,
            to: targetDay,
            modelContext: context
        )

        XCTAssertTrue(Calendar.current.isDate(timedTask.date, inSameDayAs: targetDay))
        XCTAssertTrue(Calendar.current.isDate(untimedTask.date, inSameDayAs: targetDay))
        XCTAssertEqual(timedTask.startDateTime, actualStart)
        XCTAssertEqual(timedTask.endDateTime, actualEnd)
    }

    func testChangingDailyChecklistDateRejectsExistingTargetDate() throws {
        let context = try makeModelContext()
        let calendar = Calendar.chronoTick
        let sourceDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 17))!
        let targetDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 19))!
        let sourceTask = TaskItem(title: "Source", date: sourceDay)
        let targetTask = TaskItem(title: "Target", date: targetDay)
        context.insert(sourceTask)
        context.insert(targetTask)
        try context.save()

        XCTAssertThrowsError(
            try TaskMutationCoordinator.changeDailyChecklistDate(
                from: sourceDay,
                to: targetDay,
                modelContext: context
            )
        ) { error in
            XCTAssertEqual(
                error as? TaskMutationCoordinator.DailyChecklistDateChangeError,
                .targetDateAlreadyExists
            )
        }

        XCTAssertTrue(Calendar.current.isDate(sourceTask.date, inSameDayAs: sourceDay))
        XCTAssertTrue(Calendar.current.isDate(targetTask.date, inSameDayAs: targetDay))
    }

    func testChangingDailyChecklistDateFindsSourceTasksByCalendarDay() throws {
        let context = try makeModelContext()
        let calendar = Calendar.chronoTick
        let sourceDay = calendar.date(from: DateComponents(year: 2026, month: 5, day: 6))!
        let targetDay = calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!
        let legacySourceDate = sourceDay.setting(hour: 22, minute: 0, calendar: calendar)!
        let task = TaskItem(title: "Legacy owning date", date: sourceDay)
        task.date = legacySourceDate
        context.insert(task)
        try context.save()

        try TaskMutationCoordinator.changeDailyChecklistDate(
            from: sourceDay,
            to: targetDay,
            modelContext: context
        )

        XCTAssertTrue(Calendar.current.isDate(task.date, inSameDayAs: targetDay))
    }

    func testChangingCompletedDailyChecklistDateMovesBuiltInCheckIn() throws {
        let context = try makeModelContext()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let sourceDay = calendar.date(byAdding: .day, value: -2, to: today)!
        let targetDay = calendar.date(byAdding: .day, value: -1, to: today)!
        let task = TaskItem(title: "Done", date: sourceDay, isCompleted: true)
        context.insert(task)
        try context.save()

        SystemHabitService.synchronizeDailyCompletionHabit(for: [sourceDay], in: context)
        let habit = try XCTUnwrap(SystemHabitService.builtInDailyCompletionHabit(in: context))
        XCTAssertNotNil(try checkIn(on: sourceDay, habit: habit, in: context))
        XCTAssertNil(try checkIn(on: targetDay, habit: habit, in: context))

        try TaskMutationCoordinator.changeDailyChecklistDate(
            from: sourceDay,
            to: targetDay,
            modelContext: context
        )

        XCTAssertNil(try checkIn(on: sourceDay, habit: habit, in: context))
        XCTAssertNotNil(try checkIn(on: targetDay, habit: habit, in: context))
    }

    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([
            TaskItem.self,
            ProjectTaskListFolder.self,
            ProjectTaskList.self,
            ProjectTask.self,
            DailyTaskReminderRule.self,
            ProjectTaskReminderPreferences.self,
            AppThemeSettings.self,
            SavedThemePreset.self,
            Habit.self,
            HabitCheckIn.self
        ])
        let configuration = ModelConfiguration("ChronoTickTests", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return container.mainContext
    }

    private func checkIn(on date: Date, habit: Habit, in context: ModelContext) throws -> HabitCheckIn? {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<HabitCheckIn>(
            predicate: #Predicate<HabitCheckIn> { checkIn in
                checkIn.date == day
            },
            sortBy: [SortDescriptor(\.date)]
        )
        return try context.fetch(descriptor).first { $0.habit?.id == habit.id }
    }
}
