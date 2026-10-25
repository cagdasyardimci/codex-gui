import AppKit
import Foundation
import Testing

@testable import CodexGUI

@Suite(
	.serialized
)
@MainActor
struct ConcurrentChatNavigationTests
{

	@Test func anonymousSubmissionKeepsOtherChatsAndNewChatAvailable()
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		_ = controller.view
		let snapshot = makeSnapshot()
		controller.render(snapshot)
		#expect(controller.chatsTable.isEnabled)
		#expect(controller.newChatButton.isEnabled)
		#expect(controller.canStartProjectChat)
	}

	private func makeSnapshot(
		threads: [ThreadSummary] = [],
		selectedThreadID: String? = nil
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/concurrent",
			threads: threads,
			selectedThreadID: selectedThreadID,
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
	}
}
