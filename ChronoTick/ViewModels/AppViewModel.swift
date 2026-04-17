import Foundation
import SwiftData
import SwiftUI

/// `AppViewModel` owns cross-screen navigation state and delegates all data mutations
/// to a dedicated coordinator further below in this file.
///
/// Keeping view navigation and data side effects separated makes the app easier to reason about:
/// views ask the view model for actions, and the view model forwards those actions to a single
/// mutation pipeline that knows how to persist data, update notifications, and synchronize
/// derived features such as the built-in "complete daily tasks" habit.
@MainActor
final class AppViewModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case week
        case dayList
        case projectLists
        case habits
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: return "周视图"
            case .dayList: return "每日清单"
            case .projectLists: return "任务列表"
            case .habits: return "打卡"
            case .settings: return "设置"
            }
        }

        var systemImage: String {
            switch self {
            case .week: return "calendar"
            case .dayList: return "list.bullet.rectangle"
            case .projectLists: return "checklist"
            case .habits: return "checkmark.circle"
            case .settings: return "gearshape"
            }
        }
    }

    @Published var selectedSection: Section? = .week
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @Published var selectedProjectTaskListID: UUID?
    @Published var quickEntryText: String = ""
    @Published var editingDraft: TaskDraft?
    @Published var editingTask: TaskItem?
    @Published var parserErrorMessage: String?
    @Published var importMessage: String?

    /// We snap direct-manipulation edits in the week timeline to a fixed interval so dragging
    /// feels deterministic and tasks do not accumulate odd minute values over time.
    let snapMinutes = 5

    func goToToday() {
        selectedDate = Calendar.current.startOfDay(for: .now)
    }

    func goToTomorrow() {
        let today = Calendar.current.startOfDay(for: .now)
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
    }

    func openProjectTaskList(_ list: ProjectTaskList) {
        selectedProjectTaskListID = list.id
        selectedSection = .projectLists
    }

    func createProjectTaskList(named rawName: String, modelContext: ModelContext) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let list = ProjectTaskList(name: trimmed)
        modelContext.insert(list)
        try? modelContext.save()
        openProjectTaskList(list)
    }

    func deleteProjectTaskList(_ list: ProjectTaskList, modelContext: ModelContext) {
        TaskMutationCoordinator.deleteProjectTaskList(list, modelContext: modelContext)
    }

    func openCreateTask(on date: Date? = nil) {
        editingTask = nil
        editingDraft = TaskDraft(date: date ?? selectedDate)
    }

    func openEdit(task: TaskItem) {
        editingTask = task
        editingDraft = TaskDraft(task: task)
    }

    func closeEditor() {
        editingDraft = nil
        editingTask = nil
    }

    func createTaskFromQuickInput(modelContext: ModelContext, on date: Date? = nil, text: String? = nil) async {
        do {
            let targetDate = (date ?? selectedDate).startOfDay()
            let rawText = (text ?? quickEntryText)
            let parsed = try TaskTimeTextParser.parse(rawText, on: targetDate)
            _ = try await TaskMutationCoordinator.createTask(
                title: parsed.title,
                owningDate: targetDate,
                startDateTime: parsed.startDateTime,
                endDateTime: parsed.endDateTime,
                hasTime: parsed.hasTime,
                modelContext: modelContext
            )
            if text == nil {
                quickEntryText = ""
            }
        } catch {
            parserErrorMessage = error.localizedDescription
        }
    }

    func saveDraft(modelContext: ModelContext) async -> Bool {
        guard let editingDraft else { return false }
        guard let validated = editingDraft.validated() else { return false }

        do {
            _ = try await TaskMutationCoordinator.saveTaskDraft(
                validated,
                editingTask: editingTask,
                modelContext: modelContext
            )
            closeEditor()
            return true
        } catch {
            parserErrorMessage = error.localizedDescription
            return false
        }
    }

    func delete(task: TaskItem, modelContext: ModelContext) {
        TaskMutationCoordinator.deleteTask(task, modelContext: modelContext)
    }

    func deleteTasks(on owningDate: Date, from tasks: [TaskItem], modelContext: ModelContext) {
        TaskMutationCoordinator.deleteTasks(on: owningDate, from: tasks, modelContext: modelContext)
    }

    func toggleCompletion(for task: TaskItem, modelContext: ModelContext) {
        Task {
            await TaskMutationCoordinator.toggleTaskCompletion(task, modelContext: modelContext)
        }
    }

    func move(task: TaskItem, to date: Date, startMinute: Int, modelContext: ModelContext) async {
        await TaskMutationCoordinator.moveTask(
            task,
            to: date,
            startMinute: startMinute,
            snapMinutes: snapMinutes,
            modelContext: modelContext
        )
    }

    func resize(task: TaskItem, edge: ResizeEdge, targetMinute: Int, modelContext: ModelContext) async {
        await TaskMutationCoordinator.resizeTask(
            task,
            edge: edge,
            targetMinute: targetMinute,
            snapMinutes: snapMinutes,
            modelContext: modelContext
        )
    }

    private func snap(_ minutes: Int) -> Int {
        Int((Double(minutes) / Double(snapMinutes)).rounded()) * snapMinutes
    }

    private func applyTime(for task: TaskItem, on date: Date, startMinute: Int) {
        let clampedStart = max(0, min(24 * 60 - snapMinutes, snap(startMinute)))
        switch task.timingKind {
        case .point:
            task.startDateTime = date.setting(hour: clampedStart / 60, minute: clampedStart % 60)
            task.endDateTime = nil
        case .range:
            let duration = max(snapMinutes, minuteOfDay(for: task.endDateTime!) - minuteOfDay(for: task.startDateTime!))
            let maxStart = max(0, 24 * 60 - duration)
            let finalStart = min(clampedStart, maxStart)
            let finalEnd = finalStart + duration
            task.startDateTime = date.setting(hour: finalStart / 60, minute: finalStart % 60)
            let cappedEnd = min(finalEnd, 23 * 60 + 59)
            task.endDateTime = date.setting(hour: cappedEnd / 60, minute: cappedEnd % 60)
        case .untimed:
            task.startDateTime = nil
            task.endDateTime = nil
        }
    }

    func minuteOfDay(for date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}

