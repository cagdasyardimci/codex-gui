import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationAmbientStatusPresentationTests
{
	@Test func ambientConversationStatusesAreOmittedAndReturnActionRemains() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		var snapshot = ConversationSnapshot(
			projectPath: "/tmp/conversation-status",
			threads: [],
			selectedThreadID: "selected",
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: .running,
			statusMessage: "Backend status",
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		snapshot.activeThreadID = "active"
		snapshot.activeExecutionState = .running
		snapshot.activeActivity = "Thinking"
		snapshot.jumpLoading = true
		controller.render(snapshot)

		let labels = descendants(controller.view).compactMap
		{
			($0 as? NSTextField)?.stringValue
		}
		#expect(!labels.contains("Backend status"))
		#expect(!labels.contains("Thinking"))
		#expect(!labels.contains("Loading target message…"))
		let returnButton = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == "Return to Task"
		})
		#expect(!returnButton.isHidden)
		#expect(returnButton.isEnabled)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}
