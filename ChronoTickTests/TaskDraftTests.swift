import XCTest
@testable import ChronoTick

final class TaskDraftTests: XCTestCase {
    func testEditingDraftKeepsOwningChecklistDateWhileShowingActualDate() {
        let calendar = Calendar.chronoTick
        let owningDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 17))!
        let actualStart = calendar.date(from: DateComponents(year: 2026, month: 4, day: 18, hour: 0, minute: 30))!

        let task = TaskItem(
            title: "Complete things &&",
            date: owningDate,
            startDateTime: actualStart,
            hasTime: true
        )

        let draft = TaskDraft(task: task)

        XCTAssertEqual(DateFormatter.numericMonthDayYear.string(from: draft.owningDate), "04/17/26")
        XCTAssertEqual(DateFormatter.numericMonthDayYear.string(from: draft.actualDate), "04/18/26")
        XCTAssertEqual(DateFormatter.displayTime.string(from: draft.startTime), "00:30")
    }

    func testValidatedDraftPreservesChecklistOwnershipWhenActualDateChanges() {
        let calendar = Calendar.chronoTick
        let owningDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 17))!
        let actualDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 18))!

        var draft = TaskDraft(date: owningDate)
        draft.title = "Complete things &&"
        draft.hasTime = true
        draft.owningDate = owningDate
        draft.actualDate = actualDate
        draft.startTime = actualDate.setting(hour: 0, minute: 30, calendar: calendar)!

        let validated = draft.validated()

        XCTAssertEqual(DateFormatter.numericMonthDayYear.string(from: validated?.owningDate ?? .distantPast), "04/17/26")
        XCTAssertEqual(DateFormatter.numericMonthDayYear.string(from: validated?.startDateTime ?? .distantPast), "04/18/26")
        XCTAssertEqual(DateFormatter.displayTime.string(from: validated?.startDateTime ?? .distantPast), "00:30")
    }
}
