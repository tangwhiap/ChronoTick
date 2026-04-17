import Foundation
import SwiftData

enum SeedDataService {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) throws {
        SystemHabitService.ensureBuiltInHabits(in: context)
        let taskCount = try context.fetchCount(FetchDescriptor<TaskItem>())
        let customHabitCount = try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)]))
            .filter { !$0.isBuiltIn }
            .count
        guard taskCount == 0, customHabitCount == 0 else { return }

        let today = Calendar.current.startOfDay(for: .now)
        let tasks = [
            TaskItem(title: "晨读", date: today, startDateTime: today.setting(hour: 7, minute: 0), endDateTime: today.setting(hour: 7, minute: 30), hasTime: true, reminderEnabled: true, reminderOffsetMinutes: 10),
            TaskItem(title: "评审需求文档", date: today, startDateTime: today.setting(hour: 10, minute: 0), endDateTime: today.setting(hour: 11, minute: 0), hasTime: true),
            TaskItem(title: "整理无时间任务区域", date: today, hasTime: false),
            TaskItem(title: "晚间散步", date: today.adding(days: 1), startDateTime: today.adding(days: 1).setting(hour: 20, minute: 0), hasTime: true)
        ]
        tasks.forEach { context.insert($0) }

        let habit = Habit(name: "阅读", colorHex: "#5B8DEF")
        context.insert(habit)
        let checkInDates = [0, -1, -2, -4, -5].map { today.adding(days: $0) }
        checkInDates.forEach { date in
            let checkIn = HabitCheckIn(date: date, isCheckedIn: true, habit: habit)
            context.insert(checkIn)
        }
        try context.save()
        SystemHabitService.synchronizeDailyCompletionHabit(for: tasks.map(\.date), in: context)
    }
}
