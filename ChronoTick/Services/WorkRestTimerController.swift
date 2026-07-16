import AppKit
import Combine
import Foundation
import SwiftData
import WidgetKit

final class WorkRestSettingsStore: ObservableObject {
    private enum Key {
        static let workMinutes = "ChronoTick.workRest.defaultWorkMinutes"
        static let restMinutes = "ChronoTick.workRest.defaultRestMinutes"
    }

    private let defaults: UserDefaults

    @Published private(set) var defaultWorkMinutes: Int
    @Published private(set) var defaultRestMinutes: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultWorkMinutes = Self.validStoredValue(
            defaults.object(forKey: Key.workMinutes),
            fallback: WorkRestSettings.defaultWorkMinutes
        )
        defaultRestMinutes = Self.validStoredValue(
            defaults.object(forKey: Key.restMinutes),
            fallback: WorkRestSettings.defaultRestMinutes
        )
    }

    var currentSettings: WorkRestSettings {
        WorkRestSettings(
            workMinutes: defaultWorkMinutes,
            restMinutes: defaultRestMinutes
        )
    }

    func setDefaultWorkMinutes(_ minutes: Int) {
        let normalized = min(
            max(minutes, WorkRestSettings.validMinuteRange.lowerBound),
            WorkRestSettings.validMinuteRange.upperBound
        )
        guard normalized != defaultWorkMinutes else { return }
        defaultWorkMinutes = normalized
        defaults.set(normalized, forKey: Key.workMinutes)
    }

    func setDefaultRestMinutes(_ minutes: Int) {
        let normalized = min(
            max(minutes, WorkRestSettings.validMinuteRange.lowerBound),
            WorkRestSettings.validMinuteRange.upperBound
        )
        guard normalized != defaultRestMinutes else { return }
        defaultRestMinutes = normalized
        defaults.set(normalized, forKey: Key.restMinutes)
    }

    private static func validStoredValue(_ object: Any?, fallback: Int) -> Int {
        guard let number = object as? NSNumber else { return fallback }
        let value = number.intValue
        return WorkRestSettings.validMinuteRange.contains(value) ? value : fallback
    }
}

final class WorkRestWidgetPublisher {
    private let store: WorkRestWidgetStateStore
    private let reloadWidget: () -> Void
    private var lastSnapshot: WorkRestWidgetSnapshot?

    init(
        store: WorkRestWidgetStateStore,
        reloadWidget: @escaping () -> Void
    ) {
        self.store = store
        self.reloadWidget = reloadWidget
        lastSnapshot = store.read()
    }

    static func system() -> WorkRestWidgetPublisher {
        WorkRestWidgetPublisher(store: WorkRestWidgetStateStore()) {
            WidgetCenter.shared.reloadTimelines(ofKind: WorkRestWidgetStateStore.widgetKind)
        }
    }

    @discardableResult
    func publish(_ state: WorkRestPresentationState) -> Bool {
        publish(Self.snapshot(from: state))
    }

    @discardableResult
    func publishUnavailable() -> Bool {
        publish(.unavailable)
    }

    static func snapshot(from state: WorkRestPresentationState) -> WorkRestWidgetSnapshot {
        switch state {
        case let .active(presentation):
            let label: String
            switch presentation.countdownKind {
            case let .phaseTransition(nextPhase):
                label = nextPhase == .rest ? "距离休息" : "距离工作"
            case .taskEnd:
                label = "距离任务结束"
            }

            return WorkRestWidgetSnapshot(
                mode: .active,
                taskID: presentation.task.id,
                taskTitle: presentation.task.title,
                taskStartDate: presentation.task.startDate,
                taskEndDate: presentation.task.endDate,
                phaseTitle: presentation.phase.title,
                accent: presentation.phase == .work ? .work : .rest,
                countdownEndDate: presentation.countdownEndDate,
                countdownLabel: label
            )
        case let .idle(presentation):
            guard let task = presentation.nextTask else { return .empty }
            return WorkRestWidgetSnapshot(
                mode: .upcoming,
                taskID: task.id,
                taskTitle: task.title,
                taskStartDate: task.startDate,
                taskEndDate: task.endDate,
                countdownEndDate: task.startDate,
                countdownLabel: "距离任务开始"
            )
        }
    }

    @discardableResult
    private func publish(_ snapshot: WorkRestWidgetSnapshot) -> Bool {
        guard snapshot != lastSnapshot else { return false }
        guard store.write(snapshot) else { return false }
        lastSnapshot = snapshot
        reloadWidget()
        return true
    }
}

