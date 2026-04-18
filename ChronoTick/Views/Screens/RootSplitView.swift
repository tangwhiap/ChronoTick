import SwiftData
import SwiftUI

/// `RootSplitView` is the composition root for the macOS app shell.
///
/// It wires together:
/// - the themed application backdrop
/// - the sidebar navigation tree
/// - the current detail screen
/// - the shared task editor overlay
///
/// Keeping this shell focused on composition, rather than business logic, makes it much easier to
/// add new sections later without touching lower-level view code.
struct RootSplitView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Query(sort: [SortDescriptor(\AppThemeSettings.createdAt)]) private var themeSettings: [AppThemeSettings]

    init() {}

    private var themeSettingsValue: AppThemeSettings? {
        themeSettings.first
    }

    var body: some View {
        ZStack {
            AppThemeBackdrop(themeSettings: themeSettingsValue)

            NavigationSplitView {
                SidebarView(themeSettings: themeSettingsValue)
                    .environmentObject(viewModel)
                    .navigationTitle("ChronoTick")
            } detail: {
                ZStack {
                    detailBackgroundColor
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        HeaderBar()
                        Divider()
                        content
                    }

                    if viewModel.editingDraft != nil {
                        editorOverlay
                    }
                }
                .alert("提示", isPresented: Binding(get: {
                    viewModel.parserErrorMessage != nil
                }, set: { newValue in
                    if !newValue { viewModel.parserErrorMessage = nil }
                })) {
                    Button("确定", role: .cancel) { viewModel.parserErrorMessage = nil }
                } message: {
                    Text(viewModel.parserErrorMessage ?? "")
                }
            }
        }
        .tint(themeAccentColor)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedSection ?? .week {
        case .week:
            WeekTimelineView()
        case .dayList:
            DayListView()
        case .projectLists:
            ProjectTaskListDetailContainerView()
        case .habits:
            HabitDashboardView()
        case .settings:
            SettingsView()
        }
    }

    private var editorOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.12))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.closeEditor()
                }

            TaskEditorSheet()
                .environmentObject(viewModel)
                .padding(32)
                .onTapGesture {
                    // Absorb taps inside the editor so only the backdrop dismisses.
                }
        }
        .transition(.opacity)
        .zIndex(1)
    }

    private var themeAccentColor: Color {
        themeSettingsValue?.themeColor ?? Color(nsColor: NSColor(themeHex: AppThemeSettings.defaultThemeHex) ?? .controlAccentColor)
    }

    private var detailBackgroundColor: Color {
        let base = Color(nsColor: .windowBackgroundColor)
        return themeSettingsValue?.backgroundImageURL == nil ? base : base.opacity(0.72)
    }
}

private struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var viewModel: AppViewModel
    @Query(sort: [SortDescriptor(\TaskItem.date), SortDescriptor(\TaskItem.createdAt)]) private var tasks: [TaskItem]
    @Query(sort: [SortDescriptor(\ProjectTaskList.createdAt)]) private var projectTaskLists: [ProjectTaskList]
    @State private var isDayListExpanded = true
    @State private var isProjectListsExpanded = true
    @State private var pendingDeleteDate: Date?
    @State private var pendingDeleteProjectTaskList: ProjectTaskList?
    @State private var isPresentingCreateProjectList = false
    let themeSettings: AppThemeSettings?

    private var recordedDates: [Date] {
        let calendar = Calendar.current
        let unique = Set(tasks.map { calendar.startOfDay(for: $0.date) })
        return unique.sorted()
    }

    private var completedDates: Set<Date> {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: tasks) { calendar.startOfDay(for: $0.date) }
        return Set(
            grouped.compactMap { date, dayTasks in
                guard !dayTasks.isEmpty, dayTasks.allSatisfy(\.isCompleted) else { return nil }
                return date
            }
        )
    }

    private var rowSelectionColor: Color {
        (themeSettings?.themeColor ?? .accentColor).opacity(0.18)
    }

    private var rowIdleColor: Color {
        Color.secondary.opacity(0.06)
    }

    private var sidebarBackgroundColor: Color {
        let base = themeSettings?.sidebarThemeColor ?? Color(nsColor: NSColor(themeHex: AppThemeSettings.defaultSidebarThemeHex) ?? .underPageBackgroundColor)
        return themeSettings?.backgroundImageURL == nil ? base.opacity(0.92) : base.opacity(0.72)
    }

    var body: some View {
        List {
            sectionButton(.week)

            Section {
                DisclosureGroup(isExpanded: $isDayListExpanded) {
                    if recordedDates.isEmpty {
                        Text("暂无记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(recordedDates, id: \.self) { date in
                            Button {
                                viewModel.selectedDate = date
                                viewModel.selectedSection = .dayList
                            } label: {
                                HStack {
                                    Text(Self.dayListFormatter.string(from: date))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .opacity(completedDates.contains(date) ? 1 : 0)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected(date: date) ? rowSelectionColor : rowIdleColor)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("删除列表", role: .destructive) {
                                    pendingDeleteDate = date
                                }
                            }
                        }
                    }
                } label: {
                    Label("每日清单", systemImage: AppViewModel.Section.dayList.systemImage)
                }
            }

            Section {
                DisclosureGroup(isExpanded: $isProjectListsExpanded) {
                    if projectTaskLists.isEmpty {
                        Text("暂无任务列表")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(projectTaskLists) { list in
                            Button {
                                viewModel.openProjectTaskList(list)
                            } label: {
                                Text(list.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected(projectTaskList: list) ? rowSelectionColor : rowIdleColor)
                                    )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("删除列表", role: .destructive) {
                                    pendingDeleteProjectTaskList = list
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label("任务列表", systemImage: AppViewModel.Section.projectLists.systemImage)
                        Spacer()
                        Button {
                            isPresentingCreateProjectList = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("新建任务列表")
                    }
                }
            }

            sectionButton(.habits)
            sectionButton(.settings)
        }
        .scrollContentBackground(.hidden)
        .background(sidebarBackgroundColor)
        .listStyle(.sidebar)
        .confirmationDialog(
            "删除该日列表？",
            isPresented: Binding(
                get: { pendingDeleteDate != nil },
                set: { isPresented in
                    if !isPresented { pendingDeleteDate = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let date = pendingDeleteDate else { return }
                if Calendar.current.isDate(viewModel.selectedDate, inSameDayAs: date),
                   viewModel.selectedSection == .dayList {
                    viewModel.selectedSection = .week
                    viewModel.goToToday()
                }
                viewModel.deleteTasks(on: date, from: tasks, modelContext: modelContext)
                pendingDeleteDate = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteDate = nil
            }
        } message: {
            if let pendingDeleteDate {
                Text("这会删除 \(Self.dayListFormatter.string(from: pendingDeleteDate)) 下的全部所属任务。")
            }
        }
        .confirmationDialog(
            "删除该任务列表？",
            isPresented: Binding(
                get: { pendingDeleteProjectTaskList != nil },
                set: { isPresented in
                    if !isPresented { pendingDeleteProjectTaskList = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let list = pendingDeleteProjectTaskList else { return }
                let deletingSelectedList = viewModel.selectedProjectTaskListID == list.id
                viewModel.deleteProjectTaskList(list, modelContext: modelContext)

                if deletingSelectedList {
                    let remainingList = projectTaskLists.first(where: { $0.id != list.id })
                    viewModel.selectedProjectTaskListID = remainingList?.id
                    viewModel.selectedSection = remainingList == nil ? .week : .projectLists
                }

                pendingDeleteProjectTaskList = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteProjectTaskList = nil
            }
        } message: {
            if let pendingDeleteProjectTaskList {
                Text("这会删除任务列表“\(pendingDeleteProjectTaskList.name)”及其中的全部任务。删除后这些任务的 deadline 也不会再显示在周视图中。")
            }
        }
        .sheet(isPresented: $isPresentingCreateProjectList) {
            CreateProjectTaskListSheet { name in
                viewModel.createProjectTaskList(named: name, modelContext: modelContext)
                isPresentingCreateProjectList = false
            } onCancel: {
                isPresentingCreateProjectList = false
            }
        }
    }

    @ViewBuilder
    private func sectionButton(_ section: AppViewModel.Section) -> some View {
        Button {
            viewModel.selectedSection = section
        } label: {
            Label(section.title, systemImage: section.systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            (viewModel.selectedSection == section ? rowSelectionColor : Color.clear)
        )
    }

    private func isSelected(date: Date) -> Bool {
        viewModel.selectedSection == .dayList && Calendar.current.isDate(viewModel.selectedDate, inSameDayAs: date)
    }

    private func isSelected(projectTaskList list: ProjectTaskList) -> Bool {
        viewModel.selectedSection == .projectLists && viewModel.selectedProjectTaskListID == list.id
    }

    private static let dayListFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd/yy"
        return formatter
    }()
}

private struct CreateProjectTaskListSheet: View {
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建任务列表")
                .font(.title3.bold())
            TextField("任务列表名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
                .onChange(of: name) { _, newValue in
                    guard newValue.last?.isWhitespace == true else { return }
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    name = trimmed
                    submit()
                }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("创建", action: submit)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onConfirm(trimmed)
    }
}

private struct HeaderBar: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private var weekRangeLabel: String {
        let calendar = Calendar.current
        let selected = viewModel.selectedDate.startOfDay()
        let weekday = calendar.component(.weekday, from: selected)
        let offset = weekday - calendar.firstWeekday
        let weekStart = calendar.date(byAdding: .day, value: -offset, to: selected) ?? selected
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(Self.weekRangeFormatter.string(from: weekStart)) -> \(Self.weekRangeFormatter.string(from: weekEnd))"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                DatePicker("选择日期", selection: $viewModel.selectedDate, displayedComponents: .date)
                    .labelsHidden()
                Button("回到今天") {
                    viewModel.goToToday()
                }
                Button("计划明天") {
                    viewModel.goToTomorrow()
                }
                Spacer(minLength: 16)
                HStack(spacing: 12) {
                    if viewModel.selectedSection == .week {
                        HStack(spacing: 10) {
                            Button {
                                viewModel.goToPreviousWeek()
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .buttonStyle(.bordered)

                            Text(weekRangeLabel)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .frame(width: 120)

                            Button {
                                viewModel.goToNextWeek()
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Button {
                        viewModel.openCreateTask()
                    } label: {
                        Label("新建任务", systemImage: "plus")
                    }
                }
            }
            QuickAddBar()
        }
        .padding()
    }

    private static let weekRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d"
        return formatter
    }()
}

private struct AppThemeBackdrop: View {
    let themeSettings: AppThemeSettings?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(nsColor: .windowBackgroundColor).mix(with: Color(nsColor: .underPageBackgroundColor), by: 0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if let imageURL = themeSettings?.backgroundImageURL,
                   let image = NSImage(contentsOf: imageURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(1)

                    Rectangle()
                        .fill(.white.opacity(0.12))
                }
            }
            .ignoresSafeArea()
        }
    }
}

private extension Color {
    func mix(with other: Color, by fraction: CGFloat) -> Color {
        let clamped = min(max(fraction, 0), 1)
        let source = NSColor(self).usingColorSpace(.deviceRGB) ?? .white
        let target = NSColor(other).usingColorSpace(.deviceRGB) ?? .white
        let inverse = 1 - clamped

        return Color(
            nsColor: NSColor(
                calibratedRed: source.redComponent * inverse + target.redComponent * clamped,
                green: source.greenComponent * inverse + target.greenComponent * clamped,
                blue: source.blueComponent * inverse + target.blueComponent * clamped,
                alpha: source.alphaComponent * inverse + target.alphaComponent * clamped
            )
        )
    }
}
