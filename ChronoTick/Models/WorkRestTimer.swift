import Foundation

enum WorkRestPhase: String, Equatable {
    case work
    case rest

    var next: WorkRestPhase {
        self == .work ? .rest : .work
    }

    var title: String {
        self == .work ? "工作中" : "休息中"
    }
}

struct WorkRestSettings: Equatable {
    static let defaultWorkMinutes = 50
    static let defaultRestMinutes = 10
    static let validMinuteRange = 1...1_440

    let workMinutes: Int
    let restMinutes: Int

    init(workMinutes: Int, restMinutes: Int) {
        self.workMinutes = Self.validMinuteRange.contains(workMinutes) ? workMinutes : Self.defaultWorkMinutes
        self.restMinutes = Self.validMinuteRange.contains(restMinutes) ? restMinutes : Self.defaultRestMinutes
    }
}

struct WorkRestTaskSnapshot: Identifiable, Equatable {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date
    let isCompleted: Bool

    var isValidRange: Bool {
        endDate > startDate
    }
}

struct WorkRestSession: Equatable {
    let taskID: UUID
    var phase: WorkRestPhase
    var nextTransitionDate: Date
    var workMinutes: Int
    var restMinutes: Int

    func durationMinutes(for phase: WorkRestPhase) -> Int {
        phase == .work ? workMinutes : restMinutes
    }
}

enum WorkRestCountdownKind: Equatable {
    case phaseTransition(to: WorkRestPhase)
    case taskEnd
}

struct WorkRestActivePresentation: Equatable {
    let task: WorkRestTaskSnapshot
    let phase: WorkRestPhase
    let workMinutes: Int
    let restMinutes: Int
    let nextTransitionDate: Date
    let countdownEndDate: Date
    let countdownKind: WorkRestCountdownKind
    let now: Date
}

struct WorkRestIdlePresentation: Equatable {
    let nextTask: WorkRestTaskSnapshot?
    let now: Date
}

struct WorkRestNotificationPlan: Equatable {
    let taskID: UUID
    let taskTitle: String
    let nextPhase: WorkRestPhase
    let fireDate: Date
}

enum WorkRestPresentationState: Equatable {
    case idle(WorkRestIdlePresentation)
    case active(WorkRestActivePresentation)

    var hasActiveTask: Bool {
        if case .active = self { return true }
        return false
    }

    var notificationPlan: WorkRestNotificationPlan? {
        guard case let .active(presentation) = self,
              case let .phaseTransition(nextPhase) = presentation.countdownKind,
              presentation.nextTransitionDate > presentation.now
        else {
            return nil
        }

        return WorkRestNotificationPlan(
            taskID: presentation.task.id,
            taskTitle: presentation.task.title,
            nextPhase: nextPhase,
            fireDate: presentation.nextTransitionDate
        )
    }
}

/// Pure, in-memory work/rest timing logic.
///
/// The engine never writes tasks or stores a historical schedule. It receives current task
/// snapshots and absolute wall-clock time, then derives the one active session and the next
/// transition. This keeps background ticking, task edits, and wake-from-sleep reconciliation
/// deterministic and independently testable.
struct WorkRestTimerEngine {
    private(set) var session: WorkRestSession?
    private(set) var suspendedCompletedSession: WorkRestSession?
    private var lastEvaluationDate: Date?
    private var previousTasksByID: [UUID: WorkRestTaskSnapshot] = [:]

    mutating func update(
        tasks: [WorkRestTaskSnapshot],
        now: Date,
        defaultSettings: WorkRestSettings
    ) -> WorkRestPresentationState {
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        pruneSuspendedSession(using: tasksByID, now: now)
        preserveCompletedSessionIfNeeded(using: tasksByID, now: now)

        let currentTask = Self.currentTask(from: tasks, now: now)

        if let currentTask {
            if session?.taskID != currentTask.id {
                if suspendedCompletedSession?.taskID == currentTask.id {
                    session = suspendedCompletedSession
                    suspendedCompletedSession = nil
                } else {
                    session = makeSession(
                        for: currentTask,
                        now: now,
                        defaultSettings: defaultSettings
                    )
                }
            }

            if var activeSession = session {
                advance(&activeSession, through: now, taskEndDate: currentTask.endDate)
                session = activeSession
            }
        } else {
            session = nil
        }

        let presentation = makePresentation(
            currentTask: currentTask,
            allTasks: tasks,
            now: now
        )

        lastEvaluationDate = now
        previousTasksByID = tasksByID
        return presentation
    }

    @discardableResult
    mutating func applyDurations(workMinutes: Int, restMinutes: Int, now: Date) -> Bool {
        guard WorkRestSettings.validMinuteRange.contains(workMinutes),
              WorkRestSettings.validMinuteRange.contains(restMinutes),
              var activeSession = session
        else {
            return false
        }

        activeSession.workMinutes = workMinutes
        activeSession.restMinutes = restMinutes
        activeSession.phase = .work
        activeSession.nextTransitionDate = now.addingTimeInterval(TimeInterval(workMinutes * 60))
        session = activeSession
        return true
    }

    @discardableResult
    mutating func switchNow(at now: Date) -> Bool {
        guard var activeSession = session else { return false }
        activeSession.phase = activeSession.phase.next
        let minutes = activeSession.durationMinutes(for: activeSession.phase)
        activeSession.nextTransitionDate = now.addingTimeInterval(TimeInterval(minutes * 60))
        session = activeSession
        return true
    }

