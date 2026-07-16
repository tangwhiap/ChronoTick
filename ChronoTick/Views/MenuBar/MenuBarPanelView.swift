import AppKit
import SwiftData
import SwiftUI

private enum MenuBarPanelTab: String, CaseIterable, Identifiable {
    case today
    case workRest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "今日任务"
        case .workRest: return "工作/休息"
        }
    }
}

struct MenuBarPanelView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var workRestController: WorkRestTimerController
    @Query(sort: [SortDescriptor(\TaskItem.date), SortDescriptor(\TaskItem.createdAt)]) private var tasks: [TaskItem]
    @Environment(\.modelContext) private var modelContext
    @State private var quickAddText = ""
    @State private var selectedTab: MenuBarPanelTab = .today

    private var todayTasks: [TaskItem] {
        tasks.filter { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("页面", selection: $selectedTab) {
                ForEach(MenuBarPanelTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch selectedTab {
            case .today:
                todayContent
            case .workRest:
                ScrollView {
                    WorkRestPanelView()
                        .environmentObject(workRestController)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 620)
            }
        }
        .onAppear {
            selectedTab = workRestController.presentationState.hasActiveTask ? .workRest : .today
        }
    }

    private var todayContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("今天共有 \(todayTasks.count) 个任务")
                .font(.headline)
            Text("已完成 \(todayTasks.filter(\.isCompleted).count) 个")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("快速添加到今天", text: $quickAddText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addQuickTask() }
                Button("添加") { addQuickTask() }
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

    private func addQuickTask() {
        Task {
            await viewModel.createTaskFromQuickInput(
                modelContext: modelContext,
                on: .now,
                text: quickAddText
            )
            if viewModel.parserErrorMessage == nil { quickAddText = "" }
        }
    }
}

private struct WorkRestPanelView: View {
    @EnvironmentObject private var controller: WorkRestTimerController

    var body: some View {
        switch controller.presentationState {
        case let .active(presentation):
            WorkRestActivePanelView(presentation: presentation)
                .environmentObject(controller)
                .id(presentation.task.id)
        case let .idle(presentation):
            WorkRestIdlePanelView(presentation: presentation)
        }
    }
}

private struct WorkRestActivePanelView: View {
    @EnvironmentObject private var controller: WorkRestTimerController
    let presentation: WorkRestActivePresentation

    @State private var workMinutesText: String
    @State private var restMinutesText: String
    @State private var delayMinutesText = ""

    init(presentation: WorkRestActivePresentation) {
        self.presentation = presentation
        _workMinutesText = State(initialValue: String(presentation.workMinutes))
        _restMinutesText = State(initialValue: String(presentation.restMinutes))
    }

    private var workMinutes: Int? {
        Self.validMinutes(from: workMinutesText)
    }

    private var restMinutes: Int? {
        Self.validMinutes(from: restMinutesText)
    }

    private var delayMinutes: Int? {
        Self.validMinutes(from: delayMinutesText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.task.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.timeRangeText(for: presentation.task))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.phase.title)
                    .font(.title3.bold())
                    .foregroundStyle(presentation.phase == .work ? Color.accentColor : .green)
                Text(presentation.countdownEndDate, style: .timer)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("\(countdownLabel) · \(Self.targetTimeText(presentation.countdownEndDate, relativeTo: presentation.now))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("当前任务时长")
                    .font(.subheadline.bold())
                HStack {
                    durationField("工作", text: $workMinutesText)
                    durationField("休息", text: $restMinutesText)
                }
                Button("应用并从工作开始") {
                    guard let workMinutes, let restMinutes else { return }
                    controller.applyDurations(
                        workMinutes: workMinutes,
                        restMinutes: restMinutes
                    )
                }
                .disabled(workMinutes == nil || restMinutes == nil)
            }

            Divider()

            Button(presentation.phase == .work ? "现在休息" : "现在工作") {
                controller.switchNow()
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 8) {
                TextField("XX", text: $delayMinutesText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 58)
                Text("分钟后")
                    .foregroundStyle(.secondary)
                Button(presentation.phase == .work ? "休息" : "工作") {
                    guard let delayMinutes else { return }
                    controller.switchAfter(minutes: delayMinutes)
                }
                .disabled(delayMinutes == nil)
            }

            if workMinutes == nil || restMinutes == nil || (!delayMinutesText.isEmpty && delayMinutes == nil) {
                Text("分钟数必须是 1–1440 的整数。")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var countdownLabel: String {
        switch presentation.countdownKind {
        case let .phaseTransition(nextPhase):
            return nextPhase == .rest ? "距离休息" : "距离工作"
        case .taskEnd:
            return "距离任务结束"
        }
    }

    private func durationField(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 5) {
            Text(title)
            TextField("分钟", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
            Text("分钟")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static func validMinutes(from text: String) -> Int? {
        guard let value = Int(text),
              WorkRestSettings.validMinuteRange.contains(value)
        else { return nil }
        return value
    }

    private static func timeRangeText(for task: WorkRestTaskSnapshot) -> String {
        if Calendar.current.isDate(task.startDate, inSameDayAs: task.endDate) {
            return "\(DateFormatter.displayTime.string(from: task.startDate))–\(DateFormatter.displayTime.string(from: task.endDate))"
        }
        return "\(task.startDate.formatted(date: .abbreviated, time: .shortened)) – \(task.endDate.formatted(date: .abbreviated, time: .shortened))"
    }

    private static func targetTimeText(_ date: Date, relativeTo now: Date) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return DateFormatter.displayTime.string(from: date)
        }
        return date.formatted(.dateTime.month().day().hour().minute())
    }
}

private struct WorkRestIdlePanelView: View {
    let presentation: WorkRestIdlePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let nextTask = presentation.nextTask {
                Text("下一项时间段任务")
                    .font(.headline)
                Text(nextTask.title)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(nextTask.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(nextTask.startDate, style: .timer)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("距离任务开始")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("没有即将开始的时间段任务", systemImage: "clock")
                    .font(.headline)
                Text("时间点任务和无时间任务不会进入工作/休息计时。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
