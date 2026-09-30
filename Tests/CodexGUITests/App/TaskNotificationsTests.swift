import Foundation
import Testing

@testable import CodexGUI

@Suite
struct TaskNotificationsTests
{
	@Test(arguments: [
		"bare.bundle",
		"identified.bundle",
		"missing-id.app",
		"empty-id.app",
		"library.app",
	])
	@MainActor
	func unsupportedLaunchKeepsNotificationsUnavailableAcrossTaskEvents(name: String) throws
	{
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let bundleURL = directory.appendingPathComponent(name)
		let contents = bundleURL.appendingPathComponent("Contents")
		try FileManager.default.createDirectory(
			at: contents,
			withIntermediateDirectories: true
		)
		var info = ["CFBundlePackageType": name == "library.app" ? "BNDL" : "APPL"]
		if name == "identified.bundle" || name == "library.app"
		{
			info["CFBundleIdentifier"] = "local.codexgui.notification-tests"
		}
		else if name == "empty-id.app"
		{
			info["CFBundleIdentifier"] = ""
		}
		try PropertyListSerialization.data(
			fromPropertyList: info,
			format: .xml,
			options: 0
		)
		.write(to: contents.appendingPathComponent("Info.plist"))
		let bundle = try #require(Bundle(url: bundleURL))
		let coordinator = TaskNotificationCoordinator(bundle: bundle)
		var reportedStatus: String?
		coordinator.onStatusChange =
		{
			reportedStatus = $0
		}
		#expect(coordinator.statusMessage.contains("Notifications are unavailable"))
		#expect(reportedStatus == coordinator.statusMessage)

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
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		snapshot.activeThreadID = "owner"
		for state: ExecutionState in [
			.running,
			.awaitingApproval,
			.awaitingAnswer,
			.completed,
			.failed,
		]
		{
			snapshot.activeExecutionState = state
			coordinator.observe(snapshot)
		}
		#expect(coordinator.statusMessage == reportedStatus)
	}

	@Test func approvalAndCompletionNotifyOnceForTheOwningConversation() throws
	{
		let thread = try #require(ThreadSummary(json: ["id": "owner", "name": "Active work"]))
		var snapshot = ConversationSnapshot(
			projectPath: "/tmp/project",
			threads: [thread],
			selectedThreadID: "history",
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		var tracker = TaskNotificationTracker()
		#expect(tracker.observe(snapshot) == nil)
		snapshot.activeThreadID = "owner"
		snapshot.activeExecutionState = .running
		#expect(tracker.observe(snapshot) == nil)
		snapshot.activeExecutionState = .awaitingApproval
		#expect(
			tracker.observe(snapshot)
				== TaskNotificationEvent(
					threadID: "owner",
					title: "Approval needed",
					body: "Active work"
				)
		)
		#expect(tracker.observe(snapshot) == nil)
		snapshot.activeExecutionState = .completed
		#expect(
			tracker.observe(snapshot)
				== TaskNotificationEvent(
					threadID: "owner",
					title: "Task completed",
					body: "Active work"
				)
		)
		snapshot.activeThreadID = nil
		snapshot.activeExecutionState = nil
		#expect(tracker.observe(snapshot) == nil)
	}

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
