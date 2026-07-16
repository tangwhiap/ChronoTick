import AppKit
import SwiftUI
import WidgetKit

private struct WorkRestWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WorkRestWidgetSnapshot
    let appearance: WorkRestWidgetAppearanceSnapshot
    let backgroundImageURL: URL?
    let isBoundaryEntry: Bool
}

private struct WorkRestWidgetProvider: TimelineProvider {
    private let store = WorkRestWidgetStateStore()

    func placeholder(in context: Context) -> WorkRestWidgetEntry {
        WorkRestWidgetEntry(
            date: .now,
            snapshot: Self.previewSnapshot,
            appearance: .fallback,
            backgroundImageURL: nil,
            isBoundaryEntry: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkRestWidgetEntry) -> Void) {
        completion(entry(at: .now, usePreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkRestWidgetEntry>) -> Void) {
        let now = Date.now
        let entry = entry(at: now, usePreview: false)
        guard let endDate = entry.snapshot.countdownEndDate, endDate > now else {
            completion(Timeline(entries: [entry], policy: .never))
            return
        }

        let boundaryEntry = WorkRestWidgetEntry(
            date: endDate,
            snapshot: entry.snapshot,
            appearance: entry.appearance,
            backgroundImageURL: entry.backgroundImageURL,
            isBoundaryEntry: true
        )
        completion(
            Timeline(
                entries: [entry, boundaryEntry],
                policy: .after(endDate.addingTimeInterval(1))
            )
        )
    }

    private func entry(at date: Date, usePreview: Bool) -> WorkRestWidgetEntry {
        let appearance = usePreview ? WorkRestWidgetAppearanceSnapshot.fallback : store.readAppearance()
        let backgroundImageURL = appearance.backgroundImageFilename.flatMap {
            store.appearanceAssetURL(filename: $0)
        }
        return WorkRestWidgetEntry(
            date: date,
            snapshot: usePreview ? Self.previewSnapshot : store.read() ?? .unavailable,
            appearance: appearance,
            backgroundImageURL: backgroundImageURL,
            isBoundaryEntry: false
        )
    }

    private static var previewSnapshot: WorkRestWidgetSnapshot {
        let now = Date.now
        return WorkRestWidgetSnapshot(
            mode: .active,
            taskID: UUID(),
            taskTitle: "整理今天的工作计划",
            taskStartDate: now.addingTimeInterval(-30 * 60),
            taskEndDate: now.addingTimeInterval(90 * 60),
            phaseTitle: "工作中",
            accent: .work,
            countdownEndDate: now.addingTimeInterval(20 * 60),
            countdownLabel: "距离休息"
        )
    }
}

private struct WorkRestWidgetView: View {
    let entry: WorkRestWidgetEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 4) {
                switch entry.snapshot.mode {
                case .active:
                    taskHeader(maximumTitleWidth: geometry.size.width * 0.618)
                    Text(entry.snapshot.phaseTitle ?? "")
                        .font(.subheadline.bold())
                        .foregroundStyle(accentColor)
                    countdown
                    targetLabel
                case .upcoming:
                    taskHeader(maximumTitleWidth: geometry.size.width * 0.618)
                    Text("下一项时间段任务")
                        .font(.subheadline.bold())
                        .foregroundStyle(secondaryTextColor)
                    countdown
                    targetLabel
                case .empty:
                    Label("没有即将开始的时间段任务", systemImage: "clock")
                        .font(.headline)
                    Text("时间点任务和无时间任务不参与工作/休息计时。")
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                case .unavailable:
                    Label("ChronoTick 未运行", systemImage: "clock.badge.exclamationmark")
                        .font(.headline)
                    Text("打开 ChronoTick 后，Widget 会自动同步当前计时。")
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(primaryTextColor)
        .shadow(color: contentShadowColor, radius: 1, y: 1)
        .containerBackground(for: .widget) {
            widgetBackground
        }
    }

    @ViewBuilder
    private func taskHeader(maximumTitleWidth: CGFloat) -> some View {
        Text(entry.snapshot.taskTitle ?? "")
            .font(.subheadline.weight(.semibold))
            .lineLimit(3)
            .minimumScaleFactor(0.86)
            .frame(maxWidth: maximumTitleWidth, alignment: .leading)
            .layoutPriority(2)
        if let startDate = entry.snapshot.taskStartDate,
           let endDate = entry.snapshot.taskEndDate {
            Text(Self.timeRangeText(from: startDate, to: endDate))
                .font(.caption)
                .foregroundStyle(secondaryTextColor)
        }
    }

    @ViewBuilder
    private var countdown: some View {
        if let endDate = entry.snapshot.countdownEndDate,
           endDate > entry.date,
           !entry.isBoundaryEntry {
            Text(endDate, style: .timer)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .layoutPriority(2)
        } else if entry.snapshot.countdownEndDate != nil {
            Text("00:00:00")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("等待 ChronoTick 同步")
                .font(.caption2)
                .foregroundStyle(secondaryTextColor)
        }
    }

    @ViewBuilder
    private var targetLabel: some View {
        if let label = entry.snapshot.countdownLabel,
           let endDate = entry.snapshot.countdownEndDate {
            Text("\(label) · \(Self.targetTimeText(endDate, relativeTo: entry.date))")
                .font(.caption)
                .foregroundStyle(secondaryTextColor)
        }
    }

    private var accentColor: Color {
        switch entry.snapshot.accent {
        case .work: return Color(widgetHex: entry.appearance.themeHex) ?? .accentColor
        case .rest: return .green
        case .neutral: return secondaryTextColor
        }
    }

    private var usesThemeImage: Bool {
        renderingMode == .fullColor && entry.backgroundImageURL != nil
    }

    private var primaryTextColor: Color {
        guard renderingMode == .fullColor else { return .primary }
        return entry.appearance.textColorRawValue == "white" ? .white : .black
    }

    private var secondaryTextColor: Color {
        guard renderingMode == .fullColor else { return .secondary }
        return primaryTextColor.opacity(entry.appearance.textColorRawValue == "white" ? 0.78 : 0.62)
    }

    private var contentShadowColor: Color {
        guard usesThemeImage else { return .clear }
        return entry.appearance.textColorRawValue == "white"
            ? .black.opacity(0.3)
            : .white.opacity(0.4)
    }

    @ViewBuilder
    private var widgetBackground: some View {
        if renderingMode == .fullColor,
           let backgroundImageURL = entry.backgroundImageURL,
           let image = NSImage(contentsOf: backgroundImageURL) {
            GeometryReader { geometry in
                ZStack {
                    WidgetFocalCroppedImage(
                        image: image,
                        cropX: entry.appearance.backgroundCropX,
                        cropY: entry.appearance.backgroundCropY,
                        cropZoom: entry.appearance.backgroundCropZoom
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)

                    Color.white.opacity(entry.appearance.backgroundFogOpacity)

                    LinearGradient(
                        colors: readabilityGradientColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
        } else {
            LinearGradient(
                colors: [
                    Color(widgetHex: entry.appearance.sidebarThemeHex) ?? Color(nsColor: .windowBackgroundColor),
                    (Color(widgetHex: entry.appearance.themeHex) ?? .accentColor).opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var readabilityGradientColors: [Color] {
        if entry.appearance.textColorRawValue == "white" {
            return [.black.opacity(0.5), .black.opacity(0.16), .clear]
        }
        return [.white.opacity(0.72), .white.opacity(0.2), .clear]
    }

    private static func timeRangeText(from startDate: Date, to endDate: Date) -> String {
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            return "\(startDate.formatted(date: .omitted, time: .shortened))–\(endDate.formatted(date: .omitted, time: .shortened))"
        }
        return "\(startDate.formatted(date: .abbreviated, time: .shortened)) – \(endDate.formatted(date: .abbreviated, time: .shortened))"
    }

    private static func targetTimeText(_ date: Date, relativeTo now: Date) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month().day().hour().minute())
    }
}

private struct WidgetFocalCroppedImage: View {
    let image: NSImage
    let cropX: Double
    let cropY: Double
    let cropZoom: Double

    var body: some View {
        GeometryReader { geometry in
            let imageSize = image.size
            let containerSize = geometry.size
            let zoom = min(max(cropZoom, 1), 4)
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
                    x: -overflowX * CGFloat(min(max(cropX, 0), 1)),
                    y: -overflowY * CGFloat(min(max(cropY, 0), 1))
                )
                .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
                .clipped()
        }
    }
}

private extension Color {
    init?(widgetHex: String) {
        let cleaned = widgetHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

@main
struct ChronoTickWorkRestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WorkRestWidgetStateStore.widgetKind,
            provider: WorkRestWidgetProvider()
        ) { entry in
            WorkRestWidgetView(entry: entry)
        }
        .configurationDisplayName("ChronoTick 工作/休息")
        .description("显示当前工作或休息阶段以及实时倒计时。")
        .supportedFamilies([.systemMedium])
    }
}
