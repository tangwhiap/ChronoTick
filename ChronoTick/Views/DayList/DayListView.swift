import SwiftData
import SwiftUI

/// `DayListView` renders the task list for the currently selected owning date.
///
/// The view intentionally keeps business logic thin. Sorting, editing, and completion behavior are
/// routed through `AppViewModel` and `TaskMutationCoordinator` so that list interactions stay
/// consistent with the week timeline, quick add, and editor sheet.
struct DayListView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\TaskItem.date), SortDescriptor(\TaskItem.startDateTime), SortDescriptor(\TaskItem.createdAt)]) private var tasks: [TaskItem]
    @State private var showCompleted = true

    private var dayTasks: [TaskItem] {
        tasks.filter { Calendar.current.isDate($0.date, inSameDayAs: viewModel.selectedDate) }
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                let lhsSortDate = lhs.startDateTime ?? lhs.endDateTime ?? lhs.createdAt
                let rhsSortDate = rhs.startDateTime ?? rhs.endDateTime ?? rhs.createdAt
                if lhsSortDate != rhsSortDate { return lhsSortDate < rhsSortDate }
                return lhs.createdAt < rhs.createdAt
            }
    }

    var body: some View {
        List {
            Section("待完成") {
                ForEach(dayTasks.filter { !$0.isCompleted }) { task in
                    row(task)
                }
            }

            Section {
                DisclosureGroup(isExpanded: $showCompleted) {
                    ForEach(dayTasks.filter(\.isCompleted)) { task in
                        row(task)
                    }
                } label: {
                    Text("已完成")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle(DateFormatter.displayMonthDay.string(from: viewModel.selectedDate))
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(spacing: 12) {
            Button {
                viewModel.toggleCompletion(for: task, modelContext: modelContext)
            } label: {
                CompletionToggleBox(isCompleted: task.isCompleted)
            }
            .buttonStyle(.borderless)

            Button {
                viewModel.openEdit(task: task)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                        Text(task.displayTimeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if task.reminderEnabled {
                        Label("提醒", systemImage: "bell")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button("编辑") { viewModel.openEdit(task: task) }
            Button("删除", role: .destructive) { viewModel.delete(task: task, modelContext: modelContext) }
        }
    }
}

private struct CompletionToggleBox: View {
    let isCompleted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isCompleted ? Color.accentColor : Color.clear)
            .stroke(isCompleted ? Color.accentColor : Color.secondary.opacity(0.55), lineWidth: 1.5)
            .frame(width: 24, height: 24)
            .overlay {
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(4)
            .contentShape(Rectangle())
    }
}

struct ProjectTaskListDetailContainerView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Query(sort: [SortDescriptor(\ProjectTaskList.createdAt)]) private var projectTaskLists: [ProjectTaskList]

    private var selectedList: ProjectTaskList? {
        guard let selectedID = viewModel.selectedProjectTaskListID else { return projectTaskLists.first }
        return projectTaskLists.first(where: { $0.id == selectedID }) ?? projectTaskLists.first
    }

    var body: some View {
        Group {
            if let selectedList {
                ProjectTaskListDetailView(list: selectedList)
            } else {
                ContentUnavailableView(
                    "暂无任务列表",
                    systemImage: "checklist",
                    description: Text("请先在左侧任务列表中点击 + 创建一个新的任务列表。")
                )
            }
        }
        .onAppear {
            if viewModel.selectedProjectTaskListID == nil {
                viewModel.selectedProjectTaskListID = projectTaskLists.first?.id
            }
        }
    }
}

private struct ProjectTaskListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var list: ProjectTaskList

    @State private var showCompleted = true
    @State private var newTaskTitle = ""
    @State private var editingTask: ProjectTask?
    @State private var draft = ProjectTaskEditorDraft()

    private var incompleteTasks: [ProjectTask] {
        list.tasks.filter { !$0.isCompleted }.sorted(by: projectTaskSort)
    }

    private var completedTasks: [ProjectTask] {
        list.tasks.filter(\.isCompleted).sorted(by: projectTaskSort)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(list.name)
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)

            HStack(spacing: 12) {
                TextField("新增列表任务", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                Button("添加任务", action: addTask)
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)

            List {
                Section("未完成") {
                    ForEach(incompleteTasks) { task in
                        projectTaskRow(task)
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $showCompleted) {
                        ForEach(completedTasks) { task in
                            projectTaskRow(task)
                        }
                    } label: {
                        Text("已完成")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .background(Color.clear)
        .sheet(item: $editingTask) { task in
            ProjectTaskEditorSheet(
                draft: ProjectTaskEditorDraft(task: task),
                onSave: { updatedDraft in
                    apply(updatedDraft, to: task)
                    editingTask = nil
                },
                onCancel: {
                    editingTask = nil
                }
            )
        }
    }

    private func addTask() {
        let trimmed = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            await TaskMutationCoordinator.createProjectTask(titled: trimmed, in: list, modelContext: modelContext)
            newTaskTitle = ""
        }
    }

    private func apply(_ draft: ProjectTaskEditorDraft, to task: ProjectTask) {
        Task {
            await TaskMutationCoordinator.saveProjectTask(
                task,
                draft: draft.coordinatorDraft,
                modelContext: modelContext
            )
        }
    }

    private func projectTaskSort(_ lhs: ProjectTask, _ rhs: ProjectTask) -> Bool {
        let lhsDeadline = lhs.effectiveDeadlineDate()
        let rhsDeadline = rhs.effectiveDeadlineDate()
        switch (lhsDeadline, rhsDeadline) {
        case let (lhs?, rhs?):
            if lhs != rhs { return lhs < rhs }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        return lhs.createdAt < rhs.createdAt
    }

    private func projectTaskRow(_ task: ProjectTask) -> some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await TaskMutationCoordinator.toggleProjectTaskCompletion(task, modelContext: modelContext)
                }
            } label: {
                CompletionToggleBox(isCompleted: task.isCompleted)
            }
            .buttonStyle(.borderless)

            Button {
                editingTask = task
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                        if task.deadlineDate != nil {
                            Text(task.displayDeadlineText)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Text("无截止时间")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button("编辑") { editingTask = task }
            Button(task.isCompleted ? "标记未完成" : "标记完成") {
                Task {
                    await TaskMutationCoordinator.toggleProjectTaskCompletion(task, modelContext: modelContext)
                }
            }
            Button("删除", role: .destructive) {
                TaskMutationCoordinator.deleteProjectTask(task, list: list, modelContext: modelContext)
            }
        }
    }
}

/// This lightweight draft object gives the editor sheet a simple, editable copy of the project task
/// state. The actual mutation is committed later through `TaskMutationCoordinator`.
private struct ProjectTaskEditorDraft {
    var title = ""
    var hasDeadline = false
    var deadlineIncludesTime = false
    var deadlineDate = Date()
    var notes = ""
    var isCompleted = false

    init() {}

    init(task: ProjectTask) {
        title = task.title
        hasDeadline = task.deadlineDate != nil
        deadlineIncludesTime = task.deadlineIncludesTime
        deadlineDate = task.deadlineDate ?? Date()
        notes = task.notes ?? ""
        isCompleted = task.isCompleted
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var coordinatorDraft: ProjectTaskDraft {
        ProjectTaskDraft(
            title: title,
            hasDeadline: hasDeadline,
            deadlineIncludesTime: deadlineIncludesTime,
            deadlineDate: deadlineDate,
            notes: notes,
            isCompleted: isCompleted
        )
    }
}

/// Editor for project-list tasks. Unlike daily checklist tasks, these tasks revolve around an
/// optional deadline rather than occupying a timeline slot by default.
private struct ProjectTaskEditorSheet: View {
    @State var draft: ProjectTaskEditorDraft
    let onSave: (ProjectTaskEditorDraft) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑列表任务")
                .font(.title3.bold())

            TextField("标题", text: $draft.title)
                .textFieldStyle(.roundedBorder)

            Toggle("设置截止时间", isOn: $draft.hasDeadline)
            if draft.hasDeadline {
                DatePicker("截止日期", selection: $draft.deadlineDate, displayedComponents: .date)
                Toggle("包含具体时间", isOn: $draft.deadlineIncludesTime)
                if draft.deadlineIncludesTime {
                    DatePicker("截止时间", selection: $draft.deadlineDate, displayedComponents: .hourAndMinute)
                }
            }

            Toggle("已完成", isOn: $draft.isCompleted)

            Text("备注")
                .font(.headline)
            TextEditor(text: $draft.notes)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    onSave(draft)
                }
                .disabled(draft.trimmedTitle.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
