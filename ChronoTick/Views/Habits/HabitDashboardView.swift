import SwiftData
import SwiftUI

struct HabitDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Habit.createdAt)]) private var habits: [Habit]
    @StateObject private var viewModel = HabitDashboardViewModel()
    @State private var newHabitName = ""
    @State private var pendingDeletion: Habit?
    @State private var pendingRename: Habit?
    @State private var nameErrorMessage: String?

    private var habitIDs: [UUID] {
        habits.map(\.id)
    }

    private var displayHabits: [Habit] {
        habits.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return lhs.isBuiltIn && !rhs.isBuiltIn
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                createBar

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
                    ForEach(displayHabits) { habit in
                        HabitCardView(
                            habit: habit,
                            month: viewModel.month,
                            checkedDates: viewModel.checkedDates(for: habit.id),
                            stats: viewModel.stats(for: habit.id),
                            today: viewModel.today,
                            onToggle: { day in
                                viewModel.toggle(day: day, habit: habit, context: modelContext)
                            },
                            onRename: {
                                pendingRename = habit
                            },
                            onDelete: {
                                pendingDeletion = habit
                            }
                        )
                    }
                }
            }
            .padding()
        }
        .onAppear {
            viewModel.reload(habits: habits, context: modelContext)
        }
        .onChange(of: habitIDs) { _, _ in
            viewModel.reload(habits: habits, context: modelContext)
        }
        .onChange(of: viewModel.month) { _, _ in
            viewModel.clampMonthIfNeeded()
        }
        .sheet(item: $pendingDeletion) { habit in
            HabitDeletionSheet(habit: habit) {
                viewModel.delete(habit: habit, context: modelContext)
                viewModel.reload(habits: habits.filter { $0.id != habit.id }, context: modelContext)
                pendingDeletion = nil
            } onCancel: {
                pendingDeletion = nil
            }
        }
        .sheet(item: $pendingRename) { habit in
            HabitRenameSheet(habit: habit) { newName in
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                guard !SystemHabitService.isHabitNameDuplicate(trimmed, excludingHabitID: habit.id, in: modelContext) else {
                    nameErrorMessage = "打卡项目名称不能和其它项目重复。"
                    return
                }

                _ = SystemHabitService.rename(habit, to: trimmed, in: modelContext)
                pendingRename = nil
                viewModel.reload(habits: habits, context: modelContext)
            } onCancel: {
                pendingRename = nil
            }
        }
        .alert("名称不可用", isPresented: Binding(
            get: { nameErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    nameErrorMessage = nil
                }
            }
        ), actions: {
            Button("确定") {
                nameErrorMessage = nil
            }
        }, message: {
            Text(nameErrorMessage ?? "")
        })
    }

    private var header: some View {
        HStack {
            Text("打卡")
                .font(.largeTitle.bold())
            Spacer()
            Button {
                viewModel.goToPreviousMonth()
            } label: {
                Image(systemName: "chevron.left")
            }
            Text(viewModel.month.formatted(.dateTime.year().month(.wide)))
                .frame(minWidth: 120)
            Button {
                viewModel.goToNextMonth()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.canAdvanceMonth)
        }
    }

    private var createBar: some View {
        HStack {
            TextField("新增打卡项", text: $newHabitName)
                .textFieldStyle(.roundedBorder)
            Button("创建") {
                let trimmed = newHabitName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                guard !SystemHabitService.isHabitNameDuplicate(trimmed, excludingHabitID: nil, in: modelContext) else {
                    nameErrorMessage = "打卡项目名称不能和其它项目重复。"
                    return
                }
                modelContext.insert(Habit(name: trimmed, colorHex: "#5B8DEF"))
                try? modelContext.save()
                newHabitName = ""
                viewModel.reload(habits: habits, context: modelContext)
            }
        }
    }
}

private struct HabitCardView: View {
    let habit: Habit
    let month: Date
    let checkedDates: Set<Date>
    let stats: HabitStats
    let today: Date
    let onToggle: (Date) -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    private let calendar = Calendar.chronoTick

    private var monthGrid: [Date] {
        let monthInterval = calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month.startOfDay(in: calendar), duration: 30 * 24 * 3600)
        let monthStart = monthInterval.start
        let weekdayOffset = calendar.component(.weekday, from: monthStart) - calendar.firstWeekday
        let normalizedOffset = weekdayOffset < 0 ? weekdayOffset + 7 : weekdayOffset
        let gridStart = calendar.date(byAdding: .day, value: -normalizedOffset, to: monthStart) ?? monthStart
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(habit.name)
                    .font(.title3.bold())
                Spacer()
                Button(action: onRename) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("重命名打卡项")
                if !habit.isBuiltIn {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("删除打卡项")
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .help("这是内建打卡项，不能删除")
                }
            }

            HStack {
                statBlock("连续", "\(stats.streak) 天")
                statBlock("累计", "\(stats.totalCompleted) 天")
                statBlock("本月", "\(Int(stats.monthCompletionRate * 100))%")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { label in
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ForEach(monthGrid, id: \.self) { day in
                    let normalized = calendar.startOfDay(for: day)
                    DayCheckCell(
                        day: day,
                        isCurrentMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                        isChecked: checkedDates.contains(normalized),
                        isFuture: normalized > today
                    ) {
                        onToggle(day)
                    }
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func statBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HabitRenameSheet: View {
    let habit: Habit
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var draftName: String

    init(habit: Habit, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.habit = habit
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _draftName = State(initialValue: habit.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("重命名打卡项")
                .font(.title3.bold())

            if habit.isBuiltIn {
                Text("这是系统自带打卡项目，可以改名，但不能和其它打卡项目重名。")
                    .foregroundStyle(.secondary)
            } else {
                Text("请输入新的打卡项目名称。")
                    .foregroundStyle(.secondary)
            }

            TextField("打卡项目名称", text: $draftName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    onConfirm(draftName)
                }
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct HabitDeletionSheet: View {
    let habit: Habit
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var confirmationText = ""

    private let requiredText = "I comfirm to delete"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("删除打卡项")
                .font(.title3.bold())

            Text("你将删除“\(habit.name)”及其全部打卡记录。此操作不可恢复。")
                .foregroundStyle(.secondary)

            Text("请输入以下内容以确认删除：")
                .font(.subheadline)
            Text(requiredText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.08))
                )

            TextField("请输入确认文本", text: $confirmationText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("删除", role: .destructive, action: onConfirm)
                    .disabled(confirmationText != requiredText)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct DayCheckCell: View {
    let day: Date
    let isCurrentMonth: Bool
    let isChecked: Bool
    let isFuture: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            guard !isFuture else { return }
            action()
        }) {
            Text(day.formatted(.dateTime.day()))
                .font(.caption)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(backgroundColor)
                )
                .foregroundStyle(foregroundColor)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .opacity(isFuture ? 0.5 : 1)
    }

    private var backgroundColor: Color {
        if isFuture {
            return Color.secondary.opacity(0.05)
        }
        if isChecked {
            return Color.green.opacity(0.24)
        }
        return Color.secondary.opacity(isCurrentMonth ? 0.08 : 0.03)
    }

    private var foregroundColor: Color {
        if isFuture {
            return .secondary.opacity(0.7)
        }
        return isCurrentMonth ? .primary : .secondary
    }
}
