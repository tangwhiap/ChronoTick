import SwiftData
import SwiftUI

/// Collects the small set of theme-driven colors the week timeline cares about.
///
/// Keeping these derived values together avoids repeating opacity math throughout the view tree
/// and makes future visual tuning much easier.
private struct WeekTimelineTheme {
    let incompleteTaskFillColor: Color
    let incompleteTaskStrokeColor: Color
    let untimedTaskFillColor: Color
    let untimedAreaBackgroundColor: Color
    let todayColumnColor: Color
    let todayBadgeColor: Color

    init(settings: AppThemeSettings?) {
        let themeColor = settings?.themeColor ?? Color.accentColor
        let sidebarThemeColor = settings?.sidebarThemeColor ?? Color(nsColor: NSColor(themeHex: AppThemeSettings.defaultSidebarThemeHex) ?? .underPageBackgroundColor)

        incompleteTaskFillColor = themeColor.opacity(0.24)
        incompleteTaskStrokeColor = themeColor.opacity(0.38)
        untimedTaskFillColor = themeColor.opacity(0.18)
        untimedAreaBackgroundColor = themeColor.opacity(0.06)
        todayColumnColor = sidebarThemeColor.opacity(0.4)
        todayBadgeColor = sidebarThemeColor.opacity(0.15)
    }
}

struct WeekTimelineView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\TaskItem.date), SortDescriptor(\TaskItem.startDateTime), SortDescriptor(\TaskItem.createdAt)]) private var tasks: [TaskItem]
    @Query(sort: [SortDescriptor(\ProjectTask.deadlineDate), SortDescriptor(\ProjectTask.createdAt)]) private var projectTasks: [ProjectTask]
    @Query(sort: [SortDescriptor(\AppThemeSettings.createdAt)]) private var themeSettings: [AppThemeSettings]

    private var metrics: WeekTimelineLayoutMetrics {
        viewModel.weekTimelineLayoutMetrics
    }

    private var theme: WeekTimelineTheme {
        WeekTimelineTheme(settings: themeSettings.first)
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let selected = viewModel.selectedDate.startOfDay()
        let weekday = calendar.component(.weekday, from: selected)
        let offset = weekday - calendar.firstWeekday
        let weekStart = calendar.date(byAdding: .day, value: -offset, to: selected) ?? selected
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 0) {
                timeAxis
                WeekTimelineStrip(
                    weekDates: weekDates,
                    metrics: metrics,
                    tasks: tasks,
                    projectTasks: projectTasks,
                    theme: theme
                )
            }
            .padding(.bottom, 40)
        }
        .background(Color.clear)
    }

    private var timeAxis: some View {
        VStack(spacing: 0) {
            Color.clear.frame(width: metrics.timeAxisWidth, height: metrics.untimedAreaHeight + metrics.headerHeight)
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: metrics.timeAxisWidth, height: metrics.hourHeight, alignment: .topTrailing)
                    .padding(.trailing, 8)
            }
        }
    }
}

/// A single week strip keeps the timeline logic grouped by week while preserving the stable
/// interaction model that shipped before experimental infinite scrolling was introduced.
private struct WeekTimelineStrip: View {
    let weekDates: [Date]
    let metrics: WeekTimelineLayoutMetrics
    let tasks: [TaskItem]
    let projectTasks: [ProjectTask]
    let theme: WeekTimelineTheme

    var body: some View {
        ForEach(Array(weekDates.enumerated()), id: \.offset) { index, date in
            DayTimelineColumn(
                date: date,
                dayIndex: index,
                weekDates: weekDates,
                untimedTasks: untimedTasksForDate(date),
                timelineSegments: timelineSegmentsForDate(date),
                projectDeadlineMarkers: projectDeadlineMarkersForDate(date),
                metrics: metrics,
                dayIdentifier: "day-\(Int(date.startOfDay().timeIntervalSinceReferenceDate))",
                theme: theme
            )
        }
    }

    private func untimedTasksForDate(_ date: Date) -> [TaskItem] {
        tasks.filter {
            $0.isVisibleInWeekView &&
            $0.timingKind == .untimed &&
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }
    }

