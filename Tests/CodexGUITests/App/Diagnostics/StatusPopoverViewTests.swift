import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
struct StatusPopoverViewTests
{
	@Test func accountMenuUsesReportedIdentityAndPlanAndRoutesActions() throws
	{
		_ = NSApplication.shared
		var current = snapshot([])
		current.canLogOut = true
		current.accountStatus = AccountStatus(
			type: "chatgpt",
			email: "member@example.com",
			requiresOpenAIAuth: true,
			planType: "pro"
		)
		let view = StatusPopoverView(frame: .zero)
		view.render(current)
		#expect(statusLabel(
			in: view,
			accessibilityLabel: "Account identity"
		)?.stringValue
			== "member@example.com")
		#expect(statusLabel(
			in: view,
			accessibilityLabel: "Account plan"
		)?.stringValue == "Pro")
		var settings = 0
		var usage = 0
		var logout = 0
		view.onShowUsage =
		{
			usage += 1
		}
		view.onShowSettings =
		{
			settings += 1
		}
		view.onLogout =
		{
			logout += 1
		}
		let usageButton = try #require(button(
			in: view,
			label: "Usage"
		))
		let settingsButton = try #require(button(
			in: view,
			label: "Settings"
		))
		let logoutButton = try #require(button(
			in: view,
			label: "Log out"
		))
		#expect(usageButton.dispatchConfiguredAction())
		#expect(settingsButton.dispatchConfiguredAction())
		#expect(logoutButton.dispatchConfiguredAction())
		#expect(usage == 1)
		#expect(settings == 1)
		#expect(logout == 1)
		current.accountActionError = "Unavailable"
		view.render(current)
		#expect(statusLabel(
			in: view,
			accessibilityLabel: "Account plan"
		)?.stringValue
			== "Could not log out: Unavailable")
		current.accountActionPending = true
		view.render(current)
		#expect(!logoutButton.isEnabled)
		view.render(snapshot([]))
		#expect(!logoutButton.isEnabled)
		#expect(statusLabel(
			in: view,
			accessibilityLabel: "Account identity"
		)?
			.stringValue == "Test")
		#expect(statusLabel(
			in: view,
			accessibilityLabel: "Account plan"
		)?.stringValue == "")
	}

	@Test func accountUsageShowsRemainingPrimaryWindowAndRetainsStaleness() throws
	{
		var current = snapshot([])
		current.usage = try #require(AccountRateLimitsSnapshot(json: [
			"rateLimits": ["primary": ["usedPercent": 12.0]],
		]))
		current.usageIsStale = false
		#expect(StatusPopoverView.remainingUsage(UsagePresentation(current)) == "88% left")
		current.usageIsStale = true
		#expect(StatusPopoverView.remainingUsage(UsagePresentation(current)) == "88% left · stale")
		#expect(StatusPopoverView.remainingUsage(UsagePresentation(snapshot([]))) == "Unavailable")
	}

	private func button(
		in view: NSView,
		label: String
	) -> NSButton?
	{
		if let button = view as? NSButton, button.accessibilityLabel() == label
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			button(
				in: $0,
				label: label
			)
		}.first
	}

	@Test func statusDisplaysLastInputAndCumulativeUsageSeparatelyWithoutInferringOccupancy() throws
	{
		_ = NSApplication.shared
		var current = snapshot([])
		let last: [String: Any] = ["inputTokens": 120,
									"cachedInputTokens": 60,
									"outputTokens": 10,
									"reasoningOutputTokens": 4,
									"totalTokens": 130]
		let total: [String: Any] = ["inputTokens": 7000,
									"cachedInputTokens": 3000,
									"outputTokens": 2000,
									"reasoningOutputTokens": 500,
									"totalTokens": 9000]
		current.threadTokenUsage = try #require(ThreadTokenUsage(json: [
			"last": last,
			"total": total,
			"modelContextWindow": 1000,
		]))
		current.threadStatus = try #require(ThreadStatus(json: [
			"type": "active",
			"activeFlags": ["waitingOnApproval"]
		]))
		var text = StatusPopoverView.conversationDetails(WorkspaceStatusPresentation(current))
		#expect(text.contains("Last request input: 120 tokens (60 cached)"))
		#expect(text.contains("Model context window: 1000 tokens"))
		#expect(text.contains("Conversation total usage: 9000 tokens"))
		#expect(text.contains("Active (waiting for approval)"))
		#expect(text.contains("Current context occupancy: not reported"))
		#expect(!text.contains("%"))
		text = StatusPopoverView.conversationDetails(WorkspaceStatusPresentation(snapshot([])))
		#expect(text.contains("Last request input: unavailable"))
		#expect(text.contains("Conversation total usage: unavailable"))
		#expect(!text.contains("9000"))
	}

	private func statusLabel(
		in view: NSView,
		accessibilityLabel: String
	) -> NSTextField?
	{
		if let label = view as? NSTextField,
			label.accessibilityLabel() == accessibilityLabel
		{
			return label
		}
		return view.subviews.lazy.compactMap
		{
			statusLabel(
				in: $0,
				accessibilityLabel: accessibilityLabel
			)
		}.first
	}

	private func snapshot(_ entries: [ConversationEntry]) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: nil,
			threads: [],
			selectedThreadID: nil,
			entries: entries,
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Test",
			backendDescription: "Test",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
	}
}