struct WorkRestWidgetThemeSource: Equatable {
    let themeHex: String
    let sidebarThemeHex: String
    let textColorRawValue: String
    let backgroundImagePath: String?
    let backgroundCropX: Double
    let backgroundCropY: Double
    let backgroundCropZoom: Double
    let backgroundFogOpacity: Double

    init(
        themeHex: String,
        sidebarThemeHex: String,
        textColorRawValue: String,
        backgroundImagePath: String?,
        backgroundCropX: Double,
        backgroundCropY: Double,
        backgroundCropZoom: Double,
        backgroundFogOpacity: Double
    ) {
        self.themeHex = themeHex
        self.sidebarThemeHex = sidebarThemeHex
        self.textColorRawValue = textColorRawValue
        self.backgroundImagePath = backgroundImagePath
        self.backgroundCropX = backgroundCropX
        self.backgroundCropY = backgroundCropY
        self.backgroundCropZoom = backgroundCropZoom
        self.backgroundFogOpacity = backgroundFogOpacity
    }

    init(settings: AppThemeSettings) {
        themeHex = settings.themeHex
        sidebarThemeHex = settings.sidebarThemeHex
        textColorRawValue = settings.taskDisplayTextColor.rawValue
        backgroundImagePath = settings.backgroundImagePath
        backgroundCropX = settings.normalizedBackgroundCropX
        backgroundCropY = settings.normalizedBackgroundCropY
        backgroundCropZoom = settings.normalizedBackgroundCropZoom
        backgroundFogOpacity = settings.normalizedBackgroundFogOpacity
    }
}

@MainActor
final class WorkRestWidgetAppearancePublisher: ObservableObject {
    typealias BackgroundRenderer = @MainActor (_ sourceURL: URL, _ destinationURL: URL) throws -> Void

    private let store: WorkRestWidgetStateStore
    private let reloadWidget: () -> Void
    private let renderBackground: BackgroundRenderer
    private let debounceNanoseconds: UInt64
    private var lastPublishedSource: WorkRestWidgetThemeSource?
    private var pendingSource: WorkRestWidgetThemeSource?
    private var pendingTask: Task<Void, Never>?

    init(
        store: WorkRestWidgetStateStore,
        debounceNanoseconds: UInt64 = 250_000_000,
        renderBackground: @escaping BackgroundRenderer = WorkRestWidgetAppearancePublisher.renderOptimizedBackground,
        reloadWidget: @escaping () -> Void
    ) {
        self.store = store
        self.debounceNanoseconds = debounceNanoseconds
        self.renderBackground = renderBackground
        self.reloadWidget = reloadWidget
    }

    static func system() -> WorkRestWidgetAppearancePublisher {
        WorkRestWidgetAppearancePublisher(store: WorkRestWidgetStateStore()) {
            WidgetCenter.shared.reloadTimelines(ofKind: WorkRestWidgetStateStore.widgetKind)
        }
    }

    func schedulePublish(_ source: WorkRestWidgetThemeSource) {
        guard source != lastPublishedSource, source != pendingSource else { return }
        pendingTask?.cancel()
        pendingSource = source
        pendingTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            publishNow(source)
        }
    }

    @discardableResult
    func publishNow(_ source: WorkRestWidgetThemeSource) -> Bool {
        pendingTask?.cancel()
        pendingTask = nil
        pendingSource = nil
        guard source != lastPublishedSource else { return false }

        let previousAppearance = store.readAppearance()
        let resourceVersion = UUID()
        var newFilename: String?

        if let path = source.backgroundImagePath, !path.isEmpty {
            do {
                _ = try store.prepareAppearanceAssetsDirectory()
                let filename = "theme-background-\(resourceVersion.uuidString).jpg"
                guard let destinationURL = store.appearanceAssetURL(filename: filename) else {
                    return false
                }
                try renderBackground(URL(fileURLWithPath: path), destinationURL)
                newFilename = filename
            } catch {
                newFilename = nil
            }
        }

        let appearance = WorkRestWidgetAppearanceSnapshot(
            themeHex: source.themeHex,
            sidebarThemeHex: source.sidebarThemeHex,
            textColorRawValue: source.textColorRawValue,
            backgroundCropX: source.backgroundCropX,
            backgroundCropY: source.backgroundCropY,
            backgroundCropZoom: source.backgroundCropZoom,
            backgroundFogOpacity: source.backgroundFogOpacity,
            backgroundImageFilename: newFilename,
            backgroundResourceVersion: newFilename == nil ? nil : resourceVersion
        )

        guard store.writeAppearance(appearance) else {
            if let newFilename, let url = store.appearanceAssetURL(filename: newFilename) {
                try? FileManager.default.removeItem(at: url)
            }
            return false
        }

        lastPublishedSource = source
        if let oldFilename = previousAppearance.backgroundImageFilename,
           oldFilename != newFilename,
           let oldURL = store.appearanceAssetURL(filename: oldFilename) {
            try? FileManager.default.removeItem(at: oldURL)
        }
        reloadWidget()
        return true
    }

    static func renderOptimizedBackground(sourceURL: URL, destinationURL: URL) throws {
        guard let image = NSImage(contentsOf: sourceURL) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let sourceSize = image.size
        let longestEdge = max(sourceSize.width, sourceSize.height)
        guard longestEdge > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let scale = min(1, 1_600 / longestEdge)
        let pixelWidth = max(1, Int((sourceSize.width * scale).rounded()))
        let pixelHeight = max(1, Int((sourceSize.height * scale).rounded()))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw CocoaError(.fileWriteUnknown) }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw CocoaError(.fileWriteUnknown)
        }
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight).fill()
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()

        guard let data = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.86]
        ) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: destinationURL, options: .atomic)
    }
}

