import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct StatusPopoverViewTests
{

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
		let view = StatusPopoverView(frame: .zero)
		view.render(current)
		let label = try #require(statusContextLabel(in: view))
		#expect(label.stringValue.contains("Last request input: 120 tokens (60 cached)"))
		#expect(label.stringValue.contains("Model context window: 1000 tokens"))
		#expect(label.stringValue.contains("Conversation total usage: 9000 tokens"))
		#expect(label.stringValue.contains("Active (waiting for approval)"))
		#expect(label.stringValue.contains("Current context occupancy: not reported"))
		#expect(!label.stringValue.contains("%"))
		view.render(snapshot([]))
		#expect(label.stringValue.contains("Last request input: unavailable"))
		#expect(label.stringValue.contains("Conversation total usage: unavailable"))
		#expect(!label.stringValue.contains("9000"))
	}

	private func statusContextLabel(in view: NSView) -> NSTextField?
	{
		if let label = view as? NSTextField,
			label
			.accessibilityLabel() == "Selected conversation status and token usage"
		{
			return label
		}
		return view.subviews.lazy.compactMap
		{
			statusContextLabel(in: $0)
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
