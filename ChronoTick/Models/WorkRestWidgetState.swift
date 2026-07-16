import Foundation

enum WorkRestWidgetMode: String, Codable, Equatable {
    case active
    case upcoming
    case empty
    case unavailable
}

enum WorkRestWidgetAccent: String, Codable, Equatable {
    case work
    case rest
    case neutral
}

/// A display-only projection of the app-owned work/rest state.
///
/// The widget never restores a timer session from this value and never derives task selection or
/// phase transitions itself. Absolute dates let WidgetKit render a live countdown without copying
/// the timer engine into the extension.
struct WorkRestWidgetSnapshot: Codable, Equatable {
    static let unavailable = WorkRestWidgetSnapshot(mode: .unavailable)
    static let empty = WorkRestWidgetSnapshot(mode: .empty)

    let schemaVersion: Int
    let mode: WorkRestWidgetMode
    let taskID: UUID?
    let taskTitle: String?
    let taskStartDate: Date?
    let taskEndDate: Date?
    let phaseTitle: String?
    let accent: WorkRestWidgetAccent
    let countdownEndDate: Date?
    let countdownLabel: String?

    init(
        schemaVersion: Int = 1,
        mode: WorkRestWidgetMode,
        taskID: UUID? = nil,
        taskTitle: String? = nil,
        taskStartDate: Date? = nil,
        taskEndDate: Date? = nil,
        phaseTitle: String? = nil,
        accent: WorkRestWidgetAccent = .neutral,
        countdownEndDate: Date? = nil,
        countdownLabel: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.taskStartDate = taskStartDate
        self.taskEndDate = taskEndDate
        self.phaseTitle = phaseTitle
        self.accent = accent
        self.countdownEndDate = countdownEndDate
        self.countdownLabel = countdownLabel
    }
}

/// Theme values copied from the app for display only. The image filename always refers to an
/// optimized asset inside the shared App Group; the widget never reads the app's SwiftData store
/// or its Application Support directory.
struct WorkRestWidgetAppearanceSnapshot: Codable, Equatable {
    static let fallback = WorkRestWidgetAppearanceSnapshot(
        themeHex: "#0A84FF",
        sidebarThemeHex: "#F4F4F6",
        textColorRawValue: "black",
        backgroundCropX: 0.5,
        backgroundCropY: 0.5,
        backgroundCropZoom: 1,
        backgroundFogOpacity: 0.12,
        backgroundImageFilename: nil,
        backgroundResourceVersion: nil
    )

    let schemaVersion: Int
    let themeHex: String
    let sidebarThemeHex: String
    let textColorRawValue: String
    let backgroundCropX: Double
    let backgroundCropY: Double
    let backgroundCropZoom: Double
    let backgroundFogOpacity: Double
    let backgroundImageFilename: String?
    let backgroundResourceVersion: UUID?

    init(
        schemaVersion: Int = 1,
        themeHex: String,
        sidebarThemeHex: String,
        textColorRawValue: String,
        backgroundCropX: Double,
        backgroundCropY: Double,
        backgroundCropZoom: Double,
        backgroundFogOpacity: Double,
        backgroundImageFilename: String?,
        backgroundResourceVersion: UUID?
    ) {
        self.schemaVersion = schemaVersion
        self.themeHex = themeHex
        self.sidebarThemeHex = sidebarThemeHex
        self.textColorRawValue = textColorRawValue
        self.backgroundCropX = backgroundCropX
        self.backgroundCropY = backgroundCropY
        self.backgroundCropZoom = backgroundCropZoom
        self.backgroundFogOpacity = backgroundFogOpacity
        self.backgroundImageFilename = backgroundImageFilename
        self.backgroundResourceVersion = backgroundResourceVersion
    }
}

struct WorkRestWidgetStateStore {
    static let widgetKind = "com.example.ChronoTick.WorkRestWidget"
    static let appGroupInfoKey = "ChronoTickAppGroupIdentifier"

    private static let snapshotKey = "ChronoTick.workRest.widgetSnapshot.v1"
    private static let appearanceKey = "ChronoTick.workRest.widgetAppearance.v1"
    private static let appearanceAssetsDirectoryName = "WorkRestWidgetAssets"
    private let defaults: UserDefaults?
    private let appGroupContainerURL: URL?

    init(
        defaults: UserDefaults? = nil,
        appGroupIdentifier: String? = nil,
        appGroupContainerURL: URL? = nil,
        bundle: Bundle = .main
    ) {
        if let defaults {
            self.defaults = defaults
            self.appGroupContainerURL = appGroupContainerURL
            return
        }

        let identifier = appGroupIdentifier
            ?? bundle.object(forInfoDictionaryKey: Self.appGroupInfoKey) as? String
        self.defaults = identifier.flatMap(UserDefaults.init(suiteName:))
        self.appGroupContainerURL = appGroupContainerURL
            ?? identifier.flatMap(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:))
    }

    func read() -> WorkRestWidgetSnapshot? {
        guard let data = defaults?.data(forKey: Self.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WorkRestWidgetSnapshot.self, from: data)
    }

    @discardableResult
    func write(_ snapshot: WorkRestWidgetSnapshot) -> Bool {
        guard let defaults,
              let data = try? JSONEncoder().encode(snapshot)
        else { return false }
        defaults.set(data, forKey: Self.snapshotKey)
        return true
    }

    func readAppearance() -> WorkRestWidgetAppearanceSnapshot {
        guard let data = defaults?.data(forKey: Self.appearanceKey),
              let snapshot = try? JSONDecoder().decode(WorkRestWidgetAppearanceSnapshot.self, from: data)
        else { return .fallback }
        return snapshot
    }

    @discardableResult
    func writeAppearance(_ snapshot: WorkRestWidgetAppearanceSnapshot) -> Bool {
        guard let defaults,
              let data = try? JSONEncoder().encode(snapshot)
        else { return false }
        defaults.set(data, forKey: Self.appearanceKey)
        return true
    }

    func appearanceAssetURL(filename: String) -> URL? {
        appearanceAssetsDirectoryURL?.appendingPathComponent(filename, isDirectory: false)
    }

    func prepareAppearanceAssetsDirectory() throws -> URL {
        guard let appearanceAssetsDirectoryURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(
            at: appearanceAssetsDirectoryURL,
            withIntermediateDirectories: true
        )
        return appearanceAssetsDirectoryURL
    }

    private var appearanceAssetsDirectoryURL: URL? {
        appGroupContainerURL?.appendingPathComponent(
            Self.appearanceAssetsDirectoryName,
            isDirectory: true
        )
    }
}
