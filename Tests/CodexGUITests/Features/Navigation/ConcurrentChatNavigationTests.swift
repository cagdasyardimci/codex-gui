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
	@Test func completionUnreadStateRemainsIndependentAcrossInterleavedThreads()
	{
		var snapshot = makeSnapshot(selectedThreadID: "history")
		snapshot.threadExecutions = [
			"a": ThreadExecutionPresentation(state: .running),
			"b": ThreadExecutionPresentation(state: .running),
		]
		var tracker = TaskUnreadTracker()
		#expect(tracker.observe(NavigationPresentation(snapshot)).isEmpty)
		snapshot.threadExecutions["a"] = ThreadExecutionPresentation(state: .completed)
		#expect(tracker.observe(NavigationPresentation(snapshot)) == ["a"])
		snapshot.threadExecutions["b"] = ThreadExecutionPresentation(state: .completed)
		#expect(tracker.observe(NavigationPresentation(snapshot)) == ["a", "b"])
		let executions = snapshot.threadExecutions
		snapshot = makeSnapshot(selectedThreadID: "a")
		snapshot.threadExecutions = executions
		#expect(tracker.observe(NavigationPresentation(snapshot)) == ["b"])
		snapshot = makeSnapshot(selectedThreadID: "history")
		snapshot.threadExecutions = executions
		#expect(tracker.observe(NavigationPresentation(snapshot)) == ["b"])
		snapshot.threadExecutions["a"] = ThreadExecutionPresentation(state: .running)
		#expect(tracker.observe(NavigationPresentation(snapshot)) == ["b"])
		snapshot.threadExecutions["a"] = ThreadExecutionPresentation(
			state: .completed,
			outcomeUncertain: true
		)
		#expect(tracker.observe(NavigationPresentation(snapshot)) == ["b"])
		snapshot.threadExecutions["a"] = ThreadExecutionPresentation(state: .completed)
		#expect(tracker.observe(NavigationPresentation(snapshot)) == ["a", "b"])
	}

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

	@Test func sidebarShowsBothRunningAndResponseNeededThreads() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		_ = controller.view
		let a = try #require(ThreadSummary(json: [
			"id": "a",
			"name": "First",
			"cwd": "/tmp/concurrent",
		]))
		let b = try #require(ThreadSummary(json: [
			"id": "b",
			"name": "Second",
			"cwd": "/tmp/concurrent",
		]))
		var snapshot = makeSnapshot(threads: [a, b])
		snapshot.threadExecutions = [
			"a": ThreadExecutionPresentation(state: .running),
			"b": ThreadExecutionPresentation(state: .awaitingApproval),
		]
		controller.render(snapshot)
		let running = try #require(controller.tableView(
			controller.chatsTable,
			viewFor: nil,
			row: 1
		) as? TaskSidebarCellView)
		let approval = try #require(controller.tableView(
			controller.chatsTable,
			viewFor: nil,
			row: 2
		) as? TaskSidebarCellView)
		#expect(running.progressRing.isRunning)
		#expect(approval.textField?.stringValue == "●  Second · Awaiting approval")
		#expect(approval.textField?.textColor == .systemOrange)
		#expect(approval.accessibilityLabel()?.contains("Awaiting approval task") == true)
		snapshot.threadExecutions["a"] = ThreadExecutionPresentation(
			state: .completed,
			outcomeUncertain: true
		)
		controller.render(snapshot)
		let uncertain = try #require(controller.tableView(
			controller.chatsTable,
			viewFor: nil,
			row: 1
		) as? TaskSidebarCellView)
		#expect(uncertain.textField?.stringValue == "●  First · Outcome unknown")
		#expect(uncertain.textField?.textColor == .systemGreen)
		#expect(uncertain.unreadDot.isHidden)
		#expect(controller.currentProjectActiveTaskCount == 2)
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
