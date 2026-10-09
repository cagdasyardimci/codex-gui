import Foundation
import Testing
@testable import CodexGUI

@MainActor
struct ProjectArchiveRuntimeTests
{
	@Test func archivesTargetProjectAndReportsPartialCompletionOnActiveDetail() async throws
	{
		let service = MockCodexService()
		let project = URL(fileURLWithPath: "/tmp/archive-project").standardizedFileURL
			.resolvingSymlinksInPath()
		service.otherThread = ThreadSummary(json: ["id": "second", "cwd": project.path])
		let fixture = try IsolatedUserDefaultsFixture(prefix: "ProjectArchiveRuntimeTests")
		defer
		{
			fixture.cleanup()
		}
		let storage = LocalStorage(defaults: fixture.defaults)
		let runner = WorkspaceEffectRunner(
			service: service,
			persistence: storage.workspacePersistenceScheduler,
			mapEvent:
			{
				_, _ in []
			},
			deliver:
			{
				_, completion in completion()
			}
		)
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/selected-project"
		)
		let operation = ProjectArchiveOperation(
			context: OperationContext(
				workspace: identity,
				generation: 1,
				requestID: UUID()
			),
			project: project
		)
		service.turnsByThreadID["second"] = [service.nextTurn]
		let partial = await runner.archiveProjectChats(operation)
		#expect(partial.archivedThreadIDs == ["thread-1"])
		#expect(partial.failure != nil)
		#expect(service.archivedThreadIDs == ["thread-1"])
		service.turnsByThreadID["second"] = []
		service.archivedThreadIDs = []
		let complete = await runner.archiveProjectChats(operation)
		#expect(complete.archivedThreadIDs == ["thread-1", "second"])
		#expect(complete.failure == nil)
		#expect(service.readThreadIDs == ["thread-1", "second", "thread-1", "second"])
	}

	@Test func batchCompletionUnpinsOnlyArchivedTasksAndRejectsStaleResults() throws
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/archive-project"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.execution.state = .ready
		let archived = try #require(ThreadSummary(json: [
			"id": "archived",
			"cwd": "/tmp/archive-project"
		]))
		let retained = try #require(ThreadSummary(json: [
			"id": "retained",
			"cwd": "/tmp/archive-project"
		]))
		model.preferences.pinnedTasks = [archived, retained]
		model.conversations.threads = [archived, retained]
		model.conversations.selectedConversation = .thread(archived.id)
		let context = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID()
		)
		let operation = ProjectArchiveOperation(
			context: context,
			project: URL(fileURLWithPath: "/tmp/archive-project")
		)
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.projectArchiveRequested(operation))
		)
		#expect(model.conversations.pendingProjectArchive == operation)
		#expect(WorkspaceLifecycleReducer.blocksCleanup(model))
		#expect(!WorkspaceEligibility(model: model).canSend)
		let stale = ProjectArchiveOperation(
			context: OperationContext(
				workspace: model.identity,
				generation: 1,
				requestID: UUID()
			),
			project: operation.project
		)
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.projectArchiveFinished(
				stale,
				ProjectArchiveResult(
					archivedThreadIDs: [retained
						.id],
					failure: nil
				)
			))
		)
		#expect(model.preferences.pinnedTasks.count == 2)
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.projectArchiveFinished(
				operation,
				ProjectArchiveResult(
					archivedThreadIDs: [archived
						.id],
					failure:
					OperationFailure(
						message: "Second chat failed",
						outcomeIsUncertain: true
					)
				)
			))
		)
		#expect(model.preferences.pinnedTasks.map(\.id) == [retained.id])
		#expect(model.conversations.threads.map(\.id) == [retained.id])
		#expect(model.conversations.selectedConversation == .newChat)
		#expect(model.conversations.pendingProjectArchive == nil)
		#expect(model.conversations.error?.contains("Second chat failed") == true)
	}
}
