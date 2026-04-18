import XCTest
@testable import ChronoTick

final class CSVServiceTests: XCTestCase {
    func testTaskCSVExportAndImport() throws {
        let base = Calendar.current.startOfDay(for: .now)
        let task = TaskItem(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            title: "Review paper",
            date: base,
            startDateTime: base.setting(hour: 9, minute: 0),
            endDateTime: base.setting(hour: 10, minute: 30),
            hasTime: true,
            reminderEnabled: true,
            reminderOffsetMinutes: 10
        )
        let csv = CSVService.exportTasks([task])
        let imported = try CSVService.importTasks(from: csv)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].title, "Review paper")
        XCTAssertEqual(imported[0].reminderOffsetMinutes, 10)
    }

    func testInvalidHeaderThrows() {
        XCTAssertThrowsError(try CSVService.importTasks(from: "bad,header\n1,2")) { error in
            XCTAssertTrue(error.localizedDescription.contains("CSV 表头"))
        }
    }

    func testHabitCSVNormalizationGroupsRowsByNameAndDay() throws {
        let day = Calendar.current.startOfDay(for: .now)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let csv = """
        id,name,date,is_checked_in
        \(UUID().uuidString),test,\(ISO8601DateFormatter.chronoTick.string(from: day)),true
        \(UUID().uuidString),test,\(ISO8601DateFormatter.chronoTick.string(from: day)),true
        ,test,\(ISO8601DateFormatter.chronoTick.string(from: nextDay)),false
        \(UUID().uuidString),focus,\(ISO8601DateFormatter.chronoTick.string(from: day)),true
        """

        let imported = try CSVService.importHabitCheckIns(from: csv)
        let normalized = CSVService.normalizedHabitRecords(imported)

        XCTAssertEqual(normalized.count, 3)
        XCTAssertEqual(normalized.filter { $0.name == "test" }.count, 2)
        XCTAssertEqual(normalized.filter { $0.name == "focus" }.count, 1)
        XCTAssertEqual(normalized.first { $0.name == "test" && Calendar.current.isDate($0.date, inSameDayAs: day) }?.isCheckedIn, true)
        XCTAssertEqual(normalized.first { $0.name == "test" && Calendar.current.isDate($0.date, inSameDayAs: nextDay) }?.isCheckedIn, false)
    }

    func testHabitExportSkipsUncheckedRows() {
        let day = Calendar.current.startOfDay(for: .now)
        let habit = Habit(name: "test")
        habit.checkIns = [
            HabitCheckIn(date: day, isCheckedIn: true, habit: habit),
            HabitCheckIn(date: Calendar.current.date(byAdding: .day, value: 1, to: day)!, isCheckedIn: false, habit: habit)
        ]

        let csv = CSVService.exportHabitCheckIns([habit])

        XCTAssertTrue(csv.contains("test"))
        XCTAssertTrue(csv.contains("true"))
        XCTAssertFalse(csv.contains("false"))
    }
}
