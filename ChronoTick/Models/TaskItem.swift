import AppKit
import Foundation
import SwiftData
import SwiftUI

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    /// `date` is the owning daily-checklist date.
    ///
    /// This value answers "which daily checklist does the task belong to?" and must stay stable
    /// after creation unless the app explicitly supports reassigning checklist ownership.
    /// It is intentionally distinct from `startDateTime` / `endDateTime`, which describe when the
    /// task actually happens in the calendar timeline.
    var date: Date
    /// Actual start date/time used by the week view and notification scheduling.
    var startDateTime: Date?
    /// Actual end date/time used by timeline rendering for ranged tasks.
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

    var owningDate: Date {
        Calendar.current.startOfDay(for: date)
    }

    var actualDisplayDate: Date {
        startDateTime ?? owningDate
    }

    func touch() {
        updatedAt = .now
    }

    var isVisibleInWeekView: Bool {
        true
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
    var backgroundCropX: Double?
    var backgroundCropY: Double?
    var backgroundCropZoom: Double?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        themeHex: String = AppThemeSettings.defaultThemeHex,
        sidebarThemeHex: String = AppThemeSettings.defaultSidebarThemeHex,
        backgroundImagePath: String? = nil,
        backgroundCropX: Double? = nil,
        backgroundCropY: Double? = nil,
        backgroundCropZoom: Double? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.themeHex = themeHex
        self.sidebarThemeHex = sidebarThemeHex
        self.backgroundImagePath = backgroundImagePath
        self.backgroundCropX = backgroundCropX
        self.backgroundCropY = backgroundCropY
        self.backgroundCropZoom = backgroundCropZoom
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func touch() {
        updatedAt = .now
    }
}

