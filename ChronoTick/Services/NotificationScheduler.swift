import Foundation
import AppKit
import SwiftData
import UserNotifications

/// `NotificationScheduler` is the bridge between ChronoTick's local models and macOS
/// `UserNotifications`.
///
/// The class deliberately owns *all* notification lifecycle rules:
/// - requesting permission
/// - translating app reminder rules into concrete fire dates
/// - removing stale pending and delivered notifications
/// - deciding how to recover when a reminder is moved to the current minute
///
/// Centralizing this logic avoids a common source of bugs in reminder-driven apps: different UI
/// entry points updating data without rescheduling notifications in exactly the same way.
@MainActor
final class NotificationScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationScheduler()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Requests permission only when the system has not asked the user yet. If a decision already
    /// exists, we return that status unchanged instead of forcing callers to interpret system state.
    func requestAuthorizationIfNeeded() async -> UNAuthorizationStatus {
        NSApp.activate(ignoringOtherApps: true)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return settings.authorizationStatus }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await center.notificationSettings().authorizationStatus
    }

    func requestAuthorizationInteractively() async -> NotificationPermissionResult {
        let previous = await authorizationStatus()
        let current = await requestAuthorizationIfNeeded()

        if current == .authorized || current == .provisional {
            return .granted
        }

        if current == .denied {
            return .denied
        }

        if previous == .notDetermined && current == .notDetermined {
            return .noPromptShown
        }

        return .unchanged(current)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Human-readable permission text used by the settings screen.
    func authorizationStatusDescription() async -> String {
        switch await authorizationStatus() {
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

    func openNotificationSettings() -> Bool {
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return true
            }
        }

        return false
    }

    func ensureNotificationState(for task: TaskItem, in context: ModelContext) async {
        // Always clear both pending and already delivered notifications before recomputing.
        // This keeps renamed or rescheduled tasks from inheriting stale reminders.
        await removeNotifications(withPrefix: dailyTaskPrefix(for: task))
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.notificationIdentifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [task.notificationIdentifier])

        guard task.isVisibleInWeekView, let start = task.startDateTime else { return }

        let descriptor = FetchDescriptor<DailyTaskReminderRule>(sortBy: [SortDescriptor(\.createdAt)])
        let rules = (try? context.fetch(descriptor)) ?? []
        var scheduledDates: [ScheduledReminder] = []
        if task.reminderEnabled {
            // Per-task manual reminders override the shared regex-based reminder rules.
            scheduledDates.append(
                ScheduledReminder(
                    identifier: "\(dailyTaskPrefix(for: task))-manual-\(task.reminderOffsetMinutes)",
                    fireDate: start.adding(minutes: -task.reminderOffsetMinutes),
                    description: manualReminderDescription(minutesBefore: task.reminderOffsetMinutes)
                )
            )
        } else {
            let matchedOffsets = ReminderSettingsService.matchedOffsets(for: task.title, rules: rules)
            scheduledDates += matchedOffsets.map {
                ScheduledReminder(
                    identifier: "\(dailyTaskPrefix(for: task))-rule-\($0.seconds)",
                    fireDate: start.addingTimeInterval(TimeInterval($0.seconds)),
                    description: $0.displayText + "提醒"
                )
            }
        }

        let futureDates = scheduledDates.compactMap { scheduled in
            normalizedScheduledReminder(from: scheduled)
        }
        guard !futureDates.isEmpty else { return }

        _ = await requestAuthorizationIfNeeded()
        for scheduled in futureDates {
            await addNotification(
                identifier: scheduled.identifier,
                title: "ChronoTick 每日清单任务提醒",
                body: task.title,
                detail: scheduled.description,
                fireDate: scheduled.fireDate
            )
        }
    }

    func ensureNotificationState(for projectTask: ProjectTask, in context: ModelContext) async {
        await removeNotifications(withPrefix: projectTaskPrefix(for: projectTask))

        guard projectTask.isVisibleInWeekView,
              projectTask.deadlineIncludesTime == false,
              let deadlineDate = projectTask.deadlineDate
        else { return }

        let preferences = ReminderSettingsService.ensureProjectTaskPreferences(in: context)
        let offsets: [Int] = [
            preferences.remindOneWeekBefore ? -7 : nil,
            preferences.remindOneDayBefore ? -1 : nil
        ].compactMap { $0 }

        guard !offsets.isEmpty else { return }

        _ = await requestAuthorizationIfNeeded()
        let calendar = Calendar.current
        let deadlineDay = calendar.startOfDay(for: deadlineDate)

        for offset in offsets {
            guard let targetDay = calendar.date(byAdding: .day, value: offset, to: deadlineDay) else { continue }
            let fireDate = calendar.date(
                bySettingHour: preferences.reminderHour,
                minute: preferences.reminderMinute,
                second: 0,
                of: targetDay
            ) ?? targetDay
            guard let normalized = normalizedScheduledReminder(
                from: ScheduledReminder(
                    identifier: "\(projectTaskPrefix(for: projectTask))-\(abs(offset))d",
                    fireDate: fireDate,
                    description: projectTaskReminderDescription(daysBefore: abs(offset), atHour: preferences.reminderHour, minute: preferences.reminderMinute)
                )
            ) else { continue }

            await addNotification(
                identifier: normalized.identifier,
                title: "ChronoTick 列表任务提醒",
                body: projectTask.title,
                detail: normalized.description,
                fireDate: normalized.fireDate
            )
        }
    }

    func ensureNotificationStateForAllTasks(in context: ModelContext) async {
        let taskDescriptor = FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)])
        let projectDescriptor = FetchDescriptor<ProjectTask>(sortBy: [SortDescriptor(\.createdAt)])
        let tasks = (try? context.fetch(taskDescriptor)) ?? []
        let projectTasks = (try? context.fetch(projectDescriptor)) ?? []

        for task in tasks {
            await ensureNotificationState(for: task, in: context)
        }
        for task in projectTasks {
            await ensureNotificationState(for: task, in: context)
        }
    }

    func removeNotification(for task: TaskItem) {
        Task { await removeNotifications(withPrefix: dailyTaskPrefix(for: task)) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.notificationIdentifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [task.notificationIdentifier])
    }

    func removeNotification(for projectTask: ProjectTask) {
        Task { await removeNotifications(withPrefix: projectTaskPrefix(for: projectTask)) }
    }

    private func addNotification(identifier: String, title: String, body: String, detail: String, fireDate: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.subtitle = detail
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func removeNotifications(withPrefix prefix: String) async {
        let pendingIdentifiers = await pendingNotificationIdentifiers(matching: prefix)
        let deliveredIdentifiers = await deliveredNotificationIdentifiers(matching: prefix)
        let identifiers = Array(Set(pendingIdentifiers + deliveredIdentifiers))
        guard !identifiers.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func pendingNotificationIdentifiers(matching prefix: String) async -> [String] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
            }
        }
    }

    private func deliveredNotificationIdentifiers(matching prefix: String) async -> [String] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications.map(\.request.identifier).filter { $0.hasPrefix(prefix) })
            }
        }
    }

    private func dailyTaskPrefix(for task: TaskItem) -> String {
        "task-\(task.id.uuidString)-multi"
    }

    private func projectTaskPrefix(for task: ProjectTask) -> String {
        "project-task-\(task.id.uuidString)"
    }

    private func normalizedScheduledReminder(from scheduled: ScheduledReminder, now: Date = .now) -> ScheduledReminder? {
        // If the target time is still in the future, schedule it as-is.
        if scheduled.fireDate > now {
            return scheduled
        }

        // If the user just edited the task and the reminder falls in the current minute,
        // reschedule it one second later instead of silently dropping it.
        if Calendar.current.isDate(scheduled.fireDate, equalTo: now, toGranularity: .minute) {
            return ScheduledReminder(
                identifier: scheduled.identifier,
                fireDate: now.addingTimeInterval(1),
                description: scheduled.description
            )
        }

        return nil
    }

    private func manualReminderDescription(minutesBefore: Int) -> String {
        if minutesBefore == 0 {
            return "准时提醒"
        }
        return "提前\(minutesBefore)分钟提醒"
    }

    private func projectTaskReminderDescription(daysBefore: Int, atHour hour: Int, minute: Int) -> String {
        let dayText = daysBefore == 7 ? "提前1星期提醒" : "提前\(daysBefore)天提醒"
        return "\(dayText)（\(String(format: "%02d:%02d", hour, minute))）"
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

enum NotificationPermissionResult {
    case granted
    case denied
    case noPromptShown
    case unchanged(UNAuthorizationStatus)
}

private struct ScheduledReminder {
    let identifier: String
    let fireDate: Date
    let description: String
}
