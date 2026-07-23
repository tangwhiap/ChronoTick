import SwiftData
import XCTest
@testable import ChronoTick

@MainActor
final class ProjectListHierarchyTests: XCTestCase {
    private var retainedContainers: [ModelContainer] = []

    func testCreatesThreeFolderLevelsAndRejectsFourth() throws {
        let context = try makeModelContext()
        let legacyList = ProjectTaskList(name: "Legacy")
        context.insert(legacyList)
        try context.save()

        XCTAssertNil(legacyList.parentFolder)

        let first = try TaskMutationCoordinator.createProjectTaskListFolder(
            named: "First",
            in: nil,
            modelContext: context
        )
        let second = try TaskMutationCoordinator.createProjectTaskListFolder(
            named: "Second",
            in: first,
            modelContext: context
        )
        let third = try TaskMutationCoordinator.createProjectTaskListFolder(
            named: "Third",
            in: second,
            modelContext: context
        )

        XCTAssertEqual(first.hierarchyDepth, 1)
        XCTAssertEqual(second.hierarchyDepth, 2)
        XCTAssertEqual(third.hierarchyDepth, 3)
        assertHierarchyError(.maximumDepthExceeded) {
            try TaskMutationCoordinator.createProjectTaskListFolder(
                named: "Fourth",
                in: third,
                modelContext: context
            )
        }
    }

    func testNamesShareCaseInsensitiveSiblingNamespaceButMayRepeatInOtherFolders() throws {
        let context = try makeModelContext()
        let rootList = try TaskMutationCoordinator.createProjectTaskList(
            named: "  Work  ",
            in: nil,
            modelContext: context
        )
        XCTAssertEqual(rootList.name, "Work")

        assertHierarchyError(.duplicateName) {
            try TaskMutationCoordinator.createProjectTaskListFolder(
                named: "work",
                in: nil,
                modelContext: context
            )
        }

        let folder = try TaskMutationCoordinator.createProjectTaskListFolder(
            named: "Folder",
            in: nil,
            modelContext: context
        )
        let nestedList = try TaskMutationCoordinator.createProjectTaskList(
            named: "WORK",
            in: folder,
            modelContext: context
        )
        let nestedFolder = try TaskMutationCoordinator.createProjectTaskListFolder(
            named: "Archive",
            in: folder,
            modelContext: context
        )

        assertHierarchyError(.duplicateName) {
            try TaskMutationCoordinator.renameProjectTaskList(
                nestedList,
                to: " archive ",
                modelContext: context
            )
        }
        XCTAssertEqual(nestedList.name, "WORK")

        try TaskMutationCoordinator.renameProjectTaskListFolder(
            nestedFolder,
            to: "archive",
            modelContext: context
        )
        XCTAssertEqual(nestedFolder.name, "archive")
    }

    func testMovesListsBetweenFoldersAndRejectsDestinationNameConflictWithoutMutation() throws {
        let context = try makeModelContext()
        let source = try TaskMutationCoordinator.createProjectTaskListFolder(
            named: "Source",
            in: nil,
            modelContext: context
        )
        let destination = try TaskMutationCoordinator.createProjectTaskListFolder(
            named: "Destination",
            in: nil,
            modelContext: context
        )
        let list = try TaskMutationCoordinator.createProjectTaskList(
            named: "Inbox",
            in: source,
            modelContext: context
        )

        try TaskMutationCoordinator.moveProjectTaskList(list, to: destination, modelContext: context)
        XCTAssertEqual(list.parentFolder?.id, destination.id)

        try TaskMutationCoordinator.moveProjectTaskList(list, to: nil, modelContext: context)
        XCTAssertNil(list.parentFolder)

        _ = try TaskMutationCoordinator.createProjectTaskList(
            named: "inbox",
            in: destination,
            modelContext: context
        )
        assertHierarchyError(.duplicateName) {
            try TaskMutationCoordinator.moveProjectTaskList(list, to: destination, modelContext: context)
        }
        XCTAssertNil(list.parentFolder)

        try TaskMutationCoordinator.moveProjectTaskList(list, to: nil, modelContext: context)
        XCTAssertNil(list.parentFolder)
    }

