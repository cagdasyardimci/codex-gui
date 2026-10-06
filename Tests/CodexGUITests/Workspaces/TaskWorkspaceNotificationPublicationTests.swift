import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct TaskWorkspaceNotificationPublicationTests
{
	@Test func streamingNotificationsPreserveEveryPublicationWithoutPreparingFullSnapshots()
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/task-notifications"
		))
		model.connection.isConnected = true
		model.conversations.selectedConversation = .thread("worker")
		model.conversations.threads = [ThreadSummary(json: [
			"id": "worker",
			"name": "Active work"
		])!]
		model.execution.state = .running
		model.execution.activeThreadID = "worker"
		model.execution.activeTurnID = "turn"
		let context = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "worker",
			turnID: "turn"
		)
		model.execution.owner = ExecutionOwner(submission: context)
		model.conversations.selectedConversation = .thread("history")
		var clockReads = 0
		let usageRuntime = UsageRuntime(now:
			{
				clockReads += 1
				return Date(timeIntervalSince1970: 10)
			})
		let suiteName = "TaskWorkspaceNotificationTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer
		{
			defaults.removePersistentDomain(forName: suiteName)
		}
		let service = AppServer()
		let store = WorkspaceStateStore(
			model: model,
			service: service,
			storage: LocalStorage(defaults: defaults),
			persistence: WorkspacePersistenceScheduler
			{
				_ in
			},
			reducers: [WorkspaceReducer(reduce: WorkspaceFeatureComposition.reduce)],
			reduceDomainEvent: ConversationReviewComposition.reduceDomainEvent,
			usageRuntime: usageRuntime
		)
		let coordinator = TaskWorkspaceCoordinator(sourceStore: store)
		defer
		{
			coordinator.shutdown()
		}
		func publishFragments()
		{
			for _ in 0 ..< 100
			{
				store.dispatch(.execution(.backendObserved(
					context,
					.agentMessageDelta(
						threadId: "worker",
						turnId: "turn",
						itemId: "answer",
						text: "x"
					)
				)))
			}
		}

		// Lifecycle domain reduction reads the clock independently of notification publication.
		clockReads = 0
		publishFragments()
		let baselineClockReads = clockReads
		var publications = 0
		coordinator.onTaskSnapshot =
		{
			projected in
			publications += 1
			#expect(projected.activeThreadID == "worker")
			#expect(projected.executionState == .running)
			#expect(projected.workspaceOwner == WorkspaceLifecycleReducer.reference(store.model))
		}
		clockReads = 0
		publishFragments()
		#expect(publications == 100)
		#expect(clockReads == baselineClockReads)
		#expect(store.model.conversations.content[.thread("worker")]?.entries.first?.body
			== String(
				repeating: "x",
				count: 200
			))
	}
}
