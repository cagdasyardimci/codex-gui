import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct TaskWorkspaceNotificationTests
{
	private func model(path: String = "/tmp/task-notifications") -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: path
		))
		model.connection.isConnected = true
		model.conversations.selectedConversation = .thread("worker")
		model.conversations.threads = [ThreadSummary(json: [
			"id": "worker",
			"name": "Active work"
		])!]
		return model
	}

	private func presentation(_ model: WorkspaceModel) -> TaskNotificationPresentation
	{
		TaskNotificationPresentation(
			model: model,
			owner: WorkspaceLifecycleReducer.reference(model)
		)
	}

	@Test func canonicalNotificationStateMatchesSnapshotWhileAnotherConversationIsVisible()
	{
		var model = model()
		let states: [ExecutionState] = [
			.ready,
			.running,
			.awaitingApproval,
			.awaitingAnswer,
			.stopping,
			.stopped,
			.completed,
			.failed,
			.disconnected
		]
		let activeThreadIDs: [String?] = ["worker", nil]
		for state in states
		{
			for activeThreadID in activeThreadIDs
			{
				model.execution.state = state
				model.execution.activeThreadID = activeThreadID
				let snapshot = WorkspaceSelectors.snapshot(
					model: model,
					now: Date(timeIntervalSince1970: 10)
				)
				let projected = presentation(model)
				#expect(projected.executionState
					== (snapshot.activeExecutionState ?? snapshot.executionState))
				#expect(projected.activeThreadID == snapshot.activeThreadID)
				#expect(projected.workspaceOwner == snapshot.workspaceOwner)
				#expect(projected.taskOutcomeUncertain == snapshot.taskOutcomeUncertain)
			}
		}
	}

	@Test func narrowTransitionsRetainTerminalThreadIdentityAndSuppressUnknownOutcomes()
	{
		var model = model()
		var tracker = TaskNotificationCollection()
		model.execution.state = .ready
		#expect(tracker.observe(presentation(model)) == nil)
		model.execution.activeThreadID = "worker"
		model.execution.owner = ExecutionOwner(submission: OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "worker"
		))
		model.execution.state = .running
		#expect(tracker.observe(presentation(model)) == nil)
		model.execution.state = .awaitingApproval
		let approval = tracker.observe(presentation(model))
		#expect(approval?.title == "Approval needed")
		#expect(approval?.threadID == "worker")
		#expect(approval?.owner == WorkspaceLifecycleReducer.reference(model))
		#expect(approval?.body == "Active work")
		#expect(tracker.observe(presentation(model)) == nil)
		model.execution.state = .running
		#expect(tracker.observe(presentation(model)) == nil)
		model.execution.activeThreadID = nil
		model.execution.state = .completed
		let completed = tracker.observe(presentation(model))
		#expect(completed?.title == "Task completed")
		#expect(completed?.threadID == "worker")
		#expect(completed?.body == "Active work")

		model.execution.activeThreadID = "worker"
		model.execution.state = .running
		#expect(tracker.observe(presentation(model)) == nil)
		model.execution.state = .failed
		model.execution.hasUncertainRequest = true
		#expect(tracker.observe(presentation(model)) == nil)
		model.execution.hasUncertainRequest = false
		model.execution.state = .running
		#expect(tracker.observe(presentation(model)) == nil)
		model.execution.state = .failed
		#expect(tracker.observe(presentation(model))?.title == "Task failed")
	}

	@Test func repeatedBackendThreadIDsKeepNarrowTransitionHistoriesWithTheirOwners()
	{
		var alpha = model(path: "/tmp/alpha")
		var beta = model(path: "/tmp/beta")
		var tracker = TaskNotificationCollection()
		for initial in [alpha, beta]
		{
			#expect(tracker.observe(presentation(initial)) == nil)
		}
		alpha.execution.activeThreadID = "worker"
		beta.execution.activeThreadID = "worker"
		alpha.execution.state = .running
		beta.execution.state = .running
		#expect(tracker.observe(presentation(alpha)) == nil)
		#expect(tracker.observe(presentation(beta)) == nil)
		alpha.execution.state = .awaitingAnswer
		beta.execution.state = .awaitingApproval
		let answer = tracker.observe(presentation(alpha))
		let approval = tracker.observe(presentation(beta))
		#expect(answer?.title == "Answer needed")
		#expect(approval?.title == "Approval needed")
		#expect(answer?.owner == WorkspaceLifecycleReducer.reference(alpha))
		#expect(approval?.owner == WorkspaceLifecycleReducer.reference(beta))
		#expect(answer?.owner != approval?.owner)
		#expect(tracker.observe(presentation(alpha)) == nil)
		#expect(tracker.observe(presentation(beta)) == nil)
	}
}
