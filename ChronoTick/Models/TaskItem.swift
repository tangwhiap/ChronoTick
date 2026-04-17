import AppKit
import Foundation
import SwiftData
import SwiftUI

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var date: Date
    var startDateTime: Date?
    var endDateTime: Date?
    var hasTime: Bool
    var isCompleted: Bool
    var reminderEnabled: Bool
    var reminderOffsetMinutes: Int
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        startDateTime: Date? = nil,
        endDateTime: Date? = nil,
        hasTime: Bool = false,
        isCompleted: Bool = false,
        reminderEnabled: Bool = false,
        reminderOffsetMinutes: Int = 0,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.date = Calendar.current.startOfDay(for: date)
        self.startDateTime = startDateTime
        self.endDateTime = endDateTime
        self.hasTime = hasTime
        self.isCompleted = isCompleted
        self.reminderEnabled = reminderEnabled
        self.reminderOffsetMinutes = reminderOffsetMinutes
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension TaskItem {
    enum TimingKind: Equatable {
        case untimed
        case point
        case range
    }

    var timingKind: TimingKind {
        if startDateTime != nil, endDateTime != nil {
            return .range
        }
        if startDateTime != nil {
            return .point
        }
        return .untimed
    }

    var displayTimeText: String {
        let formatter = DateFormatter.displayTime
        switch timingKind {
        case .untimed:
            return "无时间"
        case .point:
            guard let startDateTime else { return "无时间" }
            return formatter.string(from: startDateTime)
        case .range:
            guard let startDateTime, let endDateTime else { return "无时间" }
            return "\(formatter.string(from: startDateTime))–\(formatter.string(from: endDateTime))"
        }
    }

    var notificationIdentifier: String {
        "task-\(id.uuidString)"
    }

    func touch() {
        updatedAt = .now
    }

    var isVisibleInWeekView: Bool {
        !isCompleted
    }
}

@Model
final class ProjectTaskList {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ProjectTask.list)
    var tasks: [ProjectTask]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tasks = []
    }

    func touch() {
        updatedAt = .now
    }
}

@Model
final class ProjectTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var isCompleted: Bool
    var deadlineDate: Date?
    var deadlineIncludesTime: Bool
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship var list: ProjectTaskList?

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        deadlineDate: Date? = nil,
        deadlineIncludesTime: Bool = false,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        list: ProjectTaskList? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.deadlineDate = deadlineDate
        self.deadlineIncludesTime = deadlineIncludesTime
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.list = list
    }

    func touch() {
        updatedAt = .now
        list?.touch()
    }
}

@Model
final class DailyTaskReminderRule {
    @Attribute(.unique) var id: UUID
    var titlePattern: String
    var rawRule: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        titlePattern: String,
        rawRule: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.titlePattern = titlePattern
        self.rawRule = rawRule
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func touch() {
        updatedAt = .now
    }
}

@Model
final class ProjectTaskReminderPreferences {
    @Attribute(.unique) var id: UUID
    var remindOneDayBefore: Bool
    var remindOneWeekBefore: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        remindOneDayBefore: Bool = false,
        remindOneWeekBefore: Bool = false,
        reminderHour: Int = 23,
        reminderMinute: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.remindOneDayBefore = remindOneDayBefore
        self.remindOneWeekBefore = remindOneWeekBefore
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func touch() {
        updatedAt = .now
    }
}

@Model
final class AppThemeSettings {
    @Attribute(.unique) var id: UUID
    var themeHex: String
    var sidebarThemeHex: String
    var backgroundImagePath: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        themeHex: String = AppThemeSettings.defaultThemeHex,
        sidebarThemeHex: String = AppThemeSettings.defaultSidebarThemeHex,
        backgroundImagePath: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.themeHex = themeHex
        self.sidebarThemeHex = sidebarThemeHex
        self.backgroundImagePath = backgroundImagePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func touch() {
        updatedAt = .now
    }
}

extension ProjectTask {
    var isVisibleInWeekView: Bool {
        !isCompleted && list != nil && deadlineDate != nil
    }

    var displayDeadlineText: String {
        guard let deadlineDate else { return "无截止时间" }
        if deadlineIncludesTime {
            return DateFormatter.projectTaskDeadlineTime.string(from: deadlineDate)
        }
        return DateFormatter.projectTaskDeadlineDay.string(from: deadlineDate)
    }

    func effectiveDeadlineDate(stackIndex: Int = 0, calendar: Calendar = .chronoTick) -> Date? {
        guard let deadlineDate else { return nil }

        if deadlineIncludesTime {
            return deadlineDate.adding(minutes: -(stackIndex * 15), calendar: calendar)
        }

        let day = calendar.startOfDay(for: deadlineDate)
        return day.setting(hour: 12, minute: 0, calendar: calendar)
    }
}

enum ThemeAssetService {
    private static let backgroundFilename = "theme-background"

    static func ensureThemeSettings(in context: ModelContext) -> AppThemeSettings {
        let descriptor = FetchDescriptor<AppThemeSettings>(sortBy: [SortDescriptor(\.createdAt)])
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let settings = AppThemeSettings()
        context.insert(settings)
        try? context.save()
        return settings
    }

    static func applyBackgroundImage(from sourceURL: URL, to settings: AppThemeSettings) throws {
        let destination = try persistBackgroundImage(from: sourceURL)
        settings.backgroundImagePath = destination.path
        settings.touch()
    }

    static func clearBackgroundImage(for settings: AppThemeSettings) {
        if let existingPath = settings.backgroundImagePath {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: existingPath))
        }
        settings.backgroundImagePath = nil
        settings.touch()
    }

    static func persistBackgroundImage(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let directory = try themeSupportDirectory()
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let destination = directory.appendingPathComponent("\(backgroundFilename).\(ext)")

        for existing in (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            if existing.lastPathComponent.hasPrefix(backgroundFilename) {
                try? fileManager.removeItem(at: existing)
            }
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private static func themeSupportDirectory() throws -> URL {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = supportURL.appendingPathComponent("ChronoTick", isDirectory: true)
        let themeDirectory = appDirectory.appendingPathComponent("ThemeAssets", isDirectory: true)
        try FileManager.default.createDirectory(at: themeDirectory, withIntermediateDirectories: true)
        return themeDirectory
    }
}

extension AppThemeSettings {
    static let defaultThemeHex = "#0A84FF"
    static let defaultSidebarThemeHex = "#F4F4F6"

    var themeColor: Color {
        Color(nsColor: nsThemeColor)
    }

    var nsThemeColor: NSColor {
        NSColor(themeHex: themeHex) ?? NSColor(themeHex: Self.defaultThemeHex) ?? NSColor(calibratedRed: 0.85, green: 0.89, blue: 0.95, alpha: 1)
    }

    /// Theme color 2 is dedicated to surfaces that should stay visually stable even when a
    /// background image is present. In the current app shell that primarily means the sidebar base.
    var sidebarThemeColor: Color {
        Color(nsColor: nsSidebarThemeColor)
    }

    var nsSidebarThemeColor: NSColor {
        NSColor(themeHex: sidebarThemeHex) ?? NSColor(themeHex: Self.defaultSidebarThemeHex) ?? NSColor(calibratedWhite: 0.96, alpha: 1)
    }

    var backgroundImageURL: URL? {
        guard let backgroundImagePath, !backgroundImagePath.isEmpty else { return nil }
        return URL(fileURLWithPath: backgroundImagePath)
    }
}

extension NSColor {
    convenience init?(themeHex hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }

        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }

    var themeHexString: String {
        let rgb = usingColorSpace(.deviceRGB) ?? self
        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
