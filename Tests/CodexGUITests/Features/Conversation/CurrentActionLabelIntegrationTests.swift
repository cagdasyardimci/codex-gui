import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct CurrentActionLabelIntegrationTests
{
	@Test func reportedActionAnimatesOnlyForTheDisplayedActiveTask() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 900,
				height: 700
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentViewController = controller
		defer
		{
			window.contentViewController = nil
		}
		let label = try #require(findActionLabel(controller.view))
		label.shouldReduceMotion =
		{
			false
		}
		var snapshot = ConversationSnapshot(
			projectPath: "/tmp/shimmer",
			threads: [],
			selectedThreadID: "active",
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
		snapshot.activeThreadID = "active"
		snapshot.activeExecutionState = .running
		snapshot.activeActivity = "Thinking"
		controller.render(snapshot)
		controller.view.layoutSubtreeIfNeeded()
		label.synchronizeAnimation()
		#expect(label.actionIsActive)
		#expect(label.highlightLayer != nil)
		#expect(label.stringValue == "Thinking")

		snapshot.activeActivity = "Running a command…"
		let previous = label.highlightLayer
		controller.render(snapshot)
		controller.view.layoutSubtreeIfNeeded()
		#expect(label.stringValue == "Running a command…")
		#expect(label.maximumNumberOfLines == 1)
		#expect(label.highlightLayer != nil && label.highlightLayer !== previous)

		snapshot.activeExecutionState = .completed
		controller.render(snapshot)
		#expect(!label.actionIsActive)
		#expect(label.highlightLayer == nil)

		snapshot.activeExecutionState = .running
		snapshot.activeThreadID = "another"
		controller.render(snapshot)
		#expect(!label.actionIsActive)
		#expect(label.highlightLayer == nil)

		snapshot.activeActivity = nil
		snapshot.jumpLoading = true
		controller.render(snapshot)
		#expect(label.stringValue == "Loading target message…")
		#expect(!label.actionIsActive)
		#expect(label.highlightLayer == nil)

		snapshot.activeThreadID = "active"
		snapshot.activeActivity = "Thinking"
		controller.render(snapshot)
		controller.view.layoutSubtreeIfNeeded()
		#expect(label.highlightLayer != nil)
		controller.viewDidDisappear()
		#expect(label.highlightLayer == nil)
		controller.viewDidAppear()
		#expect(label.highlightLayer != nil)
	}

	private func findActionLabel(_ view: NSView) -> CurrentActionLabel?
	{
		if let label = view as? CurrentActionLabel
		{
			return label
		}
		return view.subviews.lazy.compactMap
		{
			findActionLabel($0)
		}.first
	}
}