    private func timelineSegmentsForDate(_ date: Date) -> [TimelineTaskSegment] {
        tasks
            .filter { $0.isVisibleInWeekView && $0.timingKind != .untimed }
            .flatMap { TimelineTaskSegment.segments(for: $0, on: date) }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate < rhs.startDate
                }
                return lhs.task.createdAt < rhs.task.createdAt
            }
    }

    private func projectDeadlineMarkersForDate(_ date: Date) -> [ProjectDeadlineCluster] {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)

        let relevantTasks = projectTasks
            .filter(\.isVisibleInWeekView)
            .sorted { lhs, rhs in
                let lhsDeadline = lhs.deadlineDate ?? .distantFuture
                let rhsDeadline = rhs.deadlineDate ?? .distantFuture
                if lhsDeadline != rhsDeadline { return lhsDeadline < rhsDeadline }
                return lhs.createdAt < rhs.createdAt
            }

        var baseMarkers: [ProjectDeadlineMarker] = []
        for task in relevantTasks {
            guard let effectiveDate = task.effectiveDeadlineDate(calendar: calendar),
                  calendar.isDate(effectiveDate, inSameDayAs: targetDay)
            else { continue }

            baseMarkers.append(ProjectDeadlineMarker(task: task, displayDate: effectiveDate))
        }

        let sortedMarkers = baseMarkers.sorted { lhs, rhs in
            if lhs.displayDate != rhs.displayDate {
                return lhs.displayDate < rhs.displayDate
            }
            return lhs.task.createdAt < rhs.task.createdAt
        }

        return ProjectDeadlineCluster.makeClusters(
            from: sortedMarkers,
            columnWidth: metrics.columnWidth,
            hourHeight: metrics.hourHeight
        )
    }
}

private struct DayTimelineColumn: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.modelContext) private var modelContext

    let date: Date
    let dayIndex: Int
    let weekDates: [Date]
    let untimedTasks: [TaskItem]
    let timelineSegments: [TimelineTaskSegment]
    let projectDeadlineMarkers: [ProjectDeadlineCluster]
    let metrics: WeekTimelineLayoutMetrics
    let dayIdentifier: String
    let theme: WeekTimelineTheme

    var body: some View {
        VStack(spacing: 0) {
            header
            untimedArea
            ZStack(alignment: .topLeading) {
                timelineGrid
                if date.isTodayInCurrentCalendar {
                    CurrentTimeIndicator(hourHeight: metrics.hourHeight)
                }
                ForEach(projectDeadlineMarkers) { cluster in
                    ProjectDeadlineClusterView(cluster: cluster, columnWidth: metrics.columnWidth, hourHeight: metrics.hourHeight)
                }
                ForEach(timelineSegments) { segment in
                    TaskTimelineCard(segment: segment, dayIndex: dayIndex, weekDates: weekDates, columnWidth: metrics.columnWidth, hourHeight: metrics.hourHeight, theme: theme)
                }
            }
            .frame(width: metrics.columnWidth, height: metrics.hourHeight * 24)
        }
        .background(viewModel.selectedDate.startOfDay() == date.startOfDay() ? theme.todayColumnColor : Color.clear)
        .overlay(Rectangle().fill(Color.secondary.opacity(0.15)).frame(width: 1), alignment: .trailing)
        .id(dayIdentifier)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(DateFormatter.displayMonthDay.string(from: date))
                .font(.headline)
            if date.isTodayInCurrentCalendar {
                Text("今天")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(theme.todayBadgeColor))
            }
        }
        .frame(width: metrics.columnWidth, height: metrics.headerHeight)
    }

    private var untimedArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("无时间任务")
                .font(.caption)
                .foregroundStyle(.secondary)
            if untimedTasks.isEmpty {
                Text("拖入或新建")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(untimedTasks.prefix(3)) { task in
                    Button {
                        viewModel.openEdit(task: task)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            Text(task.title)
                                .lineLimit(1)
                            Spacer()
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(task.isCompleted ? Color.gray.opacity(0.14) : theme.untimedTaskFillColor)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(task.isCompleted ? "标记未完成" : "标记完成") {
                            viewModel.toggleCompletion(for: task, modelContext: modelContext)
                        }
                        Button("编辑") { viewModel.openEdit(task: task) }
                        Button("删除", role: .destructive) { viewModel.delete(task: task, modelContext: modelContext) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: metrics.columnWidth, height: metrics.untimedAreaHeight, alignment: .topLeading)
        .background(theme.untimedAreaBackgroundColor)
    }

    private var timelineGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { _ in
                Rectangle()
                    .fill(Color.secondary.opacity(0.08))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: metrics.columnWidth, height: metrics.hourHeight * 24)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.secondary.opacity(0.12)).frame(width: 1)
        }
    }
}

