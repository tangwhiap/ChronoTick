import XCTest
@testable import ChronoTick

final class WorkRestTimerEngineTests: XCTestCase {
    private let defaults = WorkRestSettings(workMinutes: 50, restMinutes: 10)

    func testColdLaunchDuringTaskStartsWorkFromCurrentTime() throws {
        let taskID = UUID()
        let task = snapshot(
            id: taskID,
            title: "Deep work",
            start: date(hour: 9),
            end: date(hour: 12)
        )
        let now = date(hour: 10, minute: 30)
        var engine = WorkRestTimerEngine()

        let state = engine.update(tasks: [task], now: now, defaultSettings: defaults)
        let active = try activePresentation(state)

        XCTAssertEqual(active.phase, .work)
        XCTAssertEqual(active.nextTransitionDate, date(hour: 11, minute: 20))
    }

    func testObservedFutureTaskUsesItsRealStartAndCatchesUpAfterSleep() throws {
        let task = snapshot(
            title: "Observed before start",
            start: date(hour: 9),
            end: date(hour: 12)
        )
        var engine = WorkRestTimerEngine()

        _ = engine.update(tasks: [task], now: date(hour: 8, minute: 55), defaultSettings: defaults)
        let state = engine.update(tasks: [task], now: date(hour: 10, minute: 30), defaultSettings: defaults)
        let active = try activePresentation(state)

        XCTAssertEqual(active.phase, .work)
        XCTAssertEqual(active.nextTransitionDate, date(hour: 10, minute: 50))
    }

    func testAutomaticWorkRestCycleUsesDefaultDurations() throws {
        let task = snapshot(
            title: "Cycle",
            start: date(hour: 9),
            end: date(hour: 12)
        )
        var engine = WorkRestTimerEngine()
        _ = engine.update(tasks: [task], now: date(hour: 9), defaultSettings: defaults)

        var active = try activePresentation(
            engine.update(tasks: [task], now: date(hour: 9, minute: 50), defaultSettings: defaults)
        )
        XCTAssertEqual(active.phase, .rest)
        XCTAssertEqual(active.nextTransitionDate, date(hour: 10))

        active = try activePresentation(
            engine.update(tasks: [task], now: date(hour: 10), defaultSettings: defaults)
        )
        XCTAssertEqual(active.phase, .work)
        XCTAssertEqual(active.nextTransitionDate, date(hour: 10, minute: 50))
    }

    func testTaskDeadlineTruncatesCountdownAndSuppressesTransitionPlan() throws {
        let task = snapshot(
            title: "Short task",
            start: date(hour: 9),
            end: date(hour: 9, minute: 30)
        )
        var engine = WorkRestTimerEngine()

        let state = engine.update(tasks: [task], now: date(hour: 9), defaultSettings: defaults)
        let active = try activePresentation(state)

        XCTAssertEqual(active.countdownEndDate, task.endDate)
        XCTAssertEqual(active.countdownKind, .taskEnd)
        XCTAssertNil(state.notificationPlan)
    }

    func testManualCommandsReplaceOnlyCurrentSessionTiming() throws {
        let task = snapshot(
            title: "Manual controls",
            start: date(hour: 9),
            end: date(hour: 14)
        )
        var engine = WorkRestTimerEngine()
        _ = engine.update(tasks: [task], now: date(hour: 9), defaultSettings: defaults)

        XCTAssertTrue(engine.switchNow(at: date(hour: 9, minute: 10)))
        var active = try activePresentation(
            engine.update(tasks: [task], now: date(hour: 9, minute: 10), defaultSettings: defaults)
        )
        XCTAssertEqual(active.phase, .rest)
        XCTAssertEqual(active.nextTransitionDate, date(hour: 9, minute: 20))

        XCTAssertTrue(engine.switchAfter(minutes: 7, now: date(hour: 9, minute: 12)))
        active = try activePresentation(
            engine.update(tasks: [task], now: date(hour: 9, minute: 12), defaultSettings: defaults)
        )
        XCTAssertEqual(active.phase, .rest)
        XCTAssertEqual(active.nextTransitionDate, date(hour: 9, minute: 19))

        XCTAssertTrue(engine.applyDurations(workMinutes: 25, restMinutes: 5, now: date(hour: 9, minute: 13)))
        active = try activePresentation(
            engine.update(tasks: [task], now: date(hour: 9, minute: 13), defaultSettings: defaults)
        )
        XCTAssertEqual(active.phase, .work)
        XCTAssertEqual(active.workMinutes, 25)
        XCTAssertEqual(active.restMinutes, 5)
        XCTAssertEqual(active.nextTransitionDate, date(hour: 9, minute: 38))
    }

    func testMostRecentlyStartedOverlappingTaskWins() throws {
        let earlier = snapshot(
            title: "Earlier",
            start: date(hour: 9),
            end: date(hour: 12)
        )
        let later = snapshot(
            title: "Later",
            start: date(hour: 10),
            end: date(hour: 11)
        )
        var engine = WorkRestTimerEngine()

        let state = engine.update(
            tasks: [earlier, later],
            now: date(hour: 10, minute: 15),
            defaultSettings: defaults
        )

        XCTAssertEqual(try activePresentation(state).task.id, later.id)
    }