/// `TaskMutationCoordinator` is the single place where task and project-task side effects live.
///
/// Before this refactor, notification updates, habit synchronization, persistence, and model edits
/// were spread across the app view model and multiple views. That worked for a while, but it also
/// made it easy to introduce subtle regressions because each new UI path had to remember the same
/// follow-up steps. Centralizing those steps here gives future maintainers one obvious place to
/// update when the mutation rules evolve.
@MainActor
enum TaskMutationCoordinator {
    static func createTask(
        title: String,
        owningDate: Date,
        startDateTime: Date?,
        endDateTime: Date?,
        hasTime: Bool,
        modelContext: ModelContext
    ) async throws -> TaskItem {
        let task = TaskItem(
            title: title,
            date: owningDate,
            startDateTime: startDateTime,
            endDateTime: endDateTime,
            hasTime: hasTime,
            reminderEnabled: false
        )
        modelContext.insert(task)
        try modelContext.save()
        synchronizeDailyCompletionHabit(for: [owningDate], in: modelContext)
        await NotificationScheduler.shared.ensureNotificationState(for: task, in: modelContext)
        return task
    }

    static func saveTaskDraft(
        _ draft: ValidatedTaskDraft,
        editingTask: TaskItem?,
        modelContext: ModelContext
    ) async throws -> TaskItem {
        let previousOwningDate = editingTask?.date
        let task = editingTask ?? TaskItem(title: draft.title, date: draft.date)

        task.title = draft.title
        task.date = Calendar.current.startOfDay(for: draft.date)
        task.hasTime = draft.hasTime
        task.startDateTime = draft.startDateTime
        task.endDateTime = draft.endDateTime
        task.reminderEnabled = draft.reminderEnabled && draft.startDateTime != nil
        task.reminderOffsetMinutes = draft.reminderOffsetMinutes
        task.notes = draft.notes
        task.isCompleted = draft.isCompleted
        task.touch()

        if editingTask == nil {
            modelContext.insert(task)
        }

        try modelContext.save()
        synchronizeDailyCompletionHabit(for: [previousOwningDate, task.date].compactMap { $0 }, in: modelContext)
        await NotificationScheduler.shared.ensureNotificationState(for: task, in: modelContext)
        return task
    }

    static func deleteTask(_ task: TaskItem, modelContext: ModelContext) {
        let owningDate = task.date
        NotificationScheduler.shared.removeNotification(for: task)
        modelContext.delete(task)
        try? modelContext.save()
        synchronizeDailyCompletionHabit(for: [owningDate], in: modelContext)
    }

    static func deleteTasks(on owningDate: Date, from tasks: [TaskItem], modelContext: ModelContext) {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: owningDate)

        for task in tasks where calendar.isDate(task.date, inSameDayAs: targetDay) {
            NotificationScheduler.shared.removeNotification(for: task)
            modelContext.delete(task)
        }