private struct TaskTimelineCard: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.modelContext) private var modelContext

    let segment: TimelineTaskSegment
    let dayIndex: Int
    let weekDates: [Date]
    let columnWidth: CGFloat
    let hourHeight: CGFloat
    let theme: WeekTimelineTheme

    @State private var activeInteraction: TimelineCardInteraction?
    @State private var committedPreview: TimelineCardPreview?

    private var task: TaskItem { segment.task }
    private let horizontalInset: CGFloat = 6
    private let handleInset: CGFloat = 10

    private var startMinutes: CGFloat {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: segment.startDate)
        return CGFloat((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
    }

    private var durationMinutes: CGFloat {
        switch segment.displayKind {
        case .point:
            return 20
        case .range:
            return max(CGFloat(segment.endDate.timeIntervalSince(segment.startDate) / 60), 20)
        }
    }

    private var yPosition: CGFloat {
        startMinutes / 60 * hourHeight
    }

    private var cardHeight: CGFloat {
        durationMinutes / 60 * hourHeight
    }

    private var preview: TimelineCardPreview {
        if let activeInteraction {
            return makePreview(for: activeInteraction)
        }
        if let committedPreview {
            return committedPreview
        }
        return basePreview
    }

    private var contentWidth: CGFloat {
        columnWidth - (horizontalInset * 2) - 16
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(task.isCompleted ? Color.gray.opacity(0.16) : theme.incompleteTaskFillColor)
            RoundedRectangle(cornerRadius: 12)
                .stroke(task.isCompleted ? Color.gray.opacity(0.3) : theme.incompleteTaskStrokeColor)

            TaskTimelineCardContent(
                title: task.title,
                fullTimeText: preview.fullTimeText,
                startOnlyTimeText: preview.startOnlyTimeText,
                width: contentWidth,
                height: preview.height
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 7)

            if segment.canResizeTop {
                handleBar
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .contentShape(Rectangle())
                    .gesture(topResizeGesture)
            }

            if segment.canResizeBottom {
                VStack {
                    Spacer(minLength: 0)
                    handleBar
                        .padding(.bottom, 4)
                        .contentShape(Rectangle())
                        .gesture(bottomResizeGesture)
                }
            }
        }
        .frame(width: columnWidth - (horizontalInset * 2), height: preview.height, alignment: .topLeading)
        .offset(x: preview.xPosition, y: preview.yPosition)
        .transaction { transaction in
            transaction.animation = nil
        }
        .gesture(moveGesture)
        .onTapGesture {
            viewModel.openEdit(task: task)
        }
        .contextMenu {
            Button(task.isCompleted ? "标记未完成" : "标记完成") {
                viewModel.toggleCompletion(for: task, modelContext: modelContext)
            }
            Button("编辑") { viewModel.openEdit(task: task) }
            Button("删除", role: .destructive) { viewModel.delete(task: task, modelContext: modelContext) }
        }
    }

    private var handleBar: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.45))
            .frame(width: max(24, (columnWidth - (horizontalInset * 2) - (handleInset * 2)) * 0.22), height: 3)
            .padding(.horizontal, handleInset)
    }

    private var topResizeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                activeInteraction = TimelineCardInteraction(mode: .resizeTop, translation: value.translation)
            }
            .onEnded { value in
                let finalPreview = makePreview(for: TimelineCardInteraction(mode: .resizeTop, translation: value.translation))
                activeInteraction = nil
                committedPreview = finalPreview
                Task {
                    await viewModel.resize(task: task, edge: .top, targetMinute: finalPreview.targetStartMinute, modelContext: modelContext)
                    await MainActor.run {
                        committedPreview = nil
                    }
                }
            }
    }

    private var bottomResizeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                activeInteraction = TimelineCardInteraction(mode: .resizeBottom, translation: value.translation)
            }
            .onEnded { value in
                let finalPreview = makePreview(for: TimelineCardInteraction(mode: .resizeBottom, translation: value.translation))
                activeInteraction = nil
                committedPreview = finalPreview
                Task {
                    await viewModel.resize(task: task, edge: .bottom, targetMinute: finalPreview.targetEndMinute ?? finalPreview.targetStartMinute, modelContext: modelContext)
                    await MainActor.run {
                        committedPreview = nil
                    }
                }
            }
    }

    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                guard segment.canMove else { return }
                activeInteraction = TimelineCardInteraction(mode: .move, translation: value.translation)
            }
            .onEnded { value in
                guard segment.canMove else {
                    return
                }
                let finalPreview = makePreview(for: TimelineCardInteraction(mode: .move, translation: value.translation))
                activeInteraction = nil
                committedPreview = finalPreview
                Task {
                    await viewModel.move(task: task, to: finalPreview.targetDate, startMinute: finalPreview.targetStartMinute, modelContext: modelContext)
                    await MainActor.run {
                        committedPreview = nil
                    }
                }
            }
    }

    private var basePreview: TimelineCardPreview {
        TimelineCardPreview(
            xPosition: horizontalInset,
            yPosition: yPosition,
            height: cardHeight,
            targetDate: segment.displayDate,
            targetStartMinute: Int(startMinutes),
            targetEndMinute: segment.displayKind == .range ? Int(startMinutes + durationMinutes) : nil,
            displayStartDate: task.startDateTime ?? segment.startDate,
            displayEndDate: task.endDateTime
        )
    }

    private func makePreview(for interaction: TimelineCardInteraction) -> TimelineCardPreview {
        TimelineCardPreview.make(
            interaction: interaction,
            segment: segment,
            dayIndex: dayIndex,
            weekDates: weekDates,
            columnWidth: columnWidth,
            horizontalInset: horizontalInset,
            yPosition: yPosition,
            cardHeight: cardHeight,
            hourHeight: hourHeight,
            snapMinutes: viewModel.snapMinutes
        )
    }
}

