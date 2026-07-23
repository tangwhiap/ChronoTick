import AppKit
import SwiftData
import SwiftUI

@main
struct ChronoTickApp: App {
    @NSApplicationDelegateAdaptor(ChronoTickApplicationDelegate.self) private var applicationDelegate
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var workRestSettings: WorkRestSettingsStore
    @StateObject private var workRestController: WorkRestTimerController
    @StateObject private var widgetAppearancePublisher: WorkRestWidgetAppearancePublisher
    private let container: ModelContainer

    init() {
        let schema = Schema([
            TaskItem.self,
            ProjectTaskListFolder.self,
            ProjectTaskList.self,
            ProjectTask.self,
            DailyTaskReminderRule.self,
            ProjectTaskReminderPreferences.self,
            AppThemeSettings.self,
            SavedThemePreset.self,
            Habit.self,
            HabitCheckIn.self
        ])
        let configuration = Self.makeConfiguration(schema: schema)
        let container = Self.makeContainer(schema: schema, configuration: configuration)
        self.container = container
        Self.removeOrphanedProjectTasks(in: container.mainContext)
        _ = ReminderSettingsService.ensureProjectTaskPreferences(in: container.mainContext)
        let themeSettings = ThemeAssetService.ensureThemeSettings(in: container.mainContext)
        ThemeAssetService.importBundledThemePackagesIfNeeded(in: container.mainContext)
        SystemHabitService.ensureBuiltInHabits(in: container.mainContext)
        try? SeedDataService.seedIfNeeded(in: container.mainContext)
        let existingTasks = (try? container.mainContext.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.date)]))) ?? []
        SystemHabitService.synchronizeDailyCompletionHabit(for: existingTasks.map(\.date), in: container.mainContext)
        let mainContext = container.mainContext
        Task { @MainActor in
            await NotificationScheduler.shared.ensureNotificationStateForAllTasks(in: mainContext)
        }

        let workRestSettings = WorkRestSettingsStore()
        let workRestController = WorkRestTimerController(
            modelContext: mainContext,
            settingsStore: workRestSettings,
            notificationScheduler: .shared
        )
        let widgetAppearancePublisher = WorkRestWidgetAppearancePublisher.system()
        widgetAppearancePublisher.publishNow(WorkRestWidgetThemeSource(settings: themeSettings))
        workRestController.start()
        _workRestSettings = StateObject(wrappedValue: workRestSettings)
        _workRestController = StateObject(wrappedValue: workRestController)
        _widgetAppearancePublisher = StateObject(wrappedValue: widgetAppearancePublisher)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootSplitView()
                .environmentObject(viewModel)
                .environmentObject(workRestSettings)
                .environmentObject(workRestController)
                .environmentObject(widgetAppearancePublisher)
                .modelContainer(container)
        }
        .defaultSize(width: 1340, height: 860)
        .commands {
            WeekTimelineZoomCommands(viewModel: viewModel)
        }

        MenuBarExtra("ChronoTick", systemImage: "clock.badge.checkmark") {
            MenuBarPanelView()
                .environmentObject(viewModel)
                .environmentObject(workRestSettings)
                .environmentObject(workRestController)
                .modelContainer(container)
                .frame(width: 320)
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
private final class ChronoTickApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        NotificationScheduler.shared.removeWorkRestTransitionNotification()
        WorkRestWidgetPublisher.system().publishUnavailable()
    }
}

private extension ChronoTickApp {
    static func makeConfiguration(schema: Schema) -> ModelConfiguration {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = supportURL.appendingPathComponent("ChronoTick", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        let storeURL = appDirectory.appendingPathComponent("ChronoTick.store")
        return ModelConfiguration("ChronoTick", schema: schema, url: storeURL, cloudKitDatabase: .none)
    }

    static func makeContainer(schema: Schema, configuration: ModelConfiguration) -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Never delete an existing store in an attempt to recover automatically. A launch
            // failure is visible and recoverable; silent deletion of user tasks is not.
            fatalError("无法打开 ChronoTick 用户数据库，原数据已保留在 \(configuration.url.path)：\(error)")
        }
    }

    static func removeOrphanedProjectTasks(in context: ModelContext) {
        let descriptor = FetchDescriptor<ProjectTask>(sortBy: [SortDescriptor(\.createdAt)])
        guard let tasks = try? context.fetch(descriptor) else { return }

        var removedAny = false
        for task in tasks where task.list == nil {
            context.delete(task)
            removedAny = true
        }

        if removedAny {
            try? context.save()
        }
    }
}

/// These commands mirror the familiar macOS zoom shortcuts so the week timeline can be resized
/// quickly when the user moves between monitors with very different pixel densities.
private struct WeekTimelineZoomCommands: Commands {
    @ObservedObject var viewModel: AppViewModel

    var body: some Commands {
        CommandMenu("视图") {
            Button("放大周视图") {
                viewModel.zoomInWeekTimeline()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(!viewModel.canZoomInWeekTimeline)

            Button("缩小周视图") {
                viewModel.zoomOutWeekTimeline()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(!viewModel.canZoomOutWeekTimeline)

            Button("恢复标准大小") {
                viewModel.resetWeekTimelineZoom()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(viewModel.weekTimelineZoomLevel == .standard)
        }
    }
}
