import SwiftUI

/// `TaskEditorSheet` is the single editor for daily checklist tasks.
///
/// The sheet intentionally edits a `TaskDraft` instead of mutating `TaskItem` directly while the
/// user types. This gives us a clean validation boundary: the draft can hold transient UI state,
/// and only the validated result is committed back to persistence when the user saves.
struct TaskEditorSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let draft = Binding($viewModel.editingDraft) {
            VStack(alignment: .leading, spacing: 16) {
                Text(viewModel.editingTask == nil ? "新建任务" : "编辑任务")
                    .font(.title2.bold())
                TextField("标题", text: draft.title)
                VStack(alignment: .leading, spacing: 6) {
                    Text("所属清单")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(draft.wrappedValue.owningDate.formatted(date: .numeric, time: .omitted))
                        .font(.body.weight(.medium))
                }
                DatePicker("实际日期", selection: draft.actualDate, displayedComponents: .date)
                Toggle("有具体时间", isOn: draft.hasTime)
                if draft.wrappedValue.hasTime {
                    DatePicker("开始时间", selection: draft.startTime, displayedComponents: .hourAndMinute)
                    Toggle("结束时间", isOn: draft.useEndTime)
                    if draft.wrappedValue.useEndTime {
                        DatePicker("结束时间", selection: draft.endTime, displayedComponents: .hourAndMinute)
                    }
                    Toggle("开启提醒", isOn: draft.reminderEnabled)
                    if draft.wrappedValue.reminderEnabled {
                        Stepper(value: draft.reminderOffsetMinutes, in: 0...180, step: 5) {
                            Text(draft.wrappedValue.reminderOffsetMinutes == 0 ? "准时提醒" : "提前 \(draft.wrappedValue.reminderOffsetMinutes) 分钟提醒")
                        }
                    }
                }
                Toggle("已完成", isOn: draft.isCompleted)
                Text("备注")
                    .font(.headline)
                TextEditor(text: draft.notes)
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                HStack {
                    Spacer()
                    Button("取消") {
                        viewModel.closeEditor()
                    }
                    Button("保存") {
                        Task {
                            // `saveDraft` performs validation, persistence, notification rescheduling,
                            // and derived state synchronization in one place.
                            let success = await viewModel.saveDraft(modelContext: modelContext)
                            if !success {
                                viewModel.parserErrorMessage = "请检查标题和时间设置，结束时间不能早于开始时间。"
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 460)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 24, y: 14)
        }
    }
}

private extension Binding {
    /// Creates a non-optional binding only when the source optional currently has a value.
    /// This is useful for SwiftUI editor screens that should disappear when the draft is cleared.
    init?(_ source: Binding<Value?>) {
        guard source.wrappedValue != nil else { return nil }
        self = Binding(
            get: { source.wrappedValue! },
            set: { source.wrappedValue = $0 }
        )
    }
}