        try? modelContext.save()
        synchronizeDailyCompletionHabit(for: [targetDay], in: modelContext)
    }

    static func toggleTaskCompletion(_ task: TaskItem, modelContext: ModelContext) async {
        task.isCompleted.toggle()
        task.touch()
        try? modelContext.save()
        synchronizeDailyCompletionHabit(for: [task.date], in: modelContext)
        await NotificationScheduler.shared.ensureNotificationState(for: task, in: modelContext)
    }

    static func moveTask(
        _ task: TaskItem,
        to date: Date,
        startMinute: Int,
        snapMinutes: Int,
        modelContext: ModelContext
    ) async {
        let previousOwningDate = task.date
        let day = date.startOfDay()
        task.date = day
        applyTimelineTime(for: task, on: day, startMinute: startMinute, snapMinutes: snapMinutes)
        task.touch()
        try? modelContext.save()
        synchronizeDailyCompletionHabit(for: [previousOwningDate, day], in: modelContext)
        await NotificationScheduler.shared.ensureNotificationState(for: task, in: modelContext)
    }

    static func resizeTask(
        _ task: TaskItem,
        edge: ResizeEdge,
        targetMinute: Int,
        snapMinutes: Int,
        modelContext: ModelContext
    ) async {
        guard task.timingKind == .range,
              let start = task.startDateTime,
              let end = task.endDateTime
        else { return }

        let startMinutes = minuteOfDay(for: start)
        let endMinutes = minuteOfDay(for: end)

        switch edge {
        case .top:
            let clamped = min(max(0, snap(targetMinute, to: snapMinutes)), endMinutes - snapMinutes)
            task.startDateTime = task.date.setting(hour: clamped / 60, minute: clamped % 60)
        case .bottom:
            let clamped = max(startMinutes + snapMinutes, min(24 * 60, snap(targetMinute, to: snapMinutes)))
            let visibleEnd = min(clamped, 23 * 60 + 59)
            task.endDateTime = task.date.setting(hour: visibleEnd / 60, minute: visibleEnd % 60)
        }

        task.touch()
        try? modelContext.save()
        await NotificationScheduler.shared.ensureNotificationState(for: task, in: modelContext)
    }

    static func createProjectTask(
        titled rawTitle: String,
        in list: ProjectTaskList,
        modelContext: ModelContext
    ) async {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let task = ProjectTask(title: trimmed, list: list)
        modelContext.insert(task)
        list.touch()
        try? modelContext.save()
        await NotificationScheduler.shared.ensureNotificationState(for: task, in: modelContext)
    }

    static func saveProjectTask(
        _ task: ProjectTask,
        draft: ProjectTaskDraft,
        modelContext: ModelContext
    ) async {
        task.title = draft.trimmedTitle
        task.isCompleted = draft.isCompleted
        task.notes = normalizedOptionalText(draft.notes)
        task.deadlineIncludesTime = draft.hasDeadline && draft.deadlineIncludesTime

        if draft.hasDeadline {
            task.deadlineDate = draft.deadlineIncludesTime ? draft.deadlineDate : Calendar.current.startOfDay(for: draft.deadlineDate)
        } else {
            task.deadlineDate = nil
            task.deadlineIncludesTime = false
        }

        task.touch()
        try? modelContext.save()
        await NotificationScheduler.shared.ensureNotificationState(for: task, in: modelContext)
    }

    static func toggleProjectTaskCompletion(_ task: ProjectTask, modelContext: ModelContext) async {
        task.isCompleted.toggle()
        task.touch()
        try? modelContext.save()
        await NotificationScheduler.shared.ensureNotificationState(for: task, in: modelContext)
    }

    static func deleteProjectTask(_ task: ProjectTask, list: ProjectTaskList, modelContext: ModelContext) {
        NotificationScheduler.shared.removeNotification(for: task)
        modelContext.delete(task)
        list.touch()
        try? modelContext.save()
    }

    static func deleteProjectTaskList(_ list: ProjectTaskList, modelContext: ModelContext) {
        for task in list.tasks {
            NotificationScheduler.shared.removeNotification(for: task)
            modelContext.delete(task)
        }
        modelContext.delete(list)
        try? modelContext.save()
    }

    private static func synchronizeDailyCompletionHabit(for dates: [Date], in modelContext: ModelContext) {
        guard !dates.isEmpty else { return }
        SystemHabitService.synchronizeDailyCompletionHabit(for: dates, in: modelContext)
    }

    private static func snap(_ minutes: Int, to step: Int) -> Int {
        Int((Double(minutes) / Double(step)).rounded()) * step
    }

    private static func normalizedOptionalText(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func applyTimelineTime(for task: TaskItem, on date: Date, startMinute: Int, snapMinutes: Int) {
        let clampedStart = max(0, min(24 * 60 - snapMinutes, snap(startMinute, to: snapMinutes)))

        switch task.timingKind {
        case .point:
            task.startDateTime = date.setting(hour: clampedStart / 60, minute: clampedStart % 60)
            task.endDateTime = nil
        case .range:
            guard let start = task.startDateTime, let end = task.endDateTime else { return }
            let duration = max(snapMinutes, minuteOfDay(for: end) - minuteOfDay(for: start))
            let maxStart = max(0, 24 * 60 - duration)
            let finalStart = min(clampedStart, maxStart)
            let finalEnd = finalStart + duration
            task.startDateTime = date.setting(hour: finalStart / 60, minute: finalStart % 60)
            let cappedEnd = min(finalEnd, 23 * 60 + 59)
            task.endDateTime = date.setting(hour: cappedEnd / 60, minute: cappedEnd % 60)
        case .untimed:
            task.startDateTime = nil
            task.endDateTime = nil
        }
    }

    private static func minuteOfDay(for date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}

enum ResizeEdge {
    case top
    case bottom
}

/// `TaskDraft` is the editable form state for daily checklist tasks.
///
/// It is intentionally more UI-friendly than `TaskItem`. For example, it stores separate toggles
/// such as `useEndTime`, even though the persisted model only cares whether `endDateTime` exists.
/// This separation keeps the editor code simple while still allowing the persisted model to remain
/// normalized.
struct TaskDraft: Identifiable {
    let id = UUID()
    var title: String
    var date: Date
    var hasTime: Bool
    var startTime: Date
    var endTime: Date
    var useEndTime: Bool
    var reminderEnabled: Bool
    var reminderOffsetMinutes: Int
    var notes: String
    var isCompleted: Bool
    var validationMessage: String?

    init(date: Date) {
        let base = Calendar.current.startOfDay(for: date)
        self.title = ""
        self.date = base
        self.hasTime = false
        self.startTime = base.setting(hour: 9, minute: 0) ?? base
        self.endTime = base.setting(hour: 10, minute: 0) ?? base
        self.useEndTime = false
        self.reminderEnabled = false
        self.reminderOffsetMinutes = 0
        self.notes = ""
        self.isCompleted = false
    }

    init(task: TaskItem) {
        let base = Calendar.current.startOfDay(for: task.date)
        self.title = task.title
        self.date = task.date
        self.hasTime = task.hasTime
        self.startTime = task.startDateTime ?? (base.setting(hour: 9, minute: 0) ?? base)
        self.endTime = task.endDateTime ?? (base.setting(hour: 10, minute: 0) ?? base)
        self.useEndTime = task.endDateTime != nil
        self.reminderEnabled = task.reminderEnabled
        self.reminderOffsetMinutes = task.reminderOffsetMinutes
        self.notes = task.notes ?? ""
        self.isCompleted = task.isCompleted
    }

    /// Converts transient editor state into a normalized payload that can be saved safely.
    /// Returning `nil` means the draft is not currently valid.
    func validated() -> ValidatedTaskDraft? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        let day = Calendar.current.startOfDay(for: date)
        if hasTime {
            let startComponents = Calendar.current.dateComponents([.hour, .minute], from: startTime)
            guard let start = day.setting(hour: startComponents.hour ?? 0, minute: startComponents.minute ?? 0) else { return nil }
            var end: Date?
            if useEndTime {
                let endComponents = Calendar.current.dateComponents([.hour, .minute], from: endTime)
                end = day.setting(hour: endComponents.hour ?? 0, minute: endComponents.minute ?? 0)
                if let end, end < start { return nil }
            }
            return ValidatedTaskDraft(
                title: trimmedTitle,
                date: day,
                hasTime: true,
                startDateTime: start,
                endDateTime: end,
                reminderEnabled: reminderEnabled,
                reminderOffsetMinutes: reminderOffsetMinutes,
                notes: notes.isEmpty ? nil : notes,
                isCompleted: isCompleted
            )
        } else {
            return ValidatedTaskDraft(
                title: trimmedTitle,
                date: day,
                hasTime: false,
                startDateTime: nil,
                endDateTime: nil,
                reminderEnabled: false,
                reminderOffsetMinutes: 0,
                notes: notes.isEmpty ? nil : notes,
                isCompleted: isCompleted
            )
        }
    }
}

/// `ValidatedTaskDraft` is the persistence-ready representation produced by `TaskDraft.validated()`.
/// Once the app reaches this type, the view model can save it without needing to inspect UI flags.
struct ValidatedTaskDraft {
    let title: String
    let date: Date
    let hasTime: Bool
    let startDateTime: Date?
    let endDateTime: Date?
    let reminderEnabled: Bool
    let reminderOffsetMinutes: Int
    let notes: String?
    let isCompleted: Bool
}

/// `ProjectTaskDraft` is the persistence-facing form used by the coordinator for project tasks.
/// It intentionally lives outside the view layer so project-task editing can evolve without the
/// coordinator depending on a specific SwiftUI form type.
struct ProjectTaskDraft {
    let title: String
    let hasDeadline: Bool
    let deadlineIncludesTime: Bool
    let deadlineDate: Date
    let notes: String
    let isCompleted: Bool

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
