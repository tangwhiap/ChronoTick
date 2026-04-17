import Foundation
import SwiftData

enum SystemHabitService {
    static let dailyCompletionKey = "daily_completion"
    static let defaultDailyCompletionName = "完成每日任务"

    @MainActor
    static func ensureBuiltInHabits(in context: ModelContext) {
        if builtInDailyCompletionHabit(in: context) != nil {
            return
        }

        let fallbackName = uniqueHabitName(
            startingWith: defaultDailyCompletionName,
            excludingHabitID: nil,
            in: context
        )
        let habit = Habit(
            name: fallbackName,
            colorHex: "#34C759",
            isBuiltIn: true,
            builtInKey: dailyCompletionKey
        )
        context.insert(habit)
        try? context.save()
    }

    @MainActor
    static func builtInDailyCompletionHabit(in context: ModelContext) -> Habit? {
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate<Habit> { habit in
                habit.isBuiltIn && habit.builtInKey == dailyCompletionKey
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try? context.fetch(descriptor).first
    }

    @MainActor
    static func uniqueHabitName(startingWith proposedName: String, excludingHabitID: UUID?, in context: ModelContext) -> String {
        let normalized = normalizedHabitName(proposedName)
        let habits = (try? context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []

        guard habits.contains(where: {
            normalizedHabitName($0.name) == normalized && $0.id != excludingHabitID
        }) else {
            return proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var suffix = 2
        while true {
            let candidate = "\(proposedName.trimmingCharacters(in: .whitespacesAndNewlines)) \(suffix)"
            let candidateNormalized = normalizedHabitName(candidate)
            let exists = habits.contains {
                normalizedHabitName($0.name) == candidateNormalized && $0.id != excludingHabitID
            }
            if !exists {
                return candidate
            }
            suffix += 1
        }
    }

    @MainActor
    static func isHabitNameDuplicate(_ proposedName: String, excludingHabitID: UUID?, in context: ModelContext) -> Bool {
        let normalized = normalizedHabitName(proposedName)
        let habits = (try? context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return habits.contains {
            normalizedHabitName($0.name) == normalized && $0.id != excludingHabitID
        }
    }

    @MainActor
    static func synchronizeDailyCompletionHabit(for owningDates: [Date], in context: ModelContext) {
        ensureBuiltInHabits(in: context)
        guard let habit = builtInDailyCompletionHabit(in: context) else { return }

        let calendar = Calendar.current
        let uniqueDates = Set(owningDates.map { calendar.startOfDay(for: $0) })
        for date in uniqueDates {
            synchronizeDailyCompletionHabit(for: date, habit: habit, in: context)
        }

        habit.updatedAt = .now
        try? context.save()
    }

    @MainActor
    static func rename(_ habit: Habit, to proposedName: String, in context: ModelContext) -> Bool {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !isHabitNameDuplicate(trimmed, excludingHabitID: habit.id, in: context) else { return false }

        habit.name = trimmed
        habit.updatedAt = .now
        try? context.save()
        return true
    }

    @MainActor
    private static func synchronizeDailyCompletionHabit(for owningDate: Date, habit: Habit, in context: ModelContext) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: owningDate)
        let today = calendar.startOfDay(for: .now)

        let tasksDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { task in
                task.date == day
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let tasks = (try? context.fetch(tasksDescriptor)) ?? []
        let shouldBeChecked = !tasks.isEmpty && tasks.allSatisfy(\.isCompleted) && day <= today

        let checkInDescriptor = FetchDescriptor<HabitCheckIn>(
            predicate: #Predicate<HabitCheckIn> { checkIn in
                checkIn.date == day
            },
            sortBy: [SortDescriptor(\.date)]
        )
        let existing = (try? context.fetch(checkInDescriptor))?.first {
            $0.habit?.id == habit.id
        }

        if shouldBeChecked {
            if existing == nil {
                context.insert(HabitCheckIn(date: day, isCheckedIn: true, habit: habit))
            }
        } else if let existing {
            context.delete(existing)
        }
    }

    private static func normalizedHabitName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