private enum TimelineCardInteractionMode {
    case move
    case resizeTop
    case resizeBottom
}

private struct TimelineCardInteraction {
    let mode: TimelineCardInteractionMode
    let translation: CGSize
}

private struct TimelineCardPreview {
    let xPosition: CGFloat
    let yPosition: CGFloat
    let height: CGFloat
    let targetDate: Date
    let targetStartMinute: Int
    let targetEndMinute: Int?
    let displayStartDate: Date
    let displayEndDate: Date?

    var fullTimeText: String {
        let formatter = DateFormatter.displayTime
        guard let displayEndDate else {
            return formatter.string(from: displayStartDate)
        }
        return "\(formatter.string(from: displayStartDate))–\(formatter.string(from: displayEndDate))"
    }

    var startOnlyTimeText: String {
        DateFormatter.displayTime.string(from: displayStartDate)
    }

    static func make(
        interaction: TimelineCardInteraction,
        segment: TimelineTaskSegment,
        dayIndex: Int,
        weekDates: [Date],
        columnWidth: CGFloat,
        horizontalInset: CGFloat,
        yPosition: CGFloat,
        cardHeight: CGFloat,
        hourHeight: CGFloat,
        snapMinutes: Int,
        calendar: Calendar = .current
    ) -> TimelineCardPreview {
        switch interaction.mode {
        case .move:
            return movePreview(
                segment: segment,
                dayIndex: dayIndex,
                weekDates: weekDates,
                columnWidth: columnWidth,
                horizontalInset: horizontalInset,
                yPosition: yPosition,
                cardHeight: cardHeight,
                hourHeight: hourHeight,
                snapMinutes: snapMinutes,
                translation: interaction.translation,
                calendar: calendar
            )
        case .resizeTop:
            return topResizePreview(
                segment: segment,
                horizontalInset: horizontalInset,
                yPosition: yPosition,
                hourHeight: hourHeight,
                snapMinutes: snapMinutes,
                translation: interaction.translation,
                calendar: calendar
            )
        case .resizeBottom:
            return bottomResizePreview(
                segment: segment,
                horizontalInset: horizontalInset,
                yPosition: yPosition,
                cardHeight: cardHeight,
                hourHeight: hourHeight,
                snapMinutes: snapMinutes,
                translation: interaction.translation,
                calendar: calendar
            )
        }
    }