@Model
final class SavedThemePreset {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var name: String
    var themeHex: String
    var sidebarThemeHex: String
    var backgroundImagePath: String?
    var backgroundCropX: Double?
    var backgroundCropY: Double?
    var backgroundCropZoom: Double?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        themeHex: String,
        sidebarThemeHex: String,
        backgroundImagePath: String? = nil,
        backgroundCropX: Double? = nil,
        backgroundCropY: Double? = nil,
        backgroundCropZoom: Double? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.themeHex = themeHex
        self.sidebarThemeHex = sidebarThemeHex
        self.backgroundImagePath = backgroundImagePath
        self.backgroundCropX = backgroundCropX
        self.backgroundCropY = backgroundCropY
        self.backgroundCropZoom = backgroundCropZoom
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
    private static let savedThemeFilenamePrefix = "saved-theme"
    static let exportedThemePackageExtension = "chronoticktheme"
    private static let exportedThemeMetadataFilename = "theme.json"

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
        let destination = try persistImage(from: sourceURL, filenamePrefix: backgroundFilename)
        settings.backgroundImagePath = destination.path
        settings.backgroundCropX = AppThemeSettings.defaultBackgroundCropX
        settings.backgroundCropY = AppThemeSettings.defaultBackgroundCropY
        settings.backgroundCropZoom = AppThemeSettings.defaultBackgroundCropZoom
        settings.touch()
    }

    static func clearBackgroundImage(for settings: AppThemeSettings) {
        deleteCopiedImage(atPath: settings.backgroundImagePath)
        settings.backgroundImagePath = nil
        settings.backgroundCropX = AppThemeSettings.defaultBackgroundCropX
        settings.backgroundCropY = AppThemeSettings.defaultBackgroundCropY
        settings.backgroundCropZoom = AppThemeSettings.defaultBackgroundCropZoom
        settings.touch()
    }

    static func saveCurrentTheme(named rawName: String, from settings: AppThemeSettings, in context: ModelContext) throws {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw ThemePresetError.emptyName }
        let descriptor = FetchDescriptor<SavedThemePreset>(sortBy: [SortDescriptor(\.createdAt)])
        let existingThemes = (try? context.fetch(descriptor)) ?? []
        guard !existingThemes.contains(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) else {
            throw ThemePresetError.duplicateName
        }

        let theme = SavedThemePreset(
            name: trimmedName,
            themeHex: settings.themeHex,
            sidebarThemeHex: settings.sidebarThemeHex,
            backgroundCropX: settings.normalizedBackgroundCropX,
            backgroundCropY: settings.normalizedBackgroundCropY,
            backgroundCropZoom: settings.normalizedBackgroundCropZoom
        )

        if let sourcePath = settings.backgroundImagePath {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let destination = try persistImage(from: sourceURL, filenamePrefix: savedThemeAssetPrefix(for: theme.id))
            theme.backgroundImagePath = destination.path
        }

        context.insert(theme)
        try context.save()
    }

    static func applySavedTheme(_ preset: SavedThemePreset, to settings: AppThemeSettings) throws {
        settings.themeHex = preset.themeHex
        settings.sidebarThemeHex = preset.sidebarThemeHex
        settings.backgroundCropX = preset.normalizedBackgroundCropX
        settings.backgroundCropY = preset.normalizedBackgroundCropY
        settings.backgroundCropZoom = preset.normalizedBackgroundCropZoom

        if let sourcePath = preset.backgroundImagePath {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let destination = try persistImage(from: sourceURL, filenamePrefix: backgroundFilename)
            settings.backgroundImagePath = destination.path
        } else {
            clearBackgroundImage(for: settings)
        }

        settings.touch()
    }

    static func updateSavedTheme(
        _ preset: SavedThemePreset,
        name rawName: String,
        themeHex: String,
        sidebarThemeHex: String,
        cropX: Double,
        cropY: Double,
        cropZoom: Double,
        selectedImageURL: URL?,
        removeBackgroundImage: Bool,
        in context: ModelContext
    ) throws {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw ThemePresetError.emptyName }
        let descriptor = FetchDescriptor<SavedThemePreset>(sortBy: [SortDescriptor(\.createdAt)])
        let existingThemes = (try? context.fetch(descriptor)) ?? []
        guard !existingThemes.contains(where: { $0.id != preset.id && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) else {
            throw ThemePresetError.duplicateName
        }

        preset.name = trimmedName
        preset.themeHex = themeHex
        preset.sidebarThemeHex = sidebarThemeHex
        preset.backgroundCropX = cropX.clamped(to: 0...1)
        preset.backgroundCropY = cropY.clamped(to: 0...1)
        preset.backgroundCropZoom = cropZoom.clamped(to: AppThemeSettings.minimumBackgroundCropZoom...AppThemeSettings.maximumBackgroundCropZoom)

        if removeBackgroundImage {
            deleteCopiedImage(atPath: preset.backgroundImagePath)
            preset.backgroundImagePath = nil
            preset.backgroundCropX = AppThemeSettings.defaultBackgroundCropX
            preset.backgroundCropY = AppThemeSettings.defaultBackgroundCropY
            preset.backgroundCropZoom = AppThemeSettings.defaultBackgroundCropZoom
        } else if let selectedImageURL {
            let destination = try persistImage(from: selectedImageURL, filenamePrefix: savedThemeAssetPrefix(for: preset.id))
            if destination.path != preset.backgroundImagePath {
                deleteCopiedImage(atPath: preset.backgroundImagePath)
            }
            preset.backgroundImagePath = destination.path
        }

        preset.touch()
        try context.save()
    }

    static func deleteSavedTheme(_ preset: SavedThemePreset, in context: ModelContext) throws {
        deleteCopiedImage(atPath: preset.backgroundImagePath)
        context.delete(preset)
        try context.save()
    }

    static func exportSavedTheme(_ preset: SavedThemePreset, to packageURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let imageFilename: String?
        if let backgroundImagePath = preset.backgroundImagePath, !backgroundImagePath.isEmpty {
            let sourceURL = URL(fileURLWithPath: backgroundImagePath)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw ThemePackageError.missingBackgroundImage
            }
            let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
            let exportedImageFilename = "background.\(ext)"
            try fileManager.copyItem(at: sourceURL, to: packageURL.appendingPathComponent(exportedImageFilename))
            imageFilename = exportedImageFilename
        } else {
            imageFilename = nil
        }

        let payload = ExportedThemePackagePayload(
            version: 1,
            name: preset.name,
            themeHex: preset.themeHex,
            sidebarThemeHex: preset.sidebarThemeHex,
            backgroundCropX: preset.normalizedBackgroundCropX,
            backgroundCropY: preset.normalizedBackgroundCropY,
            backgroundCropZoom: preset.normalizedBackgroundCropZoom,
            backgroundImageFilename: imageFilename
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: packageURL.appendingPathComponent(exportedThemeMetadataFilename), options: .atomic)
    }

    static func readThemePackage(from packageURL: URL) throws -> ImportedThemePackage {
        guard packageURL.pathExtension.lowercased() == exportedThemePackageExtension else {
            throw ThemePackageError.invalidPackage
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: packageURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ThemePackageError.invalidPackage
        }

        let metadataURL = packageURL.appendingPathComponent(exportedThemeMetadataFilename)
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw ThemePackageError.missingMetadata
        }

        let payload = try JSONDecoder().decode(ExportedThemePackagePayload.self, from: Data(contentsOf: metadataURL))
        guard payload.version == 1,
              !payload.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              NSColor(themeHex: payload.themeHex) != nil,
              NSColor(themeHex: payload.sidebarThemeHex) != nil
        else {
            throw ThemePackageError.unsupportedMetadata
        }

        let imageURL: URL?
        if let filename = payload.backgroundImageFilename, !filename.isEmpty {
            let candidate = packageURL.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: candidate.path) else {
                throw ThemePackageError.missingBackgroundImage
            }
            imageURL = candidate
        } else {
            imageURL = nil
        }

        return ImportedThemePackage(
            name: payload.name,
            themeHex: payload.themeHex,
            sidebarThemeHex: payload.sidebarThemeHex,
            backgroundCropX: payload.backgroundCropX.clamped(to: 0...1),
            backgroundCropY: payload.backgroundCropY.clamped(to: 0...1),
            backgroundCropZoom: payload.backgroundCropZoom.clamped(to: AppThemeSettings.minimumBackgroundCropZoom...AppThemeSettings.maximumBackgroundCropZoom),
            backgroundImageURL: imageURL
        )
    }

    static func importThemePackage(_ package: ImportedThemePackage, named rawName: String, in context: ModelContext) throws {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw ThemePresetError.emptyName }

        let descriptor = FetchDescriptor<SavedThemePreset>(sortBy: [SortDescriptor(\.createdAt)])
        let existingThemes = (try? context.fetch(descriptor)) ?? []
        guard !existingThemes.contains(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) else {
            throw ThemePresetError.duplicateName
        }

        let preset = SavedThemePreset(
            name: trimmedName,
            themeHex: package.themeHex,
            sidebarThemeHex: package.sidebarThemeHex,
            backgroundCropX: package.backgroundCropX,
            backgroundCropY: package.backgroundCropY,
            backgroundCropZoom: package.backgroundCropZoom
        )

        if let backgroundImageURL = package.backgroundImageURL {
            let destination = try persistImage(from: backgroundImageURL, filenamePrefix: savedThemeAssetPrefix(for: preset.id))
            preset.backgroundImagePath = destination.path
        }

        context.insert(preset)
        try context.save()
    }

    /// Persists a copy of the selected image under a fresh filename every time.
    ///
    /// Using a new path for each update avoids stale UI previews caused by view/image caching when
    /// the app keeps overwriting the same file path in place.
    private static func persistImage(from sourceURL: URL, filenamePrefix: String) throws -> URL {
        let fileManager = FileManager.default
        let directory = try themeSupportDirectory()
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let uniqueSuffix = UUID().uuidString.lowercased()
        let destination = directory.appendingPathComponent("\(filenamePrefix)-\(uniqueSuffix).\(ext)")

        for existing in (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            if existing.lastPathComponent.hasPrefix(filenamePrefix) {
                try? fileManager.removeItem(at: existing)
            }
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private static func savedThemeAssetPrefix(for id: UUID) -> String {
        "\(savedThemeFilenamePrefix)-\(id.uuidString)"
    }

    static func deleteCopiedImage(atPath path: String?) {
        guard let path, !path.isEmpty else { return }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }

    private static func themeSupportDirectory() throws -> URL {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = supportURL.appendingPathComponent("ChronoTick", isDirectory: true)
        let themeDirectory = appDirectory.appendingPathComponent("ThemeAssets", isDirectory: true)
        try FileManager.default.createDirectory(at: themeDirectory, withIntermediateDirectories: true)
        return themeDirectory
    }
}

struct ImportedThemePackage: Identifiable {
    let id = UUID()
    let name: String
    let themeHex: String
    let sidebarThemeHex: String
    let backgroundCropX: Double
    let backgroundCropY: Double
    let backgroundCropZoom: Double
    let backgroundImageURL: URL?
}

private struct ExportedThemePackagePayload: Codable {
    let version: Int
    let name: String
    let themeHex: String
    let sidebarThemeHex: String
    let backgroundCropX: Double
    let backgroundCropY: Double
    let backgroundCropZoom: Double
    let backgroundImageFilename: String?
}

extension AppThemeSettings {
    static let defaultThemeHex = "#0A84FF"
    static let defaultSidebarThemeHex = "#F4F4F6"
    static let defaultBackgroundCropX = 0.5
    static let defaultBackgroundCropY = 0.5
    static let defaultBackgroundCropZoom = 1.0
    static let minimumBackgroundCropZoom = 1.0
    static let maximumBackgroundCropZoom = 4.0

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

    var normalizedBackgroundCropX: Double {
        (backgroundCropX ?? Self.defaultBackgroundCropX).clamped(to: 0...1)
    }

    var normalizedBackgroundCropY: Double {
        (backgroundCropY ?? Self.defaultBackgroundCropY).clamped(to: 0...1)
    }

    var normalizedBackgroundCropZoom: Double {
        (backgroundCropZoom ?? Self.defaultBackgroundCropZoom).clamped(to: Self.minimumBackgroundCropZoom...Self.maximumBackgroundCropZoom)
    }
}

extension SavedThemePreset {
    var themeColor: Color {
        Color(nsColor: nsThemeColor)
    }

    var nsThemeColor: NSColor {
        NSColor(themeHex: themeHex) ?? NSColor(themeHex: AppThemeSettings.defaultThemeHex) ?? NSColor(calibratedRed: 0.04, green: 0.52, blue: 1, alpha: 1)
    }

    var sidebarThemeColor: Color {
        Color(nsColor: nsSidebarThemeColor)
    }

    var nsSidebarThemeColor: NSColor {
        NSColor(themeHex: sidebarThemeHex) ?? NSColor(themeHex: AppThemeSettings.defaultSidebarThemeHex) ?? NSColor(calibratedWhite: 0.96, alpha: 1)
    }

    var backgroundImageURL: URL? {
        guard let backgroundImagePath, !backgroundImagePath.isEmpty else { return nil }
        return URL(fileURLWithPath: backgroundImagePath)
    }

    var normalizedBackgroundCropX: Double {
        (backgroundCropX ?? AppThemeSettings.defaultBackgroundCropX).clamped(to: 0...1)
    }

    var normalizedBackgroundCropY: Double {
        (backgroundCropY ?? AppThemeSettings.defaultBackgroundCropY).clamped(to: 0...1)
    }

    var normalizedBackgroundCropZoom: Double {
        (backgroundCropZoom ?? AppThemeSettings.defaultBackgroundCropZoom).clamped(to: AppThemeSettings.minimumBackgroundCropZoom...AppThemeSettings.maximumBackgroundCropZoom)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

enum ThemePresetError: LocalizedError {
    case emptyName
    case duplicateName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "主题名称不能为空。"
        case .duplicateName:
            return "主题名称不能与现有主题重复。"
        }
    }
}

enum ThemePackageError: LocalizedError {
    case invalidPackage
    case missingMetadata
    case unsupportedMetadata
    case missingBackgroundImage

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            return "请选择有效的 ChronoTick 主题包。"
        case .missingMetadata:
            return "主题包缺少 theme.json。"
        case .unsupportedMetadata:
            return "主题包格式不受支持或内容不完整。"
        case .missingBackgroundImage:
            return "主题包中的背景图片缺失。"
        }
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
