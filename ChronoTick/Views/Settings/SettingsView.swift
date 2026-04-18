import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

private enum SettingsImportKind: Identifiable {
    case tasks
    case habits

    var id: String { title }

    var title: String {
        switch self {
        case .tasks: return "任务"
        case .habits: return "打卡"
        }
    }
}

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: [SortDescriptor(\TaskItem.createdAt)]) private var tasks: [TaskItem]
    @Query(sort: [SortDescriptor(\ProjectTask.createdAt)]) private var projectTasks: [ProjectTask]
    @Query(sort: [SortDescriptor(\Habit.createdAt)]) private var habits: [Habit]
    @Query(sort: [SortDescriptor(\DailyTaskReminderRule.createdAt)]) private var dailyReminderRules: [DailyTaskReminderRule]
    @Query(sort: [SortDescriptor(\ProjectTaskReminderPreferences.createdAt)]) private var projectReminderPreferences: [ProjectTaskReminderPreferences]
    @Query(sort: [SortDescriptor(\AppThemeSettings.createdAt)]) private var themeSettings: [AppThemeSettings]
    @Query(sort: [SortDescriptor(\SavedThemePreset.createdAt)]) private var savedThemes: [SavedThemePreset]

    @State private var pendingReplaceImportKind: SettingsImportKind?
    @State private var importMode: CSVImportMode = .merge
    @State private var message: String?
    @State private var isPresentingAddDailyRule = false
    @State private var editingDailyRule: DailyTaskReminderRule?
    @State private var pendingDeleteDailyRule: DailyTaskReminderRule?
    @State private var isPresentingSaveTheme = false
    @State private var editingSavedTheme: SavedThemePreset?
    @State private var pendingDeleteSavedTheme: SavedThemePreset?
    @State private var authorizationStatusText = "读取中..."
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var projectReminderPreference: ProjectTaskReminderPreferences? {
        projectReminderPreferences.first
    }

    private var themePreference: AppThemeSettings? {
        themeSettings.first
    }

    private var authorizationButtonTitle: String {
        authorizationStatus == .denied ? "打开系统设置" : "检查并请求权限"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                themeCard
                reminderSettingsCard
                csvCard
                infoSection
                Spacer(minLength: 240)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            _ = ReminderSettingsService.ensureProjectTaskPreferences(in: modelContext)
            _ = ThemeAssetService.ensureThemeSettings(in: modelContext)
            Task { await refreshAuthorizationStatus() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await refreshAuthorizationStatus() }
        }
        .sheet(isPresented: $isPresentingAddDailyRule) {
            AddDailyReminderRuleSheet { titlePattern, rawRule in
                do {
                    try saveDailyReminderRule(titlePattern: titlePattern, rawRule: rawRule)
                    isPresentingAddDailyRule = false
                } catch {
                    message = error.localizedDescription
                }
            } onCancel: {
                isPresentingAddDailyRule = false
            }
        }
        .sheet(item: $editingDailyRule) { rule in
            EditDailyReminderRuleSheet(rule: rule) { titlePattern, rawRule in
                do {
                    try saveDailyReminderRule(titlePattern: titlePattern, rawRule: rawRule, editing: rule)
                    editingDailyRule = nil
                } catch {
                    message = error.localizedDescription
                }
            } onCancel: {
                editingDailyRule = nil
            }
        }
        .sheet(item: $pendingReplaceImportKind) { kind in
            ReplaceImportConfirmationSheet(kind: kind) {
                pendingReplaceImportKind = nil
                startImport(kind)
            } onCancel: {
                pendingReplaceImportKind = nil
            }
        }
        .sheet(isPresented: $isPresentingSaveTheme) {
            if let themePreference {
                SaveThemeSheet(themePreference: themePreference) { name in
                    do {
                        try ThemeAssetService.saveCurrentTheme(named: name, from: themePreference, in: modelContext)
                        isPresentingSaveTheme = false
                    } catch {
                        message = error.localizedDescription
                    }
                } onCancel: {
                    isPresentingSaveTheme = false
                }
            }
        }
        .sheet(item: $editingSavedTheme) { preset in
            EditSavedThemeSheet(theme: preset) { updatedName, updatedThemeHex, updatedSidebarHex, selectedImageURL, removeBackgroundImage in
                do {
                    try ThemeAssetService.updateSavedTheme(
                        preset,
                        name: updatedName,
                        themeHex: updatedThemeHex,
                        sidebarThemeHex: updatedSidebarHex,
                        selectedImageURL: selectedImageURL,
                        removeBackgroundImage: removeBackgroundImage,
                        in: modelContext
                    )
                    editingSavedTheme = nil
                } catch {
                    message = error.localizedDescription
                }
            } onCancel: {
                editingSavedTheme = nil
            }
        }
        .confirmationDialog(
            "删除提醒规则？",
            isPresented: Binding(
                get: { pendingDeleteDailyRule != nil },
                set: { isPresented in
                    if !isPresented { pendingDeleteDailyRule = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let rule = pendingDeleteDailyRule else { return }
                modelContext.delete(rule)
                try? modelContext.save()
                Task { await NotificationScheduler.shared.ensureNotificationStateForAllTasks(in: modelContext) }
                pendingDeleteDailyRule = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteDailyRule = nil
            }
        } message: {
            if let pendingDeleteDailyRule {
                Text("将删除规则“\(pendingDeleteDailyRule.titlePattern)”。删除后会立即重新计算所有每日清单任务的统一提醒。")
            }
        }
        .confirmationDialog(
            "删除保存的主题？",
            isPresented: Binding(
                get: { pendingDeleteSavedTheme != nil },
                set: { isPresented in
                    if !isPresented { pendingDeleteSavedTheme = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let pendingDeleteSavedTheme else { return }
                do {
                    try ThemeAssetService.deleteSavedTheme(pendingDeleteSavedTheme, in: modelContext)
                } catch {
                    message = error.localizedDescription
                }
                self.pendingDeleteSavedTheme = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteSavedTheme = nil
            }
        } message: {
            if let pendingDeleteSavedTheme {
                Text("将删除主题“\(pendingDeleteSavedTheme.name)”。这会清理 ChronoTick 自己保存的主题图片副本，但不会删除原始图片。")
            }
        }
        .alert("结果", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("主题设置")
                .font(.title3.bold())

            if let themePreference {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("自定义主题")
                            .font(.headline)

                        HStack(alignment: .top, spacing: 16) {
                            ThemePreviewSwatch(
                                title: "当前主题",
                                themeColor: themePreference.themeColor,
                                sidebarThemeColor: themePreference.sidebarThemeColor,
                                backgroundImageURL: themePreference.backgroundImageURL
                            )

                            VStack(alignment: .leading, spacing: 10) {
                                ThemeColorRow(
                                    title: "主题色1",
                                    description: "用于按钮、选中态和强调元素。",
                                    selection: Binding(
                                        get: { themePreference.themeColor },
                                        set: { newValue in
                                            themePreference.themeHex = NSColor(newValue).themeHexString
                                            themePreference.touch()
                                            try? modelContext.save()
                                        }
                                    )
                                )

                                ThemeColorRow(
                                    title: "主题色2",
                                    description: "用于左侧栏不受背景图直接影响的基础底色。",
                                    selection: Binding(
                                        get: { themePreference.sidebarThemeColor },
                                        set: { newValue in
                                            themePreference.sidebarThemeHex = NSColor(newValue).themeHexString
                                            themePreference.touch()
                                            try? modelContext.save()
                                        }
                                    )
                                )

                                Text(themePreference.backgroundImagePath == nil ? "当前使用纯色背景。" : "当前背景图与主题色已独立。背景图用于页面背景，主题色用于按钮、选中态和重点元素。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            Button("选择背景图") {
                                selectCustomThemeImage()
                            }
                            if themePreference.backgroundImagePath != nil {
                                Button("移除背景图") {
                                    ThemeAssetService.clearBackgroundImage(for: themePreference)
                                    try? modelContext.save()
                                }
                            }
                            Button("恢复默认主题") {
                                ThemeAssetService.clearBackgroundImage(for: themePreference)
                                themePreference.themeHex = AppThemeSettings.defaultThemeHex
                                themePreference.sidebarThemeHex = AppThemeSettings.defaultSidebarThemeHex
                                themePreference.touch()
                                try? modelContext.save()
                            }
                            Button("保存主题") {
                                isPresentingSaveTheme = true
                            }
                        }

                        if let imageURL = themePreference.backgroundImageURL {
                            Text("背景图：\(imageURL.lastPathComponent)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("已保存主题")
                            .font(.headline)

                        if savedThemes.isEmpty {
                            Text("还没有保存任何主题。可以先配置自定义主题，再点击“保存主题”。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)], spacing: 16) {
                                ForEach(savedThemes) { preset in
                                    SavedThemeCard(
                                        theme: preset,
                                        onApply: {
                                            do {
                                                try ThemeAssetService.applySavedTheme(preset, to: themePreference)
                                                try modelContext.save()
                                            } catch {
                                                message = error.localizedDescription
                                            }
                                        },
                                        onEdit: {
                                            editingSavedTheme = preset
                                        },
                                        onDelete: {
                                            pendingDeleteSavedTheme = preset
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var reminderSettingsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("提醒设置")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("通知权限")
                            .font(.headline)
                        Text(authorizationStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(authorizationButtonTitle) {
                        Task {
                            if authorizationStatus == .denied {
                                let opened = NotificationScheduler.shared.openNotificationSettings()
                                if !opened {
                                    message = "无法自动打开系统通知设置，请前往 系统设置 > 通知 > ChronoTick 手动开启。"
                                }
                            } else {
                                let result = await NotificationScheduler.shared.requestAuthorizationInteractively()
                                await refreshAuthorizationStatus()
                                switch result {
                                case .granted:
                                    message = "通知权限已开启。"
                                case .denied:
                                    let opened = NotificationScheduler.shared.openNotificationSettings()
                                    message = opened ? "通知权限已被拒绝，已尝试为你打开系统通知设置。" : "通知权限已被拒绝，请前往 系统设置 > 通知 > ChronoTick 手动开启。"
                                case .noPromptShown:
                                    let opened = NotificationScheduler.shared.openNotificationSettings()
                                    message = opened ? "系统没有弹出授权窗口，已尝试为你打开系统通知设置。" : "系统没有弹出授权窗口，请前往 系统设置 > 通知 > ChronoTick 手动开启。"
                                case let .unchanged(status):
                                    message = "通知权限状态未变化：\(authorizationText(for: status))。"
                                }
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    Text("每日清单任务提醒")
                        .font(.headline)
                    Spacer()
                    Button("新增规则") {
                        isPresentingAddDailyRule = true
                    }
                }

                if dailyReminderRules.isEmpty {
                    Text("暂无规则。新增后会按任务名正则匹配，并为符合规则的未完成每日清单任务自动安排多次提醒。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dailyReminderRules) { rule in
                        DailyReminderRuleCard(
                            rule: rule,
                            onEdit: { editingDailyRule = rule },
                            onDelete: { pendingDeleteDailyRule = rule }
                        )
                    }
                }

                Text("如果某个每日清单任务单独开启了提醒，则该任务优先使用自己的提醒设置，不再叠加这里的统一规则。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Text("列表任务提醒")
                    .font(.headline)

                if let preference = projectReminderPreference {
                    ProjectTaskReminderPreferenceEditor(preference: preference) {
                        try? modelContext.save()
                        Task { await NotificationScheduler.shared.ensureNotificationStateForAllTasks(in: modelContext) }
                    }
                }

                Text("列表任务提醒仅作用于有 deadline 且没有具体时间的未完成列表任务。若 deadline 包含具体时间，则忽略这些全局提醒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var csvCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CSV 导入导出")
                .font(.title3.bold())

            Picker("导入模式", selection: $importMode) {
                ForEach(CSVImportMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Button("导出任务 CSV") {
                    startExport(
                        text: CSVService.exportTasks(tasks),
                        filename: "chronotick_tasks.csv"
                    )
                }
                Button("导入任务 CSV") {
                    requestImport(.tasks)
                }
            }

            HStack {
                Button("导出打卡 CSV") {
                    startExport(
                        text: CSVService.exportHabitCheckIns(habits),
                        filename: "chronotick_habits.csv"
                    )
                }
                Button("导入打卡 CSV") {
                    requestImport(.habits)
                }
            }

            Text("所有日期时间均使用 ISO 8601 格式，README 和 Samples 目录中提供了示例文件。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("说明")
                .font(.headline)
            Text("ChronoTick 是本地优先的 macOS 时间管理工具。第一版不包含云同步、账号系统和重复任务。")
            Text("提醒使用系统通知，首次命中提醒规则或开启任务提醒时会请求通知权限。")
        }
        .padding(.horizontal, 4)
    }

    private func startExport(text: String, filename: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = filename
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            message = "CSV 导出完成。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func refreshAuthorizationStatus() async {
        let status = await NotificationScheduler.shared.authorizationStatus()
        authorizationStatus = status
        authorizationStatusText = await NotificationScheduler.shared.authorizationStatusDescription()
    }

    /// Saves a daily checklist reminder rule after validating both the regex and the reminder
    /// expression. Centralizing this logic keeps add/edit flows identical and guarantees that any
    /// successful rule change immediately triggers a full notification recomputation.
    private func saveDailyReminderRule(titlePattern: String, rawRule: String, editing rule: DailyTaskReminderRule? = nil) throws {
        _ = try NSRegularExpression(pattern: titlePattern)
        _ = try ReminderRuleParser.parse(rawRule)

        if let rule {
            rule.titlePattern = titlePattern
            rule.rawRule = rawRule
            rule.touch()
        } else {
            let newRule = DailyTaskReminderRule(titlePattern: titlePattern, rawRule: rawRule)
            modelContext.insert(newRule)
        }

        try modelContext.save()
        Task { await NotificationScheduler.shared.ensureNotificationStateForAllTasks(in: modelContext) }
    }

    private func authorizationText(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional:
            return "已授权"
        case .denied:
            return "已拒绝"
        case .notDetermined:
            return "未请求"
        case .ephemeral:
            return "临时授权"
        @unknown default:
            return "未知状态"
        }
    }

    private func startImport(_ kind: SettingsImportKind) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        switch kind {
        case .tasks:
            handleTaskImport(result: .success(url))
        case .habits:
            handleHabitImport(result: .success(url))
        }
    }

    private func requestImport(_ kind: SettingsImportKind) {
        if importMode == .replace {
            pendingReplaceImportKind = kind
        } else {
            startImport(kind)
        }
    }

    private func handleTaskImport(result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let csv = try String(contentsOf: url, encoding: .utf8)
            let records = try CSVService.importTasks(from: csv)
            if importMode == .replace {
                tasks.forEach {
                    NotificationScheduler.shared.removeNotification(for: $0)
                    modelContext.delete($0)
                }
            }
            let merged = CSVService.merge(taskRecords: records, into: tasks, mode: importMode)
            for record in merged {
                let task = TaskItem(
                    id: record.id ?? UUID(),
                    title: record.title,
                    date: record.date,
                    startDateTime: record.startDateTime,
                    endDateTime: record.endDateTime,
                    hasTime: record.hasTime,
                    isCompleted: record.isCompleted,
                    reminderEnabled: record.reminderEnabled,
                    reminderOffsetMinutes: record.reminderOffsetMinutes,
                    notes: record.notes,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
                modelContext.insert(task)
            }
            try modelContext.save()
            Task { await NotificationScheduler.shared.ensureNotificationStateForAllTasks(in: modelContext) }
            message = "任务导入完成，共导入 \(merged.count) 条。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func handleHabitImport(result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let csv = try String(contentsOf: url, encoding: .utf8)
            let records = try CSVService.importHabitCheckIns(from: csv)
            if importMode == .replace {
                habits.forEach { modelContext.delete($0) }
            }
            for record in records {
                let habit = habits.first(where: { $0.name == record.name }) ?? Habit(name: record.name, colorHex: "#5B8DEF")
                if !habits.contains(where: { $0.id == habit.id }) {
                    modelContext.insert(habit)
                }
                if let existing = habit.checkIns.first(where: { Calendar.current.isDate($0.date, inSameDayAs: record.date) }) {
                    existing.isCheckedIn = record.isCheckedIn
                } else {
                    let checkIn = HabitCheckIn(id: record.id ?? UUID(), date: record.date, isCheckedIn: record.isCheckedIn, habit: habit)
                    modelContext.insert(checkIn)
                }
            }
            try modelContext.save()
            message = "打卡导入完成，共处理 \(records.count) 条。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func selectCustomThemeImage() {
        guard let url = chooseThemeImageURL() else { return }
        do {
            let theme = ThemeAssetService.ensureThemeSettings(in: modelContext)
            try ThemeAssetService.applyBackgroundImage(from: url, to: theme)
            try modelContext.save()
        } catch {
            message = error.localizedDescription
        }
    }

    private func chooseThemeImageURL() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private struct ThemePreviewSwatch: View {
    let title: String
    let themeColor: Color
    let sidebarThemeColor: Color
    let backgroundImageURL: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            themeColor.opacity(0.16).mix(with: .white, by: 0.78),
                            Color(nsColor: .windowBackgroundColor)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let imageURL = backgroundImageURL,
               let image = NSImage(contentsOf: imageURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 170, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(0.92)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.26))
            }

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(themeColor.opacity(0.5), lineWidth: 1)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(backgroundImageURL == nil ? "纯色主题" : "图片主题")
                    .font(.caption)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(12)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(sidebarThemeColor.opacity(0.78))
                .frame(width: 52, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(themeColor.opacity(0.35), lineWidth: 1)
                )
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(width: 170, height: 108)
    }
}

private struct SavedThemeCard: View {
    let theme: SavedThemePreset
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onApply) {
                ThemePreviewSwatch(
                    title: theme.name,
                    themeColor: theme.themeColor,
                    sidebarThemeColor: theme.sidebarThemeColor,
                    backgroundImageURL: theme.backgroundImageURL
                )
            }
            .buttonStyle(.plain)

            Text(theme.name)
                .font(.headline)

            HStack(spacing: 8) {
                ThemeChip(color: theme.themeColor, title: "主题色1")
                ThemeChip(color: theme.sidebarThemeColor, title: "主题色2")
            }

            HStack {
                Button("使用", action: onApply)
                Button("编辑", action: onEdit)
                Button("删除", role: .destructive, action: onDelete)
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}

private struct ThemeChip: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.black.opacity(0.08), lineWidth: 1)
                )
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ThemeColorRow: View {
    let title: String
    let description: String
    @Binding var selection: Color
    @State private var isPresentingPalette = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button {
                    isPresentingPalette = true
                } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selection)
                            .frame(width: 28, height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.black.opacity(0.08), lineWidth: 1)
                            )
                        Text(title)
                    }
                }
                .buttonStyle(.bordered)

                Text(NSColor(selection).themeHexString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .popover(isPresented: $isPresentingPalette, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("选择\(title)")
                    .font(.headline)
                ColorPicker("", selection: $selection, supportsOpacity: false)
                    .labelsHidden()
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 280)
        }
    }
}

private struct SaveThemeSheet: View {
    let themePreference: AppThemeSettings
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("保存主题")
                .font(.title3.bold())

            ThemePreviewSwatch(
                title: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新主题" : name,
                themeColor: themePreference.themeColor,
                sidebarThemeColor: themePreference.sidebarThemeColor,
                backgroundImageURL: themePreference.backgroundImageURL
            )

            TextField("主题名称", text: $name)
                .textFieldStyle(.roundedBorder)

            Text("会保存当前背景图片、主题色1和主题色2。背景图片会复制到 ChronoTick 自己的主题库中，不依赖原始文件位置。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    onSave(name)
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

private struct EditSavedThemeSheet: View {
    let theme: SavedThemePreset
    let onSave: (String, String, String, URL?, Bool) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var themeColor: Color
    @State private var sidebarThemeColor: Color
    @State private var selectedImageURL: URL?
    @State private var removeBackgroundImage = false

    init(
        theme: SavedThemePreset,
        onSave: @escaping (String, String, String, URL?, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.theme = theme
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: theme.name)
        _themeColor = State(initialValue: theme.themeColor)
        _sidebarThemeColor = State(initialValue: theme.sidebarThemeColor)
    }

    private var effectiveBackgroundImageURL: URL? {
        if removeBackgroundImage { return nil }
        return selectedImageURL ?? theme.backgroundImageURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑主题")
                .font(.title3.bold())

            ThemePreviewSwatch(
                title: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? theme.name : name,
                themeColor: themeColor,
                sidebarThemeColor: sidebarThemeColor,
                backgroundImageURL: effectiveBackgroundImageURL
            )

            TextField("主题名称", text: $name)
                .textFieldStyle(.roundedBorder)

            ThemeColorRow(title: "主题色1", description: "用于按钮、选中态和强调元素。", selection: $themeColor)
            ThemeColorRow(title: "主题色2", description: "用于左侧栏不受背景图直接影响的基础底色。", selection: $sidebarThemeColor)

            HStack {
                Button("更换背景图") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.allowedContentTypes = [.image]
                    if panel.runModal() == .OK {
                        selectedImageURL = panel.url
                        removeBackgroundImage = false
                    }
                }
                if effectiveBackgroundImageURL != nil {
                    Button("移除背景图") {
                        selectedImageURL = nil
                        removeBackgroundImage = true
                    }
                }
            }

            Text("保存后会同步更新主题数据库，并替换旧的主题图片副本，避免无用文件残留。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存修改") {
                    onSave(
                        name,
                        NSColor(themeColor).themeHexString,
                        NSColor(sidebarThemeColor).themeHexString,
                        selectedImageURL,
                        removeBackgroundImage
                    )
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

/// `DailyReminderRuleCard` presents one shared reminder rule and exposes explicit edit/delete
/// affordances instead of hiding rule management inside a context menu only.
private struct DailyReminderRuleCard: View {
    let rule: DailyTaskReminderRule
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(rule.titlePattern)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                Spacer()
                Button("编辑", action: onEdit)
                    .buttonStyle(.borderless)
                Button("删除", role: .destructive, action: onDelete)
                    .buttonStyle(.borderless)
            }

            Text(rule.rawRule)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(ReminderSettingsService.displayTexts(for: rule), id: \.self) { text in
                    Text(text)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .contextMenu {
            Button("编辑规则", action: onEdit)
            Button("删除规则", role: .destructive, action: onDelete)
        }
    }
}

private struct ProjectTaskReminderPreferenceEditor: View {
    @Bindable var preference: ProjectTaskReminderPreferences
    let onChange: () -> Void

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: preference.reminderHour, minute: preference.reminderMinute, second: 0, of: .now) ?? .now
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            preference.reminderHour = components.hour ?? 23
            preference.reminderMinute = components.minute ?? 0
            preference.touch()
            onChange()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("提前1天", isOn: Binding(
                get: { preference.remindOneDayBefore },
                set: { newValue in
                    preference.remindOneDayBefore = newValue
                    preference.touch()
                    onChange()
                }
            ))

            Toggle("提前1星期", isOn: Binding(
                get: { preference.remindOneWeekBefore },
                set: { newValue in
                    preference.remindOneWeekBefore = newValue
                    preference.touch()
                    onChange()
                }
            ))

            DatePicker("提醒时间", selection: reminderTime, displayedComponents: .hourAndMinute)
        }
    }
}

private struct AddDailyReminderRuleSheet: View {
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @State private var titlePattern = ""
    @State private var rawRule = ""

    private var previewTexts: [String] {
        (try? ReminderRuleParser.displayTexts(from: rawRule)) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新增提醒规则")
                .font(.title3.bold())

            TextField("任务名正则字符串", text: $titlePattern)
                .textFieldStyle(.roundedBorder)

            TextField("规则字符串，例如 -1d;-3m;-30s;0m;30s", text: $rawRule)
                .textFieldStyle(.roundedBorder)

            if !previewTexts.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(previewTexts, id: \.self) { text in
                        Text(text)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                    }
                }
            }

            Text("支持 d / h / m / s，也支持小数，例如 -1.5m 会解析成提前1分钟30秒。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    onSave(titlePattern.trimmingCharacters(in: .whitespacesAndNewlines), rawRule.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .disabled(titlePattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rawRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

/// `EditDailyReminderRuleSheet` reuses the same parsing model as the add flow, but it starts from
/// an existing persisted rule. Keeping it separate from the storage layer makes the editing flow
/// easy to understand for future contributors.
private struct EditDailyReminderRuleSheet: View {
    let rule: DailyTaskReminderRule
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @State private var titlePattern: String
    @State private var rawRule: String

    init(rule: DailyTaskReminderRule, onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.rule = rule
        self.onSave = onSave
        self.onCancel = onCancel
        _titlePattern = State(initialValue: rule.titlePattern)
        _rawRule = State(initialValue: rule.rawRule)
    }

    private var previewTexts: [String] {
        (try? ReminderRuleParser.displayTexts(from: rawRule)) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑提醒规则")
                .font(.title3.bold())

            TextField("任务名正则字符串", text: $titlePattern)
                .textFieldStyle(.roundedBorder)

            TextField("规则字符串，例如 -1d;-3m;-30s;0m;30s", text: $rawRule)
                .textFieldStyle(.roundedBorder)

            if !previewTexts.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(previewTexts, id: \.self) { text in
                        Text(text)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                    }
                }
            }

            Text("修改后会立即按新规则重新计算所有未完成每日清单任务的统一提醒。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存修改") {
                    onSave(
                        titlePattern.trimmingCharacters(in: .whitespacesAndNewlines),
                        rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .disabled(titlePattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rawRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

private struct ReplaceImportConfirmationSheet: View {
    let kind: SettingsImportKind
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var confirmationText = ""

    private let requiredText = "I comfirm to replace import"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("确认覆盖导入")
                .font(.title3.bold())

            Text("覆盖导入会删除当前全部\(kind.title)数据，再导入新的 CSV。此操作不可撤销。")
                .foregroundStyle(.secondary)

            Text("请输入以下内容后才能继续：")
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
                Button("继续导入", action: onConfirm)
                    .disabled(confirmationText != requiredText)
            }
        }
        .padding(24)
        .frame(width: 430)
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