    func testCompletionMistakeRestoresOriginalWallClockSession() throws {
        let id = UUID()
        let task = snapshot(
            id: id,
            title: "Mistaken completion",
            start: date(hour: 10),
            end: date(hour: 12)
        )
        var engine = WorkRestTimerEngine()

        _ = engine.update(tasks: [task], now: date(hour: 10), defaultSettings: defaults)
        let completed = snapshot(
            id: id,
            title: task.title,
            start: task.startDate,
            end: task.endDate,
            isCompleted: true
        )
        let completedState = engine.update(
            tasks: [completed],
            now: date(hour: 10, minute: 20),
            defaultSettings: defaults
        )
        XCTAssertFalse(completedState.hasActiveTask)

        let restoredState = engine.update(
            tasks: [task],
            now: date(hour: 10, minute: 25),
            defaultSettings: defaults
        )
        let active = try activePresentation(restoredState)

        XCTAssertEqual(active.phase, .work)
        XCTAssertEqual(active.nextTransitionDate, date(hour: 10, minute: 50))
    }

    func testRenameAndPastStartEditDoNotResetSameTaskSession() throws {
        let id = UUID()
        let original = snapshot(
            id: id,
            title: "Original",
            start: date(hour: 10),
            end: date(hour: 12)
        )
        var engine = WorkRestTimerEngine()
        _ = engine.update(tasks: [original], now: date(hour: 10, minute: 5), defaultSettings: defaults)

        let edited = snapshot(
            id: id,
            title: "Renamed",
            start: date(hour: 9),
            end: date(hour: 12)
        )
        let state = engine.update(
            tasks: [edited],
            now: date(hour: 10, minute: 15),
            defaultSettings: defaults
        )
        let active = try activePresentation(state)

        XCTAssertEqual(active.task.title, "Renamed")
        XCTAssertEqual(active.nextTransitionDate, date(hour: 10, minute: 55))
    }

    func testMovingCurrentTaskIntoFutureStopsSessionAndShowsItAsNext() throws {
        let id = UUID()
        let current = snapshot(
            id: id,
            title: "Move me",
            start: date(hour: 10),
            end: date(hour: 12)
        )
        var engine = WorkRestTimerEngine()
        _ = engine.update(tasks: [current], now: date(hour: 10, minute: 5), defaultSettings: defaults)

        let future = snapshot(
            id: id,
            title: current.title,
            start: date(hour: 11),
            end: date(hour: 13)
        )
        let state = engine.update(
            tasks: [future],
            now: date(hour: 10, minute: 10),
            defaultSettings: defaults
        )

        guard case let .idle(idle) = state else {
            return XCTFail("Expected idle state")
        }
        XCTAssertEqual(idle.nextTask?.id, id)
    }

    func testDeletionStopsCurrentSession() {
        let current = snapshot(
            title: "Delete me",
            start: date(hour: 10),
            end: date(hour: 12)
        )
        var engine = WorkRestTimerEngine()
        _ = engine.update(tasks: [current], now: date(hour: 10, minute: 5), defaultSettings: defaults)

        let state = engine.update(
            tasks: [],
            now: date(hour: 10, minute: 6),
            defaultSettings: defaults
        )

        XCTAssertFalse(state.hasActiveTask)
        XCTAssertNil(engine.session)
    }

    func testDeadlineExtensionKeepsOriginalTransition() throws {
        let id = UUID()
        let original = snapshot(
            id: id,
            title: "Extend me",
            start: date(hour: 10),
            end: date(hour: 10, minute: 30)
        )
        var engine = WorkRestTimerEngine()
        _ = engine.update(tasks: [original], now: date(hour: 10), defaultSettings: defaults)

        let extended = snapshot(
            id: id,
            title: original.title,
            start: original.startDate,
            end: date(hour: 12)
        )
        let state = engine.update(
            tasks: [extended],
            now: date(hour: 10, minute: 10),
            defaultSettings: defaults
        )
        let active = try activePresentation(state)

        XCTAssertEqual(active.phase, .work)
        XCTAssertEqual(active.nextTransitionDate, date(hour: 10, minute: 50))
        XCTAssertEqual(active.countdownKind, .phaseTransition(to: .rest))
    }

    func testSettingsStoreUsesDefaultsAndPersistsValidatedValues() {
        let suiteName = "WorkRestSettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WorkRestSettingsStore(defaults: defaults)
        XCTAssertEqual(store.defaultWorkMinutes, 50)
        XCTAssertEqual(store.defaultRestMinutes, 10)

        store.setDefaultWorkMinutes(35)
        store.setDefaultRestMinutes(8)

        let reloaded = WorkRestSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.defaultWorkMinutes, 35)
        XCTAssertEqual(reloaded.defaultRestMinutes, 8)
    }

    func testNotificationPlanTargetsOnlyNextPhaseTransition() throws {
        let task = snapshot(
            title: "Notify",
            start: date(hour: 9),
            end: date(hour: 12)
        )
        var engine = WorkRestTimerEngine()
        let state = engine.update(tasks: [task], now: date(hour: 9), defaultSettings: defaults)
        let plan = try XCTUnwrap(state.notificationPlan)

        XCTAssertEqual(plan.taskID, task.id)
        XCTAssertEqual(plan.nextPhase, .rest)
        XCTAssertEqual(plan.fireDate, date(hour: 9, minute: 50))
    }

    private func activePresentation(
        _ state: WorkRestPresentationState
    ) throws -> WorkRestActivePresentation {
        guard case let .active(active) = state else {
            throw TestError.expectedActiveState
        }
        return active
    }

    private func snapshot(
        id: UUID = UUID(),
        title: String,
        start: Date,
        end: Date,
        isCompleted: Bool = false
    ) -> WorkRestTaskSnapshot {
        WorkRestTaskSnapshot(
            id: id,
            title: title,
            startDate: start,
            endDate: end,
            isCompleted: isCompleted
        )
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        Calendar.chronoTick.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 15,
                hour: hour,
                minute: minute
            )
        )!
    }

    private enum TestError: Error {
        case expectedActiveState
    }
}
