import Foundation
import SwiftData

enum ReminderSettingsService {
    @MainActor
    static func ensureProjectTaskPreferences(in context: ModelContext) -> ProjectTaskReminderPreferences {
        let descriptor = FetchDescriptor<ProjectTaskReminderPreferences>(sortBy: [SortDescriptor(\.createdAt)])
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let preferences = ProjectTaskReminderPreferences()
        context.insert(preferences)
        try? context.save()
        return preferences
    }

    static func ruleMatchesTaskTitle(_ rule: DailyTaskReminderRule, taskTitle: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: rule.titlePattern) else { return false }
        let range = NSRange(taskTitle.startIndex..., in: taskTitle)
        return regex.firstMatch(in: taskTitle, range: range) != nil
    }

    static func matchedOffsets(for taskTitle: String, rules: [DailyTaskReminderRule]) -> [ReminderOffset] {
        let offsets = rules
            .filter { ruleMatchesTaskTitle($0, taskTitle: taskTitle) }
            .flatMap { (try? ReminderRuleParser.parse($0.rawRule)) ?? [] }

        return Array(Set(offsets)).sorted { $0.seconds < $1.seconds }
    }

    static func displayTexts(for rule: DailyTaskReminderRule) -> [String] {
        (try? ReminderRuleParser.displayTexts(from: rule.rawRule)) ?? []
    }
}
