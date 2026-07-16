import AppKit
import XCTest
@testable import ChronoTick

final class WorkRestWidgetStateTests: XCTestCase {
    func testStoreRoundTripsSnapshot() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WorkRestWidgetStateStore(defaults: defaults)
        let endDate = Date(timeIntervalSinceReferenceDate: 12_345)
        let snapshot = WorkRestWidgetSnapshot(
            mode: .active,
            taskID: UUID(),
            taskTitle: "Write tests",
            taskStartDate: endDate.addingTimeInterval(-3_600),
            taskEndDate: endDate.addingTimeInterval(3_600),
            phaseTitle: "工作中",
            accent: .work,
            countdownEndDate: endDate,
            countdownLabel: "距离休息"
        )

        XCTAssertTrue(store.write(snapshot))
        XCTAssertEqual(store.read(), snapshot)
    }

    func testStoreRoundTripsAppearanceSnapshot() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WorkRestWidgetStateStore(defaults: defaults)
        let appearance = WorkRestWidgetAppearanceSnapshot(
            themeHex: "#123456",
            sidebarThemeHex: "#F0F0F0",
            textColorRawValue: "white",
            backgroundCropX: 0.2,
            backgroundCropY: 0.7,
            backgroundCropZoom: 1.4,
            backgroundFogOpacity: 0.08,
            backgroundImageFilename: "theme.jpg",
            backgroundResourceVersion: UUID()
        )

        XCTAssertTrue(store.writeAppearance(appearance))
        XCTAssertEqual(store.readAppearance(), appearance)
    }

    func testPublisherDoesNotRewriteWhenOnlyPresentationNowChanges() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var reloadCount = 0
        let publisher = WorkRestWidgetPublisher(
            store: WorkRestWidgetStateStore(defaults: defaults)
        ) {
            reloadCount += 1
        }
        let first = activeState(now: Date(timeIntervalSinceReferenceDate: 1_000))
        let second = activeState(now: Date(timeIntervalSinceReferenceDate: 1_001))

        XCTAssertTrue(publisher.publish(first))
        XCTAssertFalse(publisher.publish(second))
        XCTAssertEqual(reloadCount, 1)
    }

    func testActiveSnapshotUsesClampedCountdownAndPhaseLabel() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let state = activeState(now: now)
        let snapshot = WorkRestWidgetPublisher.snapshot(from: state)

        XCTAssertEqual(snapshot.mode, .active)
        XCTAssertEqual(snapshot.phaseTitle, "工作中")
        XCTAssertEqual(snapshot.accent, .work)
        XCTAssertEqual(snapshot.countdownLabel, "距离休息")
        XCTAssertEqual(snapshot.countdownEndDate, now.addingTimeInterval(600))
    }

    func testIdleSnapshotDistinguishesUpcomingAndEmpty() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let future = WorkRestTaskSnapshot(
            id: UUID(),
            title: "Future task",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(1_200),
            isCompleted: false
        )

        let upcoming = WorkRestWidgetPublisher.snapshot(
            from: .idle(WorkRestIdlePresentation(nextTask: future, now: now))
        )
        let empty = WorkRestWidgetPublisher.snapshot(
            from: .idle(WorkRestIdlePresentation(nextTask: nil, now: now))
        )

        XCTAssertEqual(upcoming.mode, .upcoming)
        XCTAssertEqual(upcoming.countdownEndDate, future.startDate)
        XCTAssertEqual(upcoming.countdownLabel, "距离任务开始")
        XCTAssertEqual(empty, .empty)
    }

    @MainActor
    func testAppearancePublisherReplacesAssetOnlyForChangedTheme() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkRestWidgetAppearanceTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let sourceURL = containerURL.appendingPathComponent("source.png")
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        try Data([1]).write(to: sourceURL)

        let store = WorkRestWidgetStateStore(
            defaults: defaults,
            appGroupContainerURL: containerURL
        )
        var renderCount = 0
        var reloadCount = 0
        let publisher = WorkRestWidgetAppearancePublisher(
            store: store,
            debounceNanoseconds: 1,
            renderBackground: { _, destinationURL in
                renderCount += 1
                try Data([2, 3, 4]).write(to: destinationURL, options: .atomic)
            },
            reloadWidget: { reloadCount += 1 }
        )
        let first = themeSource(path: sourceURL.path, themeHex: "#111111")

        XCTAssertTrue(publisher.publishNow(first))
        let firstAppearance = store.readAppearance()
        let firstFilename = try XCTUnwrap(firstAppearance.backgroundImageFilename)
        let firstURL = try XCTUnwrap(store.appearanceAssetURL(filename: firstFilename))
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertFalse(publisher.publishNow(first))

        XCTAssertTrue(publisher.publishNow(themeSource(path: sourceURL.path, themeHex: "#222222")))
        let secondAppearance = store.readAppearance()
        let secondFilename = try XCTUnwrap(secondAppearance.backgroundImageFilename)
        let secondURL = try XCTUnwrap(store.appearanceAssetURL(filename: secondFilename))
        XCTAssertNotEqual(firstFilename, secondFilename)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertEqual(renderCount, 2)
        XCTAssertEqual(reloadCount, 2)
    }

    @MainActor
    func testAppearancePublisherDebouncesRapidThemeChanges() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkRestWidgetDebounceTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let sourceURL = containerURL.appendingPathComponent("source.png")
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        try Data([1]).write(to: sourceURL)

        let store = WorkRestWidgetStateStore(
            defaults: defaults,
            appGroupContainerURL: containerURL
        )
        var renderCount = 0
        var reloadCount = 0
        let publisher = WorkRestWidgetAppearancePublisher(
            store: store,
            debounceNanoseconds: 20_000_000,
            renderBackground: { _, destinationURL in
                renderCount += 1
                try Data([5]).write(to: destinationURL, options: .atomic)
            },
            reloadWidget: { reloadCount += 1 }
        )

        publisher.schedulePublish(themeSource(path: sourceURL.path, themeHex: "#111111"))
        publisher.schedulePublish(themeSource(path: sourceURL.path, themeHex: "#222222"))
        publisher.schedulePublish(themeSource(path: sourceURL.path, themeHex: "#333333"))
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.readAppearance().themeHex, "#333333")
        XCTAssertEqual(renderCount, 1)
        XCTAssertEqual(reloadCount, 1)
    }

    @MainActor
    func testAppearancePublisherFallsBackWhenThereIsNoBackground() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WorkRestWidgetStateStore(defaults: defaults)
        var reloadCount = 0
        let publisher = WorkRestWidgetAppearancePublisher(
            store: store,
            renderBackground: { _, _ in XCTFail("No image should be rendered") },
            reloadWidget: { reloadCount += 1 }
        )

        XCTAssertTrue(publisher.publishNow(themeSource(path: nil, themeHex: "#ABCDEF")))
        XCTAssertNil(store.readAppearance().backgroundImageFilename)
        XCTAssertEqual(store.readAppearance().themeHex, "#ABCDEF")
        XCTAssertEqual(reloadCount, 1)
    }

    @MainActor
    func testOptimizedBackgroundRendererCreatesReadableJPEG() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkRestWidgetRendererTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("source.png")
        let destinationURL = directoryURL.appendingPathComponent("result.jpg")

        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 24,
            pixelsHigh: 12,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.setColor(NSColor(calibratedRed: 0.1, green: 0.4, blue: 0.9, alpha: 1), atX: 4, y: 4)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: sourceURL)

        try WorkRestWidgetAppearancePublisher.renderOptimizedBackground(
            sourceURL: sourceURL,
            destinationURL: destinationURL
        )

        let rendered = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: destinationURL)))
        XCTAssertEqual(rendered.pixelsWide, 24)
        XCTAssertEqual(rendered.pixelsHigh, 12)
    }

    private func activeState(now: Date) -> WorkRestPresentationState {
        let taskStartDate = Date(timeIntervalSinceReferenceDate: 400)
        let taskEndDate = Date(timeIntervalSinceReferenceDate: 4_600)
        let transitionDate = Date(timeIntervalSinceReferenceDate: 1_600)
        let task = WorkRestTaskSnapshot(
            id: UUID(uuidString: "A3D7D51F-586B-4B30-90B6-85CDBDB925D7")!,
            title: "Current task",
            startDate: taskStartDate,
            endDate: taskEndDate,
            isCompleted: false
        )
        return .active(
            WorkRestActivePresentation(
                task: task,
                phase: .work,
                workMinutes: 50,
                restMinutes: 10,
                nextTransitionDate: transitionDate,
                countdownEndDate: transitionDate,
                countdownKind: .phaseTransition(to: .rest),
                now: now
            )
        )
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "WorkRestWidgetStateTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func themeSource(path: String?, themeHex: String) -> WorkRestWidgetThemeSource {
        WorkRestWidgetThemeSource(
            themeHex: themeHex,
            sidebarThemeHex: "#F4F4F6",
            textColorRawValue: "black",
            backgroundImagePath: path,
            backgroundCropX: 0.5,
            backgroundCropY: 0.5,
            backgroundCropZoom: 1,
            backgroundFogOpacity: 0.12
        )
    }
}
