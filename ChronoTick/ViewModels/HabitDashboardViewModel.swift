import Foundation
import SwiftData

@MainActor
final class HabitDashboardViewModel: ObservableObject {
    @Published var month: Date
    @Published private(set) var checkedDatesByHabitID: [UUID: Set<Date>] = [:]

    private let calendar: Calendar

    init(calendar: Calendar = .chronoTick) {
        self.calendar = calendar
        self.month = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
    }

    var today: Date {
        calendar.startOfDay(for: .now)
    }

    var currentMonthStart: Date {
        calendar.dateInterval(of: .month, for: today)?.start ?? today
    }

    var canAdvanceMonth: Bool {
        month < currentMonthStart
    }

    func goToPreviousMonth() {
        month = calendar.date(byAdding: .month, value: -1, to: month) ?? month
    }

    func goToNextMonth() {
        guard canAdvanceMonth else { return }
        let next = calendar.date(byAdding: .month, value: 1, to: month) ?? month
        month = min(next, currentMonthStart)
    }

    func clampMonthIfNeeded() {
        if month > currentMonthStart {
            month = currentMonthStart
        } else {
            month = calendar.dateInterval(of: .month, for: month)?.start ?? currentMonthStart
        }
    }

    func reload(habits: [Habit], context: ModelContext) {
        let habitIDs = Set(habits.map(\.id))
        let descriptor = FetchDescriptor<HabitCheckIn>(sortBy: [SortDescriptor(\.date)])
        let fetched = (try? context.fetch(descriptor)) ?? []

        var grouped: [UUID: Set<Date>] = [:]
        for checkIn in fetched {
            guard
                checkIn.isCheckedIn,
                let habitID = checkIn.habit?.id,
                habitIDs.contains(habitID)
            else { continue }

            let normalized = calendar.startOfDay(for: checkIn.date)
            guard normalized <= today else { continue }
            grouped[habitID, default: []].insert(normalized)
        }

        checkedDatesByHabitID = grouped
        clampMonthIfNeeded()
    }

    func checkedDates(for habitID: UUID) -> Set<Date> {
        checkedDatesByHabitID[habitID, default: []]
    }

    func stats(for habitID: UUID) -> HabitStats {
        HabitStatsCalculator.stats(
            for: Array(checkedDates(for: habitID)).sorted(),
            month: month,
            calendar: calendar
        )
    }

    func canToggle(day: Date) -> Bool {
        calendar.startOfDay(for: day) <= today
    }

    func toggle(day: Date, habit: Habit, context: ModelContext) {
        let normalized = calendar.startOfDay(for: day)
        guard normalized <= today else { return }

        var current = checkedDates(for: habit.id)
        let wasChecked = current.contains(normalized)
        if wasChecked {
            current.remove(normalized)
        } else {
            current.insert(normalized)
        }
        checkedDatesByHabitID[habit.id] = current

        do {
            if let existing = try existingCheckIn(on: normalized, habitID: habit.id, context: context) {
                context.delete(existing)
            } else if !wasChecked {
                context.insert(HabitCheckIn(date: normalized, isCheckedIn: true, habit: habit))
            }

            habit.updatedAt = .now
            try context.save()
            reloadHabit(habitID: habit.id, context: context)
        } catch {
            reloadHabit(habitID: habit.id, context: context)
        }
    }

    func delete(habit: Habit, context: ModelContext) {
        guard !habit.isBuiltIn else { return }
        checkedDatesByHabitID[habit.id] = nil
        context.delete(habit)
        try? context.save()
    }

    private func reloadHabit(habitID: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<HabitCheckIn>(sortBy: [SortDescriptor(\.date)])
        let fetched = (try? context.fetch(descriptor)) ?? []
        let set = Set(
            fetched.compactMap { checkIn -> Date? in
                guard
                    checkIn.isCheckedIn,
                    checkIn.habit?.id == habitID
                else { return nil }

                let normalized = calendar.startOfDay(for: checkIn.date)
                return normalized <= today ? normalized : nil
            }
        )
        checkedDatesByHabitID[habitID] = set
    }

    private func existingCheckIn(on day: Date, habitID: UUID, context: ModelContext) throws -> HabitCheckIn? {
        let startOfDay = calendar.startOfDay(for: day)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(24 * 3600)
        let descriptor = FetchDescriptor<HabitCheckIn>(
            predicate: #Predicate<HabitCheckIn> { checkIn in
                checkIn.habit?.id == habitID && checkIn.date >= startOfDay && checkIn.date < nextDay
            },
            sortBy: [SortDescriptor(\.date)]
        )
        return try context.fetch(descriptor).first
    }
}