    private static func movePreview(
        segment: TimelineTaskSegment,
        dayIndex: Int,
        weekDates: [Date],
        columnWidth: CGFloat,
        horizontalInset: CGFloat,
        yPosition: CGFloat,
        cardHeight: CGFloat,
        hourHeight: CGFloat,
        snapMinutes: Int,
        translation: CGSize,
        calendar: Calendar
    ) -> TimelineCardPreview {
        let rawIndex = dayIndex + Int((translation.width / columnWidth).rounded())
        let targetIndex = max(0, min(weekDates.count - 1, rawIndex))
        let targetDate = calendar.startOfDay(for: weekDates[targetIndex])
        let targetStartMinute = clampedStartMinute(
            minuteFromYPosition(yPosition + translation.height, hourHeight: hourHeight),
            snapMinutes: snapMinutes
        )
        let previewStart = date(on: targetDate, minute: targetStartMinute)
        let duration = segment.task.endDateTime?.timeIntervalSince(segment.task.startDateTime ?? segment.startDate)
        let previewEnd = duration.map { previewStart.addingTimeInterval(max(TimeInterval(snapMinutes * 60), $0)) }

        return TimelineCardPreview(
            xPosition: horizontalInset + translation.width,
            yPosition: CGFloat(targetStartMinute) / 60 * hourHeight,
            height: max(cardHeight, 20),
            targetDate: targetDate,
            targetStartMinute: targetStartMinute,
            targetEndMinute: previewEnd.map { minuteOfDay(for: $0, calendar: calendar) },
            displayStartDate: previewStart,
            displayEndDate: previewEnd
        )
    }

    private static func topResizePreview(
        segment: TimelineTaskSegment,
        horizontalInset: CGFloat,
        yPosition: CGFloat,
        hourHeight: CGFloat,
        snapMinutes: Int,
        translation: CGSize,
        calendar: Calendar
    ) -> TimelineCardPreview {
        guard let currentEnd = segment.task.endDateTime else {
            return unchangedPreview(segment: segment, horizontalInset: horizontalInset, yPosition: yPosition, hourHeight: hourHeight)
        }

        let startDay = calendar.startOfDay(for: segment.task.startDateTime ?? segment.startDate)
        let maxAllowed = min((24 * 60) - snapMinutes, Int(currentEnd.timeIntervalSince(startDay) / 60) - snapMinutes)
        let targetStartMinute = min(max(0, snap(minuteFromYPosition(yPosition + translation.height, hourHeight: hourHeight), to: snapMinutes)), maxAllowed)
        let previewStart = date(on: startDay, minute: targetStartMinute)
        let visibleEnd = min(currentEnd, calendar.date(byAdding: .day, value: 1, to: startDay) ?? currentEnd)
        let previewHeight = max(CGFloat(visibleEnd.timeIntervalSince(previewStart) / 60) / 60 * hourHeight, 20)

        return TimelineCardPreview(
            xPosition: horizontalInset,
            yPosition: CGFloat(targetStartMinute) / 60 * hourHeight,
            height: previewHeight,
            targetDate: startDay,
            targetStartMinute: targetStartMinute,
            targetEndMinute: minuteOfDay(for: currentEnd, calendar: calendar),
            displayStartDate: previewStart,
            displayEndDate: currentEnd
        )
    }

