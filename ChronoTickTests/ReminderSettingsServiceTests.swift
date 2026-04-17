import XCTest
@testable import ChronoTick

final class ReminderSettingsServiceTests: XCTestCase {
    func testMatchedOffsetsAppearImmediatelyAfterTitleStartsMatchingRule() {
        let rules = [
            DailyTaskReminderRule(titlePattern: "&&$", rawRule: "-1m")
        ]

        XCTAssertTrue(ReminderSettingsService.matchedOffsets(for: "AA", rules: rules).isEmpty)

        let matched = ReminderSettingsService.matchedOffsets(for: "AA &&", rules: rules)
        XCTAssertEqual(matched.map(\.seconds), [-60])
    }

    func testMatchedOffsetsDisappearImmediatelyAfterTitleStopsMatchingRule() {
        let rules = [
            DailyTaskReminderRule(titlePattern: "&&$", rawRule: "-1m")
        ]

        XCTAssertEqual(
            ReminderSettingsService.matchedOffsets(for: "BB &&", rules: rules).map(\.seconds),
            [-60]
        )

        XCTAssertTrue(ReminderSettingsService.matchedOffsets(for: "BB", rules: rules).isEmpty)
    }

    func testMultipleMatchingRulesAreMergedAndDeduplicated() {
        let rules = [
            DailyTaskReminderRule(titlePattern: "AA", rawRule: "-1m;-30s"),
            DailyTaskReminderRule(titlePattern: "&&$", rawRule: "-1m;30s")
        ]

        let offsets = ReminderSettingsService.matchedOffsets(for: "AA &&", rules: rules)
        XCTAssertEqual(offsets.map(\.seconds), [-60, -30, 30])
    }
}
