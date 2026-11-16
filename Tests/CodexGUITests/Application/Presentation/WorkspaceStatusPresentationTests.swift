import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct WorkspaceStatusPresentationTests
{
	@Test func lightweightStatusRetainsAccountUsageAndExecutionSemantics()
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/project"
		))
		model.conversations.selectedConversation = .thread("selected")
		model.preferences.accountStatus = AccountStatus(
			type: "chatgpt",
			email: "member@example.com",
			requiresOpenAIAuth: true,
			planType: "pro"
		)
		model.preferences.signOutError = "Retry"
		model.usage.fetchedAt = Date(timeIntervalSince1970: 100)
		model.usage.needsRefresh = false
		model.usage.freshnessDeadline = Date(timeIntervalSince1970: 200)
		for connected in [false, true]
		{
			model.connection.isConnected = connected
			for state in [ExecutionState.ready, .running, .stopped]
			{
				model.execution.state = state
				let now = Date(timeIntervalSince1970: 150)
				let expected = WorkspaceStatusPresentation(WorkspaceSelectors.snapshot(
					model: model,
					now: now
				))
				let actual = WorkspaceStatusPresentation(
					model: model,
					now: now
				)
				#expect(actual.execution == expected.execution)
				#expect(actual.accountStatus == expected.accountStatus)
				#expect(actual.accountDescription == expected.accountDescription)
				#expect(actual.canLogOut == expected.canLogOut)
				#expect(actual.accountActionError == expected.accountActionError)
				#expect(actual.usage.isStale == expected.usage.isStale)
				#expect(actual.usage.refreshedAt == expected.usage.refreshedAt)
			}
		}
	}
}
