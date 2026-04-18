import SwiftData
import SwiftUI

@main
struct ChronoTickApp: App {
    @StateObject private var viewModel = AppViewModel()
    private let container: ModelContainer

    init() {
        let schema = Schema([
            TaskItem.self,
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
        container = Self.makeContainer(schema: schema, configuration: configuration)
        Self.removeOrphanedProjectTasks(in: container.mainContext)
        _ = ReminderSettingsService.ensureProjectTaskPreferences(in: container.mainContext)
        _ = ThemeAssetService.ensureThemeSettings(in: container.mainContext)
        SystemHabitService.ensureBuiltInHabits(in: container.mainContext)
        try? SeedDataService.seedIfNeeded(in: container.mainContext)
        let existingTasks = (try? container.mainContext.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.date)]))) ?? []
        SystemHabitService.synchronizeDailyCompletionHabit(for: existingTasks.map(\.date), in: container.mainContext)
        let mainContext = container.mainContext
        Task { @MainActor in
            await NotificationScheduler.shared.ensureNotificationStateForAllTasks(in: mainContext)
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootSplitView()
                .environmentObject(viewModel)
                .modelContainer(container)
        }
        .defaultSize(width: 1340, height: 860)
        .commands {
            WeekTimelineZoomCommands(viewModel: viewModel)
        }

        MenuBarExtra("ChronoTick", systemImage: "clock.badge.checkmark") {
            MenuBarPanelView()
                .environmentObject(viewModel)
                .modelContainer(container)
                .frame(width: 320)
                .padding()
        }
        .menuBarExtraStyle(.window)
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
            purgeStoreArtifacts(at: configuration.url)
            return try! ModelContainer(for: schema, configurations: [configuration])
        }
    }

    static func purgeStoreArtifacts(at url: URL) {
        let fileManager = FileManager.default
        let candidates = [
            url,
            URL(fileURLWithPath: url.path + "-shm"),
            URL(fileURLWithPath: url.path + "-wal")
        ]
        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            try? fileManager.removeItem(at: candidate)
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