    private static func bottomResizePreview(
        segment: TimelineTaskSegment,
        horizontalInset: CGFloat,
        yPosition: CGFloat,
        cardHeight: CGFloat,
        hourHeight: CGFloat,
        snapMinutes: Int,
        translation: CGSize,
        calendar: Calendar
    ) -> TimelineCardPreview {
        guard let currentStart = segment.task.startDateTime,
              let currentEnd = segment.task.endDateTime
        else {
            return unchangedPreview(segment: segment, horizontalInset: horizontalInset, yPosition: yPosition, hourHeight: hourHeight)
        }

        let endDay = calendar.startOfDay(for: currentEnd)
        let startMinutes = minuteOfDay(for: currentStart, calendar: calendar)
        let minimum = calendar.isDate(currentStart, inSameDayAs: endDay) ? startMinutes + snapMinutes : 0
        let targetEndMinute = max(minimum, min((23 * 60) + 59, snap(minuteFromYPosition(yPosition + cardHeight + translation.height, hourHeight: hourHeight), to: snapMinutes)))
        let previewEnd = date(on: endDay, minute: targetEndMinute)
        let previewHeight = max(CGFloat(previewEnd.timeIntervalSince(segment.startDate) / 60) / 60 * hourHeight, 20)

        return TimelineCardPreview(
            xPosition: horizontalInset,
            yPosition: yPosition,
            height: previewHeight,
            targetDate: endDay,
            targetStartMinute: startMinutes,
            targetEndMinute: targetEndMinute,
            displayStartDate: currentStart,
            displayEndDate: previewEnd
        )
    }

    private static func unchangedPreview(
        segment: TimelineTaskSegment,
        horizontalInset: CGFloat,
        yPosition: CGFloat,
        hourHeight: CGFloat
    ) -> TimelineCardPreview {
        let startMinute = minuteOfDay(for: segment.startDate, calendar: .current)
        let endMinute = segment.displayKind == .range ? minuteOfDay(for: segment.endDate, calendar: .current) : nil
        return TimelineCardPreview(
            xPosition: horizontalInset,
            yPosition: yPosition,
            height: max(CGFloat(segment.endDate.timeIntervalSince(segment.startDate) / 60) / 60 * hourHeight, 20),
            targetDate: segment.displayDate,
            targetStartMinute: startMinute,
            targetEndMinute: endMinute,
            displayStartDate: segment.task.startDateTime ?? segment.startDate,
            displayEndDate: segment.task.endDateTime
        )
    }

    private static func clampedStartMinute(_ minute: Int, snapMinutes: Int) -> Int {
        max(0, min((24 * 60) - snapMinutes, snap(minute, to: snapMinutes)))
    }

    private static func minuteFromYPosition(_ yPosition: CGFloat, hourHeight: CGFloat) -> Int {
        Int(((yPosition / hourHeight) * 60).rounded())
    }

    private static func snap(_ minutes: Int, to step: Int) -> Int {
        Int((Double(minutes) / Double(step)).rounded()) * step
    }

    private static func date(on day: Date, minute: Int) -> Date {
        day.setting(hour: minute / 60, minute: minute % 60) ?? day
    }

    private static func minuteOfDay(for date: Date, calendar: Calendar) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}

private struct TaskTimelineCardContent: View {
    let title: String
    let fullTimeText: String
    let startOnlyTimeText: String
    let width: CGFloat
    let height: CGFloat

    private var layout: LayoutStyle {
        if height >= 52 {
            return .stacked
        }
        if height >= 32 {
            if width >= 116 {
                return .inlineFull
            }
            if width >= 92 {
                return .inlineStartOnly
            }
            return .titleOnly
        }
        if width >= 110 {
            return .inlineFull
        }
        if width >= 88 {
            return .inlineStartOnly
        }
        return .titleOnly
    }