@MainActor
final class WorkRestTimerController: ObservableObject {
    @Published private(set) var presentationState: WorkRestPresentationState

    private let modelContext: ModelContext
    private let settingsStore: WorkRestSettingsStore
    private let notificationScheduler: NotificationScheduler
    private let widgetPublisher: WorkRestWidgetPublisher
    private var engine = WorkRestTimerEngine()
    private var timer: Timer?
    private var notificationTask: Task<Void, Never>?
    private var scheduledNotificationPlan: WorkRestNotificationPlan?

    init(
        modelContext: ModelContext,
        settingsStore: WorkRestSettingsStore,
        notificationScheduler: NotificationScheduler,
        widgetPublisher: WorkRestWidgetPublisher = .system()
    ) {
        self.modelContext = modelContext
        self.settingsStore = settingsStore
        self.notificationScheduler = notificationScheduler
        self.widgetPublisher = widgetPublisher
        presentationState = .idle(WorkRestIdlePresentation(nextTask: nil, now: .now))
    }

    func start() {
        guard timer == nil else { return }
        refresh(now: .now)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(now: .now)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func applyDurations(workMinutes: Int, restMinutes: Int) {
        let now = Date.now
        guard engine.applyDurations(
            workMinutes: workMinutes,
            restMinutes: restMinutes,
            now: now
        ) else { return }
        refresh(now: now)
    }

    func switchNow() {
        let now = Date.now
        guard engine.switchNow(at: now) else { return }
        refresh(now: now)
    }

    func switchAfter(minutes: Int) {
        let now = Date.now
        guard engine.switchAfter(minutes: minutes, now: now) else { return }
        refresh(now: now)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        notificationTask?.cancel()
        notificationTask = nil
        scheduledNotificationPlan = nil
        notificationScheduler.removeWorkRestTransitionNotification()
        widgetPublisher.publishUnavailable()
    }

    private func refresh(now: Date) {
        let descriptor = FetchDescriptor<TaskItem>(
            sortBy: [SortDescriptor(\TaskItem.createdAt)]
        )
        guard let tasks = try? modelContext.fetch(descriptor) else { return }

        let snapshots = tasks.compactMap(Self.snapshot)
        presentationState = engine.update(
            tasks: snapshots,
            now: now,
            defaultSettings: settingsStore.currentSettings
        )
        widgetPublisher.publish(presentationState)
        synchronizeNotification()
    }

    private func synchronizeNotification() {
        let plan = presentationState.notificationPlan
        guard plan != scheduledNotificationPlan else { return }
        scheduledNotificationPlan = plan

        notificationTask?.cancel()
        notificationTask = Task { [notificationScheduler] in
            await notificationScheduler.ensureWorkRestTransitionNotification(plan)
        }
    }

    private static func snapshot(for task: TaskItem) -> WorkRestTaskSnapshot? {
        guard let startDate = task.startDateTime,
              let endDate = task.endDateTime
        else { return nil }

        return WorkRestTaskSnapshot(
            id: task.id,
            title: task.title,
            startDate: startDate,
            endDate: endDate,
            isCompleted: task.isCompleted
        )
    }
}