    func testMovesFolderTreeAndRejectsCyclesAndExcessiveDepth() throws {
        let context = try makeModelContext()
        let root = try TaskMutationCoordinator.createProjectTaskListFolder(
            named: "Root",
            in: nil,
            modelContext: context
        )
        let child = try TaskMutationCoordinator.createProjectTaskListFolder(
            named: "Child",
            in: root,
            modelContext: context
        )
        let grandchild = try TaskMutationCoordinator.createProjectTaskListFolder(
            named: "Grandchild",
            in: child,
            modelContext: context
        )
        let target = try TaskMutationCoordinator.createProjectTaskListFolder(
            named: "Target",
            in: nil,
            modelContext: context
        )

        assertHierarchyError(.cannotMoveFolderIntoItself) {
            try TaskMutationCoordinator.moveProjectTaskListFolder(root, to: root, modelContext: context)
        }
        assertHierarchyError(.cannotMoveFolderIntoDescendant) {
            try TaskMutationCoordinator.moveProjectTaskListFolder(root, to: grandchild, modelContext: context)
        }
        assertHierarchyError(.maximumDepthExceeded) {
            try TaskMutationCoordinator.moveProjectTaskListFolder(root, to: target, modelContext: context)
        }
        XCTAssertNil(root.parentFolder)

        try TaskMutationCoordinator.moveProjectTaskListFolder(grandchild, to: target, modelContext: context)
        XCTAssertEqual(grandchild.parentFolder?.id, target.id)
        XCTAssertEqual(grandchild.hierarchyDepth, 2)

        try TaskMutationCoordinator.moveProjectTaskListFolder(grandchild, to: nil, modelContext: context)
        XCTAssertNil(grandchild.parentFolder)
    }

    func testDeletingFolderCascadesThroughListsTasksAndChildFolders() throws {
        let context = try makeModelContext()
        let root = try TaskMutationCoordinator.createProjectTaskListFolder(
            named: "Root",
            in: nil,
            modelContext: context
        )
        let child = try TaskMutationCoordinator.createProjectTaskListFolder(
            named: "Child",
            in: root,
            modelContext: context
        )
        let rootList = try TaskMutationCoordinator.createProjectTaskList(
            named: "Root list",
            in: root,
            modelContext: context
        )
        let childList = try TaskMutationCoordinator.createProjectTaskList(
            named: "Child list",
            in: child,
            modelContext: context
        )
        context.insert(ProjectTask(title: "One", list: rootList))
        context.insert(ProjectTask(title: "Two", list: childList))
        try context.save()

        try TaskMutationCoordinator.deleteProjectTaskListFolder(root, modelContext: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<ProjectTaskListFolder>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProjectTaskList>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProjectTask>()).isEmpty)
    }

    func testSelectionFallsBackOnlyWhenSelectedListWasDeleted() {
        let viewModel = AppViewModel()
        let deleted = ProjectTaskList(name: "Deleted")
        let fallback = ProjectTaskList(name: "Fallback")
        viewModel.selectedSection = .projectLists
        viewModel.selectedProjectTaskListID = deleted.id

        viewModel.reconcileProjectTaskListSelection(afterDeleting: [deleted.id], fallback: fallback)
        XCTAssertEqual(viewModel.selectedProjectTaskListID, fallback.id)
        XCTAssertEqual(viewModel.selectedSection, .projectLists)

        viewModel.reconcileProjectTaskListSelection(afterDeleting: [fallback.id], fallback: nil)
        XCTAssertNil(viewModel.selectedProjectTaskListID)
        XCTAssertEqual(viewModel.selectedSection, .week)
    }

    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([
            ProjectTaskListFolder.self,
            ProjectTaskList.self,
            ProjectTask.self
        ])
        let configuration = ModelConfiguration(
            "ProjectListHierarchyTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        retainedContainers.append(container)
        return container.mainContext
    }

    private func assertHierarchyError(
        _ expected: ProjectListHierarchyError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ProjectListHierarchyError, expected, file: file, line: line)
        }
    }
}