    var body: some View {
        Group {
            switch layout {
            case .stacked:
                VStack(alignment: .leading, spacing: 2) {
                    titleText(lineLimit: height < 68 ? 1 : 2)
                    timeText(fullTimeText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .inlineFull:
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    titleText(lineLimit: 1)
                    Spacer(minLength: 0)
                    timeText(fullTimeText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            case .inlineStartOnly:
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    titleText(lineLimit: 1)
                    Spacer(minLength: 0)
                    timeText(startOnlyTimeText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            case .titleOnly:
                titleText(lineLimit: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private func titleText(lineLimit: Int) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.primary)
            .lineLimit(lineLimit)
            .truncationMode(.tail)
    }

    private func timeText(_ value: String) -> some View {
        Text(value)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private enum LayoutStyle {
        case stacked
        case inlineFull
        case inlineStartOnly
        case titleOnly
    }
}

private struct TimelineTaskSegment: Identifiable {
    enum DisplayKind {
        case point
        case range
    }

    let id: String
    let task: TaskItem
    let displayDate: Date
    let startDate: Date
    let endDate: Date
    let displayKind: DisplayKind
    let canMove: Bool
    let canResizeTop: Bool
    let canResizeBottom: Bool

    static func segments(for task: TaskItem, on date: Date, calendar: Calendar = .current) -> [TimelineTaskSegment] {
        guard let start = task.startDateTime else { return [] }

        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 3600)

        switch task.timingKind {
        case .point:
            guard start >= dayStart && start < dayEnd else { return [] }
            return [
                TimelineTaskSegment(
                    id: "\(task.id.uuidString)-\(dayStart.timeIntervalSinceReferenceDate)-point",
                    task: task,
                    displayDate: dayStart,
                    startDate: start,
                    endDate: start,
                    displayKind: .point,
                    canMove: true,
                    canResizeTop: false,
                    canResizeBottom: false
                )
            ]
        case .range:
            guard let end = task.endDateTime, start < dayEnd, end > dayStart else { return [] }
            let segmentStart = max(start, dayStart)
            let segmentEnd = min(end, dayEnd)
            return [
                TimelineTaskSegment(
                    id: "\(task.id.uuidString)-\(dayStart.timeIntervalSinceReferenceDate)-range",
                    task: task,
                    displayDate: dayStart,
                    startDate: segmentStart,
                    endDate: segmentEnd,
                    displayKind: .range,
                    canMove: calendar.isDate(start, inSameDayAs: dayStart),
                    canResizeTop: calendar.isDate(start, inSameDayAs: dayStart),
                    canResizeBottom: calendar.isDate(end, inSameDayAs: dayStart)
                )
            ]
        case .untimed:
            return []
        }
    }
}

private struct CurrentTimeIndicator: View {
    let hourHeight: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let components = Calendar.current.dateComponents([.hour, .minute], from: context.date)
            let minutes = CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0))

            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
                .offset(y: minutes / 60 * hourHeight)
        }
    }
}

private struct ProjectDeadlineMarker: Identifiable {
    let task: ProjectTask
    let displayDate: Date

    var id: String {
        "\(task.id.uuidString)-\(displayDate.timeIntervalSinceReferenceDate)"
    }
}

private struct ProjectDeadlineCluster: Identifiable {
    struct Item: Identifiable {
        let marker: ProjectDeadlineMarker
        let color: Color
        let rowIndex: Int
        let xOffset: CGFloat
        let labelWidth: CGFloat
        let lineSegmentIndex: Int
        let lineSegmentCount: Int

        var id: String { marker.id }
    }

    let id: String
    let items: [Item]
    let minMinuteOfDay: CGFloat
    let maxMinuteOfDay: CGFloat

    static func makeClusters(from markers: [ProjectDeadlineMarker], columnWidth: CGFloat, hourHeight: CGFloat) -> [ProjectDeadlineCluster] {
        guard !markers.isEmpty else { return [] }

        var clusters: [[ProjectDeadlineMarker]] = []
        var current: [ProjectDeadlineMarker] = []
        let proximityMinutes = 20.0

        for marker in markers {
            if let previous = current.last,
               marker.displayDate.timeIntervalSince(previous.displayDate) / 60 <= proximityMinutes {
                current.append(marker)
            } else {
                if !current.isEmpty { clusters.append(current) }
                current = [marker]
            }
        }
        if !current.isEmpty { clusters.append(current) }

        return clusters.map { markers in
            let availableWidth = max(80, columnWidth - 12)
            let colors = deadlineColors(count: markers.count)

            var rowWidths: [CGFloat] = []
            var rowAssignments: [(rowIndex: Int, xOffset: CGFloat, width: CGFloat)] = []

            for marker in markers.enumerated() {
                let estimatedWidth = min(max(56, estimatedLabelWidth(for: marker.element.task.title)), availableWidth)
                let spacing: CGFloat = rowWidths.isEmpty ? 0 : 8

                var placed = false
                for rowIndex in rowWidths.indices {
                    let currentWidth = rowWidths[rowIndex]
                    let needed = currentWidth == 0 ? estimatedWidth : currentWidth + spacing + estimatedWidth
                    if needed <= availableWidth {
                        let xOffset = currentWidth == 0 ? 0 : currentWidth + spacing
                        rowAssignments.append((rowIndex, xOffset, estimatedWidth))
                        rowWidths[rowIndex] = needed
                        placed = true
                        break
                    }
                }

                if !placed {
                    let rowIndex = rowWidths.count
                    rowWidths.append(estimatedWidth)
                    rowAssignments.append((rowIndex, 0, estimatedWidth))
                }
            }

            let exactGroups = Dictionary(grouping: markers) { $0.displayDate }
            let minutes = markers.map { minuteOfDay(for: $0.displayDate) }
            let items = markers.enumerated().map { index, marker in
                let exactGroup = exactGroups[marker.displayDate, default: [marker]]
                    .sorted { $0.task.createdAt < $1.task.createdAt }
                let lineSegmentIndex = exactGroup.firstIndex(where: { $0.id == marker.id }) ?? 0
                let assignment = rowAssignments[index]

                return Item(
                    marker: marker,
                    color: colors[index],
                    rowIndex: assignment.rowIndex,
                    xOffset: assignment.xOffset,
                    labelWidth: assignment.width,
                    lineSegmentIndex: lineSegmentIndex,
                    lineSegmentCount: exactGroup.count
                )
            }

            return ProjectDeadlineCluster(
                id: markers.map(\.id).joined(separator: "-"),
                items: items,
                minMinuteOfDay: minutes.min() ?? 0,
                maxMinuteOfDay: minutes.max() ?? 0
            )
        }
    }

    private static func minuteOfDay(for date: Date) -> CGFloat {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return CGFloat((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
    }

    private static func estimatedLabelWidth(for title: String) -> CGFloat {
        CGFloat(min(18, max(4, title.count))) * 8 + 18
    }

    private static func deadlineColors(count: Int) -> [Color] {
        let palette: [Color] = [
            .orange, .pink, .mint, .indigo, .teal, .red, .green, .brown, .cyan
        ]
        return (0..<count).map { palette[$0 % palette.count] }
    }
}

private struct ProjectDeadlineClusterView: View {
    let cluster: ProjectDeadlineCluster
    let columnWidth: CGFloat
    let hourHeight: CGFloat

    private let horizontalInset: CGFloat = 5
    private let labelHeight: CGFloat = 22
    private let labelGap: CGFloat = 6

    private var topRows: Int {
        max(1, rowCount - (rowCount > 1 ? 1 : 0))
    }

    private var rowCount: Int {
        (cluster.items.map(\.rowIndex).max() ?? 0) + 1
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(cluster.items) { item in
                lineView(for: item)
            }
            ForEach(cluster.items) { item in
                labelView(for: item)
            }
        }
    }

    private func lineView(for item: ProjectDeadlineCluster.Item) -> some View {
        let minuteOfDay = minute(of: item.marker.displayDate)
        let totalWidth = columnWidth - (horizontalInset * 2)
        let segmentWidth = totalWidth / CGFloat(max(1, item.lineSegmentCount))
        return Rectangle()
            .fill(item.color)
            .frame(width: item.lineSegmentCount > 1 ? segmentWidth : totalWidth, height: 2)
            .offset(
                x: horizontalInset + CGFloat(item.lineSegmentIndex) * segmentWidth,
                y: minuteOfDay / 60 * hourHeight
            )
    }

    private func labelView(for item: ProjectDeadlineCluster.Item) -> some View {
        Text(item.marker.task.title)
            .font(.caption.bold())
            .foregroundStyle(item.color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(width: item.labelWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item.color.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(item.color.opacity(0.4), lineWidth: 1)
            )
            .offset(x: horizontalInset + item.xOffset, y: labelY(for: item))
    }

    private func labelY(for item: ProjectDeadlineCluster.Item) -> CGFloat {
        if rowCount == 1 {
            return (cluster.minMinuteOfDay / 60 * hourHeight) - labelHeight - labelGap
        }

        if item.rowIndex < rowCount - 1 {
            let levelsFromLine = CGFloat((rowCount - 1) - item.rowIndex)
            return (cluster.minMinuteOfDay / 60 * hourHeight) - (levelsFromLine * (labelHeight + 2)) - labelGap
        }

        return (cluster.maxMinuteOfDay / 60 * hourHeight) + labelGap
    }

    private func minute(of date: Date) -> CGFloat {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return CGFloat((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
    }
}
