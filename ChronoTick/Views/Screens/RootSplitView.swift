import AppKit
import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
                    DetailThemeBackground(themeSettings: themeSettingsValue)
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

}

private struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var viewModel: AppViewModel
    @Query(sort: [SortDescriptor(\TaskItem.date), SortDescriptor(\TaskItem.createdAt)]) private var tasks: [TaskItem]
    @Query(sort: [SortDescriptor(\ProjectTaskList.createdAt)]) private var projectTaskLists: [ProjectTaskList]
    @Query(sort: [SortDescriptor(\ProjectTaskListFolder.createdAt)]) private var projectTaskListFolders: [ProjectTaskListFolder]

    @State private var isDayListExpanded = true
    @State private var isProjectListsExpanded = true
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var rootDropIsTargeted = false
    @State private var dropTargetedFolderID: UUID?
    @State private var pendingDeleteDate: Date?
    @State private var editingDayListEntry: SidebarDayListEntry?
    @State private var pendingDeleteProjectTaskList: ProjectTaskList?
    @State private var pendingDeleteProjectTaskListFolder: ProjectTaskListFolder?
    @State private var projectNodeNameRequest: ProjectNodeNameRequest?
    @State private var hierarchyErrorMessage: String?

    let themeSettings: AppThemeSettings?

    private var dayListEntries: [SidebarDayListEntry] {
        let calendar = Calendar.current
        var completionByDate: [Date: Bool] = [:]

        for task in tasks {
            let date = calendar.startOfDay(for: task.date)
            if let isCompleted = completionByDate[date] {
                completionByDate[date] = isCompleted && task.isCompleted
            } else {
                completionByDate[date] = task.isCompleted
            }
        }

        return completionByDate
            .map { SidebarDayListEntry(date: $0.key, isCompleted: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private var visibleProjectNodes: [VisibleProjectNode] {
        flattenedProjectNodes(onlyExpandedFolders: true)
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
                    if dayListEntries.isEmpty {
                        Text("暂无记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        SidebarDayListScroller(
                            entries: dayListEntries,
                            selectedDate: viewModel.selectedDate,
                            isDayListActive: viewModel.selectedSection == .dayList,
                            rowSelectionColor: rowSelectionColor,
                            rowIdleColor: rowIdleColor,
                            onSelect: { date in
                                viewModel.selectedDate = date
                                viewModel.selectedSection = .dayList
                            },
                            onEdit: { date in
                                editingDayListEntry = dayListEntries.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
                            },
                            onDelete: { date in
                                pendingDeleteDate = date
                            }
                        )
                    }
                } label: {
                    Label("每日清单", systemImage: AppViewModel.Section.dayList.systemImage)
                }
            }

            Section {
                DisclosureGroup(isExpanded: $isProjectListsExpanded) {
                    if projectTaskLists.isEmpty && projectTaskListFolders.isEmpty {
                        Text("暂无任务列表或文件夹")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(visibleProjectNodes) { visibleNode in
                            switch visibleNode.node {
                            case .list(let list):
                                projectListRow(list, depth: visibleNode.depth)
                            case .folder(let folder):
                                projectFolderRow(folder, depth: visibleNode.depth)
                            }
                        }
                    }
                } label: {
                    projectListsHeader
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
                set: { if !$0 { pendingDeleteDate = nil } }
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
            Button("取消", role: .cancel) { pendingDeleteDate = nil }
        } message: {
            if let pendingDeleteDate {
                Text("这会删除 \(Self.dayListFormatter.string(from: pendingDeleteDate)) 下的全部所属任务。")
            }
        }
        .confirmationDialog(
            "删除该任务列表？",
            isPresented: Binding(
                get: { pendingDeleteProjectTaskList != nil },
                set: { if !$0 { pendingDeleteProjectTaskList = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive, action: deletePendingProjectTaskList)
            Button("取消", role: .cancel) { pendingDeleteProjectTaskList = nil }
        } message: {
            if let list = pendingDeleteProjectTaskList {
                Text("这会删除任务列表“\(list.name)”及其中的全部任务。删除后这些任务的 deadline 也不会再显示在周视图中。")
            }
        }
        .confirmationDialog(
            "删除该文件夹？",
            isPresented: Binding(
                get: { pendingDeleteProjectTaskListFolder != nil },
                set: { if !$0 { pendingDeleteProjectTaskListFolder = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除文件夹及全部内容", role: .destructive, action: deletePendingProjectTaskListFolder)
            Button("取消", role: .cancel) { pendingDeleteProjectTaskListFolder = nil }
        } message: {
            if let folder = pendingDeleteProjectTaskListFolder {
                Text("这会删除文件夹“\(folder.name)”内的全部任务列表、子文件夹和任务，且无法撤销。")
            }
        }
        .sheet(item: $editingDayListEntry) { entry in
            EditDailyChecklistDateSheet(sourceDate: entry.date) { targetDate in
                do {
                    try viewModel.changeDailyChecklistDate(
                        from: entry.date,
                        to: targetDate,
                        modelContext: modelContext
                    )
                    editingDayListEntry = nil
                    return nil
                } catch {
                    return error.localizedDescription
                }
            } onCancel: {
                editingDayListEntry = nil
            }
        }
        .sheet(item: $projectNodeNameRequest) { request in
            ProjectNodeNameSheet(
                title: request.title,
                placeholder: request.placeholder,
                initialName: request.initialName,
                confirmTitle: request.confirmTitle,
                onConfirm: { name in submitProjectNodeNameRequest(request, name: name) },
                onCancel: { projectNodeNameRequest = nil }
            )
        }
        .alert(
            "无法完成操作",
            isPresented: Binding(
                get: { hierarchyErrorMessage != nil },
                set: { if !$0 { hierarchyErrorMessage = nil } }
            )
        ) {
            Button("确定", role: .cancel) { hierarchyErrorMessage = nil }
        } message: {
            Text(hierarchyErrorMessage ?? "")
        }
    }

    private var projectListsHeader: some View {
        HStack(spacing: 8) {
            Label("任务列表", systemImage: AppViewModel.Section.projectLists.systemImage)
            Spacer()
            Menu {
                Button("新建任务列表", systemImage: "checklist") {
                    projectNodeNameRequest = .create(kind: .list, parentFolder: nil)
                }
                Button("新建文件夹", systemImage: "folder.badge.plus") {
                    projectNodeNameRequest = .create(kind: .folder, parentFolder: nil)
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("新建任务列表或文件夹")
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(rootDropIsTargeted ? rowSelectionColor : Color.clear)
        )
        .dropDestination(for: ProjectSidebarDragItem.self) { items, _ in
            guard let item = items.first else { return false }
            return moveProjectNode(item, to: nil)
        } isTargeted: { isTargeted in
            rootDropIsTargeted = isTargeted
        }
    }

    private func projectListRow(_ list: ProjectTaskList, depth: Int) -> some View {
        Button {
            viewModel.openProjectTaskList(list)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "checklist")
                    .foregroundStyle(.secondary)
                Text(list.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .padding(.leading, CGFloat(depth) * 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected(projectTaskList: list) ? rowSelectionColor : rowIdleColor)
            )
        }
        .buttonStyle(.plain)
        .draggable(ProjectSidebarDragItem(kind: .list, id: list.id))
        .contextMenu {
            Button("重命名") {
                projectNodeNameRequest = .rename(.list(list))
            }
            Button("删除列表", role: .destructive) {
                pendingDeleteProjectTaskList = list
            }
        }
    }

    private func projectFolderRow(_ folder: ProjectTaskListFolder, depth: Int) -> some View {
        Button {
            toggleFolder(folder)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: expandedFolderIDs.contains(folder.id) ? "chevron.down" : "chevron.right")
                    .font(.caption.bold())
                    .frame(width: 10)
                Image(systemName: expandedFolderIDs.contains(folder.id) ? "folder.fill" : "folder")
                    .foregroundStyle(.secondary)
                Text(folder.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .padding(.leading, CGFloat(depth) * 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(dropTargetedFolderID == folder.id ? rowSelectionColor : rowIdleColor)
            )
        }
        .buttonStyle(.plain)
        .draggable(ProjectSidebarDragItem(kind: .folder, id: folder.id))
        .dropDestination(for: ProjectSidebarDragItem.self) { items, _ in
            guard let item = items.first else { return false }
            return moveProjectNode(item, to: folder)
        } isTargeted: { isTargeted in
            if isTargeted {
                dropTargetedFolderID = folder.id
            } else if dropTargetedFolderID == folder.id {
                dropTargetedFolderID = nil
            }
        }
        .contextMenu {
            Button("新建任务列表", systemImage: "checklist") {
                projectNodeNameRequest = .create(kind: .list, parentFolder: folder)
            }
            Button("新建文件夹", systemImage: "folder.badge.plus") {
                projectNodeNameRequest = .create(kind: .folder, parentFolder: folder)
            }
            .disabled(folder.hierarchyDepth >= ProjectListHierarchyPolicy.maximumFolderDepth)
            Divider()
            Button("重命名") {
                projectNodeNameRequest = .rename(.folder(folder))
            }
            Button("删除文件夹", role: .destructive) {
                pendingDeleteProjectTaskListFolder = folder
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
        .listRowBackground(viewModel.selectedSection == section ? rowSelectionColor : Color.clear)
    }

    private func toggleFolder(_ folder: ProjectTaskListFolder) {
        if expandedFolderIDs.contains(folder.id) {
            expandedFolderIDs.remove(folder.id)
        } else {
            expandedFolderIDs.insert(folder.id)
        }
    }

    private func moveProjectNode(
        _ item: ProjectSidebarDragItem,
        to parentFolder: ProjectTaskListFolder?
    ) -> Bool {
        do {
            switch item.kind {
            case .list:
                guard let list = projectTaskLists.first(where: { $0.id == item.id }) else {
                    hierarchyErrorMessage = "拖动的任务列表已不存在。"
                    return false
                }
                try viewModel.moveProjectTaskList(list, to: parentFolder, modelContext: modelContext)
            case .folder:
                guard let folder = projectTaskListFolders.first(where: { $0.id == item.id }) else {
                    hierarchyErrorMessage = "拖动的文件夹已不存在。"
                    return false
                }
                try viewModel.moveProjectTaskListFolder(folder, to: parentFolder, modelContext: modelContext)
            }

            if let parentFolder {
                expandedFolderIDs.insert(parentFolder.id)
            }
            isProjectListsExpanded = true
            return true
        } catch {
            hierarchyErrorMessage = error.localizedDescription
            return false
        }
    }

    private func submitProjectNodeNameRequest(_ request: ProjectNodeNameRequest, name: String) -> String? {
        do {
            switch request.purpose {
            case .create(let kind, let parentFolder):
                switch kind {
                case .list:
                    try viewModel.createProjectTaskList(named: name, in: parentFolder, modelContext: modelContext)
                case .folder:
                    try viewModel.createProjectTaskListFolder(named: name, in: parentFolder, modelContext: modelContext)
                }
                if let parentFolder {
                    expandedFolderIDs.insert(parentFolder.id)
                }
                isProjectListsExpanded = true
            case .rename(let node):
                switch node {
                case .list(let list):
                    try viewModel.renameProjectTaskList(list, to: name, modelContext: modelContext)
                case .folder(let folder):
                    try viewModel.renameProjectTaskListFolder(folder, to: name, modelContext: modelContext)
                }
            }

            projectNodeNameRequest = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func deletePendingProjectTaskList() {
        guard let list = pendingDeleteProjectTaskList else { return }
        let deletedIDs: Set<UUID> = [list.id]
        let fallback = orderedProjectTaskLists(excluding: deletedIDs).first

        do {
            try viewModel.deleteProjectTaskList(list, modelContext: modelContext)
            updateSelectionAfterDeletingLists(deletedIDs, fallback: fallback)
        } catch {
            hierarchyErrorMessage = error.localizedDescription
        }
        pendingDeleteProjectTaskList = nil
    }

    private func deletePendingProjectTaskListFolder() {
        guard let folder = pendingDeleteProjectTaskListFolder else { return }
        let deletedIDs = Set(projectTaskLists.filter { isList($0, inside: folder) }.map(\.id))
        let fallback = orderedProjectTaskLists(excluding: deletedIDs).first

        do {
            try viewModel.deleteProjectTaskListFolder(folder, modelContext: modelContext)
            expandedFolderIDs.subtract(folderAndDescendantIDs(folder))
            updateSelectionAfterDeletingLists(deletedIDs, fallback: fallback)
        } catch {
            hierarchyErrorMessage = error.localizedDescription
        }
        pendingDeleteProjectTaskListFolder = nil
    }

    private func updateSelectionAfterDeletingLists(_ deletedIDs: Set<UUID>, fallback: ProjectTaskList?) {
        viewModel.reconcileProjectTaskListSelection(afterDeleting: deletedIDs, fallback: fallback)
    }

    private func orderedProjectTaskLists(excluding excludedIDs: Set<UUID>) -> [ProjectTaskList] {
        flattenedProjectNodes(onlyExpandedFolders: false).compactMap { visibleNode in
            guard case .list(let list) = visibleNode.node, !excludedIDs.contains(list.id) else { return nil }
            return list
        }
    }

    private func flattenedProjectNodes(onlyExpandedFolders: Bool) -> [VisibleProjectNode] {
        var result: [VisibleProjectNode] = []
        var visitedFolderIDs: Set<UUID> = []
        appendProjectNodes(
            parentFolderID: nil,
            depth: 0,
            onlyExpandedFolders: onlyExpandedFolders,
            visitedFolderIDs: &visitedFolderIDs,
            result: &result
        )
        return result
    }

    private func appendProjectNodes(
        parentFolderID: UUID?,
        depth: Int,
        onlyExpandedFolders: Bool,
        visitedFolderIDs: inout Set<UUID>,
        result: inout [VisibleProjectNode]
    ) {
        let lists = projectTaskLists
            .filter { $0.parentFolder?.id == parentFolderID }
            .map(ProjectSidebarNode.list)
        let folders = projectTaskListFolders
            .filter { $0.parentFolder?.id == parentFolderID }
            .map(ProjectSidebarNode.folder)
        let siblings = (lists + folders).sorted(by: ProjectSidebarNode.stableOrder)

        for node in siblings {
            result.append(VisibleProjectNode(node: node, depth: depth))
            guard case .folder(let folder) = node,
                  visitedFolderIDs.insert(folder.id).inserted,
                  !onlyExpandedFolders || expandedFolderIDs.contains(folder.id)
            else { continue }

            appendProjectNodes(
                parentFolderID: folder.id,
                depth: depth + 1,
                onlyExpandedFolders: onlyExpandedFolders,
                visitedFolderIDs: &visitedFolderIDs,
                result: &result
            )
        }
    }

    private func isList(_ list: ProjectTaskList, inside folder: ProjectTaskListFolder) -> Bool {
        var visited: Set<UUID> = []
        var ancestor = list.parentFolder
        while let current = ancestor, visited.insert(current.id).inserted {
            if current.id == folder.id { return true }
            ancestor = current.parentFolder
        }
        return false
    }

    private func folderAndDescendantIDs(_ folder: ProjectTaskListFolder) -> Set<UUID> {
        var result: Set<UUID> = []
        var pending = [folder]
        while let current = pending.popLast(), result.insert(current.id).inserted {
            pending.append(contentsOf: current.childFolders)
        }
        return result
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

private enum ProjectNodeKind {
    case list
    case folder
}

private enum ProjectSidebarNodeReference {
    case list(ProjectTaskList)
    case folder(ProjectTaskListFolder)
}

private struct ProjectNodeNameRequest: Identifiable {
    enum Purpose {
        case create(ProjectNodeKind, parentFolder: ProjectTaskListFolder?)
        case rename(ProjectSidebarNodeReference)
    }

    let id = UUID()
    let purpose: Purpose

    static func create(kind: ProjectNodeKind, parentFolder: ProjectTaskListFolder?) -> Self {
        Self(purpose: .create(kind, parentFolder: parentFolder))
    }

    static func rename(_ node: ProjectSidebarNodeReference) -> Self {
        Self(purpose: .rename(node))
    }

    var title: String {
        switch purpose {
        case .create(.list, _): return "新建任务列表"
        case .create(.folder, _): return "新建文件夹"
        case .rename(.list): return "重命名任务列表"
        case .rename(.folder): return "重命名文件夹"
        }
    }

    var placeholder: String {
        switch purpose {
        case .create(.list, _), .rename(.list): return "任务列表名称"
        case .create(.folder, _), .rename(.folder): return "文件夹名称"
        }
    }

    var initialName: String {
        switch purpose {
        case .create: return ""
        case .rename(.list(let list)): return list.name
        case .rename(.folder(let folder)): return folder.name
        }
    }

    var confirmTitle: String {
        switch purpose {
        case .create: return "创建"
        case .rename: return "保存"
        }
    }
}

private enum ProjectSidebarNode {
    case list(ProjectTaskList)
    case folder(ProjectTaskListFolder)

    var stableID: String {
        switch self {
        case .list(let list): return "list-\(list.id.uuidString)"
        case .folder(let folder): return "folder-\(folder.id.uuidString)"
        }
    }

    var createdAt: Date {
        switch self {
        case .list(let list): return list.createdAt
        case .folder(let folder): return folder.createdAt
        }
    }

    static func stableOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.stableID < rhs.stableID
    }
}

private struct VisibleProjectNode: Identifiable {
    let node: ProjectSidebarNode
    let depth: Int
    var id: String { node.stableID }
}

private struct ProjectSidebarDragItem: Codable, Transferable {
    enum Kind: String, Codable {
        case list
        case folder
    }

    let kind: Kind
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .chronoTickProjectSidebarItem)
    }
}

private extension UTType {
    static let chronoTickProjectSidebarItem = UTType(exportedAs: "com.example.chronotick.project-sidebar-item")
}

private struct SidebarDayListEntry: Identifiable, Equatable {
    let date: Date
    let isCompleted: Bool

    var id: Date { date }
}

private struct SidebarDayListScroller: View {
    let entries: [SidebarDayListEntry]
    let selectedDate: Date
    let isDayListActive: Bool
    let rowSelectionColor: Color
    let rowIdleColor: Color
    let onSelect: (Date) -> Void
    let onEdit: (Date) -> Void
    let onDelete: (Date) -> Void

    private static let visibleRowLimit = 15
    private static let rowHeight: CGFloat = 30
    private static let rowSpacing: CGFloat = 4
    private static let dayListFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd/yy"
        return formatter
    }()

    private var showsScroller: Bool {
        entries.count > Self.visibleRowLimit
    }

    private var viewportHeight: CGFloat {
        let visibleRows = min(entries.count, Self.visibleRowLimit)
        guard visibleRows > 0 else { return 0 }
        return CGFloat(visibleRows) * Self.rowHeight + CGFloat(visibleRows - 1) * Self.rowSpacing
    }

    private var selectedEntryID: SidebarDayListEntry.ID? {
        guard isDayListActive else { return nil }
        return entries.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: showsScroller) {
                LazyVStack(spacing: Self.rowSpacing) {
                    ForEach(entries) { entry in
                        SidebarDayListRow(
                            title: Self.dayListFormatter.string(from: entry.date),
                            isCompleted: entry.isCompleted,
                            isSelected: isDayListActive && Calendar.current.isDate(selectedDate, inSameDayAs: entry.date),
                            rowSelectionColor: rowSelectionColor,
                            rowIdleColor: rowIdleColor,
                            rowHeight: Self.rowHeight,
                            onSelect: { onSelect(entry.date) },
                            onEdit: { onEdit(entry.date) },
                            onDelete: { onDelete(entry.date) }
                        )
                        .id(entry.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, showsScroller ? 4 : 0)
            }
            .frame(height: viewportHeight)
            .onAppear {
                scrollToSelectedEntry(using: proxy)
            }
            .onChange(of: selectedDate) { _, _ in
                scrollToSelectedEntry(using: proxy)
            }
            .onChange(of: entries) { _, _ in
                scrollToSelectedEntry(using: proxy)
            }
        }
    }

    private func scrollToSelectedEntry(using proxy: ScrollViewProxy) {
        guard let selectedEntryID else { return }
        proxy.scrollTo(selectedEntryID, anchor: .center)
    }
}

private struct SidebarDayListRow: View {
    let title: String
    let isCompleted: Bool
    let isSelected: Bool
    let rowSelectionColor: Color
    let rowIdleColor: Color
    let rowHeight: CGFloat
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .opacity(isCompleted ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? rowSelectionColor : rowIdleColor)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .overlay {
            SidebarDayListContextMenuOverlay(
                onOpen: onSelect,
                onEdit: onEdit,
                onDelete: onDelete
            )
        }
    }
}

private struct SidebarDayListContextMenuOverlay: NSViewRepresentable {
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpen: onOpen, onEdit: onEdit, onDelete: onDelete)
    }

    func makeNSView(context: Context) -> ContextMenuView {
        let view = ContextMenuView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ContextMenuView, context: Context) {
        context.coordinator.onOpen = onOpen
        context.coordinator.onEdit = onEdit
        context.coordinator.onDelete = onDelete
        nsView.coordinator = context.coordinator
    }

    final class Coordinator: NSObject {
        var onOpen: () -> Void
        var onEdit: () -> Void
        var onDelete: () -> Void

        init(onOpen: @escaping () -> Void, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
            self.onOpen = onOpen
            self.onEdit = onEdit
            self.onDelete = onDelete
        }

        func showMenu(for event: NSEvent, in view: NSView) {
            onOpen()

            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "编辑所属日期", action: #selector(edit), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "删除列表", action: #selector(deleteList), keyEquivalent: ""))

            for item in menu.items {
                item.target = self
            }

            NSMenu.popUpContextMenu(menu, with: event, for: view)
        }

        @objc private func edit() {
            onEdit()
        }

        @objc private func deleteList() {
            onDelete()
        }
    }

    final class ContextMenuView: NSView {
        weak var coordinator: Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = window?.currentEvent ?? NSApp.currentEvent else { return nil }
            if event.type == .rightMouseDown ||
                (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
                return self
            }
            return nil
        }

        override func rightMouseDown(with event: NSEvent) {
            coordinator?.showMenu(for: event, in: self)
        }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                coordinator?.showMenu(for: event, in: self)
            } else {
                super.mouseDown(with: event)
            }
        }
    }
}

private struct EditDailyChecklistDateSheet: View {
    let sourceDate: Date
    let onConfirm: (Date) -> String?
    let onCancel: () -> Void

    @State private var targetDate: Date
    @State private var message: String?

    init(
        sourceDate: Date,
        onConfirm: @escaping (Date) -> String?,
        onCancel: @escaping () -> Void
    ) {
        self.sourceDate = sourceDate
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _targetDate = State(initialValue: Calendar.current.startOfDay(for: sourceDate))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑所属日期")
                .font(.title2.bold())
            DatePicker("所属日期", selection: $targetDate, displayedComponents: .date)
            HStack(spacing: 8) {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    message = onConfirm(targetDate)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
        .alert("提示", isPresented: Binding(
            get: { message != nil },
            set: { isPresented in
                if !isPresented { message = nil }
            }
        )) {
            Button("确定", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
}

private struct ProjectNodeNameSheet: View {
    let title: String
    let placeholder: String
    let confirmTitle: String
    let onConfirm: (String) -> String?
    let onCancel: () -> Void

    @State private var name: String
    @State private var validationMessage: String?

    init(
        title: String,
        placeholder: String,
        initialName: String,
        confirmTitle: String,
        onConfirm: @escaping (String) -> String?,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.bold())
            TextField(placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button(confirmTitle, action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmedName.isEmpty else { return }
        validationMessage = onConfirm(trimmedName)
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
                    // Draw the photo across the whole app shell instead of estimating the
                    // NavigationSplitView sidebar width. The sidebar paints its own themed surface
                    // above this layer, and avoiding a guessed spacer prevents the visible seam that
                    // appeared between the sidebar and the detail background on some window sizes.
                    FocalCroppedImage(
                        image: image,
                        cropX: themeSettings?.normalizedBackgroundCropX ?? AppThemeSettings.defaultBackgroundCropX,
                        cropY: themeSettings?.normalizedBackgroundCropY ?? AppThemeSettings.defaultBackgroundCropY,
                        cropZoom: themeSettings?.normalizedBackgroundCropZoom ?? AppThemeSettings.defaultBackgroundCropZoom
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(1)

                    Rectangle()
                        .fill(.white.opacity(AppThemeSettings.defaultBackgroundFogOpacity))
                }
            }
            .ignoresSafeArea()
        }
    }
}

private struct DetailThemeBackground: View {
    let themeSettings: AppThemeSettings?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                if let themeSettings,
                   let imageURL = themeSettings.backgroundImageURL,
                   let image = NSImage(contentsOf: imageURL) {
                    let rendering = themeSettings.backgroundFogRendering

                    FocalCroppedImage(
                        image: image,
                        cropX: themeSettings.normalizedBackgroundCropX,
                        cropY: themeSettings.normalizedBackgroundCropY,
                        cropZoom: themeSettings.normalizedBackgroundCropZoom
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)

                    Rectangle()
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(rendering.detailSurfaceOpacity))

                    Rectangle()
                        .fill(.white.opacity(rendering.detailMistOpacity))
                }
            }
            .clipped()
        }
    }
}

struct FocalCroppedImage: View {
    let image: NSImage
    let cropX: Double
    let cropY: Double
    var cropZoom: Double = AppThemeSettings.defaultBackgroundCropZoom

    var body: some View {
        GeometryReader { geometry in
            let imageSize = image.size
            let containerSize = geometry.size
            let zoom = cropZoom.clamped(to: AppThemeSettings.minimumBackgroundCropZoom...AppThemeSettings.maximumBackgroundCropZoom)
            let scale = max(
                containerSize.width / max(imageSize.width, 1),
                containerSize.height / max(imageSize.height, 1)
            ) * zoom
            let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let overflowX = max(0, fittedSize.width - containerSize.width)
            let overflowY = max(0, fittedSize.height - containerSize.height)

            Image(nsImage: image)
                .resizable()
                .frame(width: fittedSize.width, height: fittedSize.height)
                .offset(
                    x: -overflowX * CGFloat(cropX.clamped(to: 0...1)),
                    y: -overflowY * CGFloat(cropY.clamped(to: 0...1))
                )
                .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
                .clipped()
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
