import Foundation
import Testing

@testable import CodexGUI

@Suite
struct ConcurrentChatNotificationsTests
{
	@Test func interleavedThreadsNotifyIndependentlyWithinOneCheckout()
	{
		let sessionID = UUID()
		let identity = WorkspaceIdentity(
			sessionID: sessionID,
			canonicalCheckoutPath: "/tmp/concurrent"
		)
		let owner = WorkspaceLifecycleOwnerReference(
			owner: .source(sessionID: sessionID),
			workspace: identity
		)
		let model = WorkspaceModel(identity: identity)
		var collection = TaskNotificationCollection()
		func presentation(
			_ threadID: String,
			_ state: ExecutionState
		) -> TaskNotificationPresentation
		{
			var execution = ExecutionModel()
			execution.activeThreadID = threadID
			execution.state = state
			return TaskNotificationPresentation(
				model: model,
				execution: execution,
				owner: owner
			)
		}
		#expect(collection.observe(presentation(
			"a",
			.running
		)) == nil)
		#expect(collection.observe(presentation(
			"b",
			.running
		)) == nil)
		let approval = collection.observe(presentation(
			"a",
			.awaitingApproval
		))
		#expect(approval?.threadID == "a")
		#expect(approval?.title == "Approval needed")
		#expect(collection.observe(presentation(
			"b",
			.running
		)) == nil)
		#expect(collection.observe(presentation(
			"a",
			.awaitingApproval
		)) == nil)
		let answer = collection.observe(presentation(
			"b",
			.awaitingAnswer
		))
		#expect(answer?.threadID == "b")
		#expect(answer?.title == "Answer needed")
		#expect(collection.observe(presentation(
			"a",
			.completed
		))?.threadID == "a")
		#expect(collection.observe(presentation(
			"b",
			.completed
		))?.threadID == "b")
		#expect(collection.observe(presentation(
			"a",
			.completed
		)) == nil)
		#expect(collection.observe(presentation(
			"b",
			.completed
		)) == nil)
	}
}
