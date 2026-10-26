import Foundation
import Testing

@testable import CodexGUI

@Suite
struct TaskNotificationsTests
{

	@Test func uncertainFailureDoesNotAnnounceAConfirmedTaskFailure() throws
	{
		let thread = try #require(ThreadSummary(json: ["id": "owner", "name": "Active work"]))
		var snapshot = ConversationSnapshot(
			projectPath: "/tmp/project",
			threads: [thread],
			selectedThreadID: "owner",
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: .running,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		snapshot.activeThreadID = "owner"
		snapshot.activeExecutionState = .running
		var tracker = TaskNotificationTracker()
		#expect(tracker.observe(snapshot) == nil)

		snapshot.activeExecutionState = .failed
		snapshot.taskOutcomeUncertain = true
		#expect(tracker.observe(snapshot) == nil)

		snapshot.activeExecutionState = .running
		snapshot.taskOutcomeUncertain = false
		#expect(tracker.observe(snapshot) == nil)
		snapshot.activeExecutionState = .failed
		#expect(
			tracker.observe(snapshot)
				== TaskNotificationEvent(
					threadID: "owner",
					title: "Task failed",
					body: "Active work"
				)
		)
	}
	@Test func identicalBackendThreadIDsRetainDistinctNotificationOwners()
	{
		let alphaSession = UUID()
		let betaSession = UUID()
		let alpha = WorkspaceLifecycleOwnerReference(
			owner: .managed(
				workspaceID: UUID(),
				sessionID: alphaSession
			),
			workspace: WorkspaceIdentity(
				sessionID: alphaSession,
				canonicalCheckoutPath: "/tasks/alpha"
			)
		)
		let beta = WorkspaceLifecycleOwnerReference(
			owner: .managed(
				workspaceID: UUID(),
				sessionID: betaSession
			),
			workspace: WorkspaceIdentity(
				sessionID: betaSession,
				canonicalCheckoutPath: "/tasks/beta"
			)
		)
		let alphaPayload = TaskNotificationPayload.userInfo(TaskNotificationEvent(
			threadID: "same-thread",
			title: "Approval needed",
			body: "Alpha",
			owner: alpha
		))
		let betaPayload = TaskNotificationPayload.userInfo(TaskNotificationEvent(
			threadID: "same-thread",
			title: "Approval needed",
			body: "Beta",
			owner: beta
		))
		#expect(alphaPayload["threadID"] as? String == betaPayload["threadID"] as? String)
		#expect(TaskNotificationPayload.owner(alphaPayload) == alpha)
		#expect(TaskNotificationPayload.owner(betaPayload) == beta)
		#expect(TaskNotificationPayload.owner(alphaPayload) != TaskNotificationPayload
			.owner(betaPayload))
		var incomplete = alphaPayload
		incomplete.removeValue(forKey: "workspaceSessionID")
		#expect(TaskNotificationPayload.owner(incomplete) == nil)
	}

}
