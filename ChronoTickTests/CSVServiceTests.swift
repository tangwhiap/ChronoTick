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
}
