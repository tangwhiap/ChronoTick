import Foundation
import SwiftData

@Model
final class HabitCheckIn {
    @Attribute(.unique) var id: UUID
    var date: Date
    var isCheckedIn: Bool

    var habit: Habit?

    init(
        id: UUID = UUID(),
        date: Date,
        isCheckedIn: Bool = true,
        habit: Habit? = nil
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.isCheckedIn = isCheckedIn
        self.habit = habit
    }
}
