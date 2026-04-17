import AppKit
import SwiftData
import SwiftUI

struct MenuBarPanelView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Query(sort: [SortDescriptor(\TaskItem.date), SortDescriptor(\TaskItem.createdAt)]) private var tasks: [TaskItem]
    @Environment(\.modelContext) private var modelContext
    @State private var quickAddText = ""

    private var todayTasks: [TaskItem] {
        tasks.filter { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("今天共有 \(todayTasks.count) 个任务")
                .font(.headline)
            Text("已完成 \(todayTasks.filter(\.isCompleted).count) 个")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("快速添加到今天", text: $quickAddText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task {
                            await viewModel.createTaskFromQuickInput(modelContext: modelContext, on: .now, text: quickAddText)
                            if viewModel.parserErrorMessage == nil { quickAddText = "" }
                        }
                    }
                Button("添加") {
                    Task {
                        await viewModel.createTaskFromQuickInput(modelContext: modelContext, on: .now, text: quickAddText)
                        if viewModel.parserErrorMessage == nil { quickAddText = "" }
                    }
                }
            }

            Button("打开主应用") {
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("查看今日任务") {
                viewModel.selectedSection = .dayList
                viewModel.goToToday()
            }

            Button("进入打卡页面") {
                viewModel.selectedSection = .habits
            }

            Divider()
            ForEach(todayTasks.prefix(5)) { task in
                HStack {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    Text(task.title)
                        .lineLimit(1)
                    Spacer()
                    Text(task.displayTimeText)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.openEdit(task: task)
                }
            }
        }
    }
}
