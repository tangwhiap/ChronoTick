import XCTest
@testable import ChronoTick

final class TaskTimeTextParserTests: XCTestCase {
    func testRangeInput() throws {
        let date = Calendar.current.startOfDay(for: .now)
        let parsed = try TaskTimeTextParser.parse("23:30 ~ 23:50 read book", on: date)
        XCTAssertEqual(parsed.title, "read book")
        XCTAssertEqual(DateFormatter.displayTime.string(from: parsed.startDateTime!), "23:30")
        XCTAssertEqual(DateFormatter.displayTime.string(from: parsed.endDateTime!), "23:50")
        XCTAssertTrue(parsed.hasTime)
    }

    func testRangeInputSupportsChinesePunctuationAndFlexibleSpacing() throws {
        let date = Calendar.current.startOfDay(for: .now)
        let samples = [
            "8:00~10:00 focus work",
            "8:00 ~ 10:00 focus work",
            "8：00～10：00 focus work",
            "8：00 ～ 10：00 focus work",
            "8:00 ～ 10:00 focus work",
            "8:00    ~ 10:00 focus work",
            "8:00-10:00 focus work"
        ]

        for sample in samples {
            let parsed = try TaskTimeTextParser.parse(sample, on: date)
            XCTAssertEqual(parsed.title, "focus work")
            XCTAssertEqual(DateFormatter.displayTime.string(from: parsed.startDateTime!), "08:00")
            XCTAssertEqual(DateFormatter.displayTime.string(from: parsed.endDateTime!), "10:00")
            XCTAssertTrue(parsed.hasTime)
        }
    }

    func testPointInput() throws {
        let date = Calendar.current.startOfDay(for: .now)
        let parsed = try TaskTimeTextParser.parse(" 5:30 get up ", on: date)
        XCTAssertEqual(parsed.title, "get up")
        XCTAssertEqual(DateFormatter.displayTime.string(from: parsed.startDateTime!), "05:30")
        XCTAssertNil(parsed.endDateTime)
    }

    func testPointInputBeyondMidnightKeepsNextDayActualTime() throws {
        let calendar = Calendar.chronoTick
        let baseDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let parsed = try TaskTimeTextParser.parse("25:30 late work", on: baseDate, calendar: calendar)

        XCTAssertEqual(parsed.title, "late work")
        XCTAssertEqual(DateFormatter.displayTime.string(from: parsed.startDateTime!), "01:30")
        XCTAssertEqual(DateFormatter.numericMonthDayYear.string(from: parsed.startDateTime!), "04/16/26")
        XCTAssertNil(parsed.endDateTime)
    }

    func testRangeInputBeyondMidnightUsesActualNextDayTime() throws {
        let calendar = Calendar.chronoTick
        let baseDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let parsed = try TaskTimeTextParser.parse("23:30-25:00 overnight", on: baseDate, calendar: calendar)

        XCTAssertEqual(DateFormatter.displayTime.string(from: parsed.startDateTime!), "23:30")
        XCTAssertEqual(DateFormatter.displayTime.string(from: parsed.endDateTime!), "01:00")
        XCTAssertEqual(DateFormatter.numericMonthDayYear.string(from: parsed.endDateTime!), "04/16/26")
    }

    func testNegativePointInputUsesPreviousDayActualTime() throws {
        let calendar = Calendar.chronoTick
        let baseDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 17))!
        let parsed = try TaskTimeTextParser.parse("-03:00 early prep", on: baseDate, calendar: calendar)

        XCTAssertEqual(parsed.title, "early prep")
        XCTAssertEqual(DateFormatter.displayTime.string(from: parsed.startDateTime!), "21:00")
        XCTAssertEqual(DateFormatter.numericMonthDayYear.string(from: parsed.startDateTime!), "04/16/26")
    }

    func testUntimedInput() throws {
        let date = Calendar.current.startOfDay(for: .now)
        let parsed = try TaskTimeTextParser.parse("Complete things", on: date)
        XCTAssertEqual(parsed.title, "Complete things")
        XCTAssertFalse(parsed.hasTime)
    }

    func testInvalidRange() {
        let date = Calendar.current.startOfDay(for: .now)
        XCTAssertThrowsError(try TaskTimeTextParser.parse("10:30-09:30 wrong", on: date)) { error in
            XCTAssertEqual(error as? TaskTimeTextParserError, .invalidRange)
        }
    }
}