    @discardableResult
    mutating func switchAfter(minutes: Int, now: Date) -> Bool {
        guard WorkRestSettings.validMinuteRange.contains(minutes),
              var activeSession = session
        else {
            return false
        }

        activeSession.nextTransitionDate = now.addingTimeInterval(TimeInterval(minutes * 60))
        session = activeSession
        return true
    }

    private mutating func pruneSuspendedSession(
        using tasksByID: [UUID: WorkRestTaskSnapshot],
        now: Date
    ) {
        guard let suspendedCompletedSession else { return }
        guard let task = tasksByID[suspendedCompletedSession.taskID],
              task.isValidRange,
              task.startDate <= now,
              now < task.endDate
        else {
            self.suspendedCompletedSession = nil
            return
        }
    }

    private mutating func preserveCompletedSessionIfNeeded(
        using tasksByID: [UUID: WorkRestTaskSnapshot],
        now: Date
    ) {
        guard let activeSession = session else { return }
        guard let task = tasksByID[activeSession.taskID],
              task.isValidRange,
              task.startDate <= now,
              now < task.endDate
        else {
            session = nil
            return
        }

        if task.isCompleted {
            suspendedCompletedSession = activeSession
            session = nil
        }
    }

    private func makeSession(
        for task: WorkRestTaskSnapshot,
        now: Date,
        defaultSettings: WorkRestSettings
    ) -> WorkRestSession {
        let activationDate: Date
        if let previousTask = previousTasksByID[task.id],
           previousTask.startDate == task.startDate,
           let lastEvaluationDate,
           lastEvaluationDate < task.startDate,
           task.startDate <= now {
            // The app observed this task before it naturally began, so the session is anchored to
            // the real start even when a delayed timer tick or system sleep crosses the boundary.
            activationDate = task.startDate
        } else {
            // Cold launch, newly-created tasks, and tasks moved into the present all start now.
            activationDate = now
        }

        return WorkRestSession(
            taskID: task.id,
            phase: .work,
            nextTransitionDate: activationDate.addingTimeInterval(TimeInterval(defaultSettings.workMinutes * 60)),
            workMinutes: defaultSettings.workMinutes,
            restMinutes: defaultSettings.restMinutes
        )
    }

    private func advance(
        _ session: inout WorkRestSession,
        through now: Date,
        taskEndDate: Date
    ) {
        while session.nextTransitionDate <= now,
              session.nextTransitionDate < taskEndDate {
            session.phase = session.phase.next
            let minutes = session.durationMinutes(for: session.phase)
            session.nextTransitionDate = session.nextTransitionDate.addingTimeInterval(TimeInterval(minutes * 60))
        }
    }

    private func makePresentation(
        currentTask: WorkRestTaskSnapshot?,
        allTasks: [WorkRestTaskSnapshot],
        now: Date
    ) -> WorkRestPresentationState {
        guard let currentTask,
              let session,
              session.taskID == currentTask.id
        else {
            return .idle(
                WorkRestIdlePresentation(
                    nextTask: Self.nextTask(from: allTasks, now: now),
                    now: now
                )
            )
        }

        let transitionsBeforeTaskEnd = session.nextTransitionDate < currentTask.endDate
        let countdownKind: WorkRestCountdownKind = transitionsBeforeTaskEnd
            ? .phaseTransition(to: session.phase.next)
            : .taskEnd
        let countdownEndDate = min(session.nextTransitionDate, currentTask.endDate)

        return .active(
            WorkRestActivePresentation(
                task: currentTask,
                phase: session.phase,
                workMinutes: session.workMinutes,
                restMinutes: session.restMinutes,
                nextTransitionDate: session.nextTransitionDate,
                countdownEndDate: countdownEndDate,
                countdownKind: countdownKind,
                now: now
            )
        )
    }

    private static func currentTask(
        from tasks: [WorkRestTaskSnapshot],
        now: Date
    ) -> WorkRestTaskSnapshot? {
        tasks
            .filter {
                !$0.isCompleted &&
                    $0.isValidRange &&
                    $0.startDate <= now &&
                    now < $0.endDate
            }
            .sorted(by: currentTaskSort)
            .first
    }

    private static func nextTask(
        from tasks: [WorkRestTaskSnapshot],
        now: Date
    ) -> WorkRestTaskSnapshot? {
        tasks
            .filter {
                !$0.isCompleted &&
                    $0.isValidRange &&
                    $0.startDate > now
            }
            .sorted(by: nextTaskSort)
            .first
    }

    private static func currentTaskSort(
        _ lhs: WorkRestTaskSnapshot,
        _ rhs: WorkRestTaskSnapshot
    ) -> Bool {
        if lhs.startDate != rhs.startDate {
            return lhs.startDate > rhs.startDate
        }
        if lhs.endDate != rhs.endDate {
            return lhs.endDate < rhs.endDate
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func nextTaskSort(
        _ lhs: WorkRestTaskSnapshot,
        _ rhs: WorkRestTaskSnapshot
    ) -> Bool {
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        if lhs.endDate != rhs.endDate {
            return lhs.endDate < rhs.endDate
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
