import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(
	"Task workspace window layout",
	.serialized
)
struct TaskWorkspaceWindowLayoutTests
{
	@Test func recoveryCertaintyAgreesAcrossWorkspaceStatusAndNotificationEligibility() async throws
	{
		_ = NSApplication.shared
		let suite = "RecoveryTaskStatus.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let state = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults))
		let controller = MainWindowController(
			store: state.store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			}
		)
		let thread = try #require(ThreadSummary(json: [
			"id": "recovery",
			"name": "Recovering task",
			"cwd": "/tmp/recovery",
		]))
		var snapshot = ConversationSnapshot(
			projectPath: "/tmp/recovery",
			threads: [thread],
			selectedThreadID: thread.id,
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Synthetic",
			backendDescription: "Synthetic",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		snapshot.activeThreadID = thread.id
		for uncertain in [true, false]
		{
			var tracker = TaskNotificationTracker()
			snapshot.activeExecutionState = .running
			snapshot.taskOutcomeUncertain = false
			#expect(tracker.observe(snapshot) == nil)
			snapshot.activeExecutionState = .failed
			snapshot.taskOutcomeUncertain = uncertain
			controller.renderSnapshot(snapshot)

			let title = uncertain ? "Outcome unknown" : "Failed"
			let navigation = controller.navigation
			let row = try #require(navigation.sidebarItems.firstIndex
			{
				if case .thread(let candidate) = $0
				{
					return candidate.id == thread.id
				}
				return false
			})
			let taskCell = try #require(navigation.tableView(
				navigation.chatsTable,
				viewFor: nil,
				row: row
			) as? TaskSidebarCellView)
			#expect(taskCell.textField?.stringValue == "Recovering task")
			#expect(taskCell.accessibilityLabel() == "Open chat Recovering task")
			#expect(controller.statusButton.toolTip == "Synthetic · \(title)")
			#expect(controller.statusButton.accessibilityLabel()
				== "\(title). Open account and backend status")
			let notification = tracker.observe(snapshot)
			if uncertain
			{
				#expect(notification == nil)
			}
			else
			{
				#expect(notification?.title == "Task failed")
				#expect(notification?.threadID == thread.id)
			}
		}
		await controller.conversation.waitForRendering()
	}

	// This scenario shows a key window and transient popovers; hidden geometry is independent.
	@Test(.testTiming)
	func populatedTaskControlsFitTheShownFullWindowAtBothSupportedSizes() async throws
	{
		let timing = TestTiming.begin("test.body")
		defer
		{
			timing.end()
		}
		let suite = "TaskWindowLayout.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let state = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults))
		// Claim exclusive AppKit state after the test body has reached MainActor.
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let native = TestTiming.begin("native.body")
			defer
			{
				native.end()
			}
			timing.mark("native.begin")
			_ = NSApplication.shared
			let controller = MainWindowController(
				store: state.store,
				onOpenProject:
				{
				},
				onInsertPath:
				{
				}
			)
			let window = try #require(controller.window)
			defer
			{
				window.orderOut(nil)
				timing.mark("native.window.dismissed")
			}
			let split = controller.paneController.split
			let navigation = try #require(
				split.splitViewItems[0].viewController as? NavigationViewController
			)
			defer
			{
				navigation.projectActionsPopover.performClose(nil)
				navigation.searchPopover.close()
			}
			let conversation = try #require(
				split.splitViewItems[1].viewController.children.first as? ConversationViewController
			)
			let inspector = try #require(split.splitViewItems[2]
				.viewController.children.first as? InspectorViewController)
			let thread = try #require(
				ThreadSummary(json: [
					"id": "alpha",
					"name": "Alpha task",
					"cwd": "/tmp/alpha",
				])
			)
			let activeThread = try #require(
				ThreadSummary(json: [
					"id": "beta",
					"name": "Beta task",
					"cwd": "/tmp/beta",
				])
			)
			let id = UUID()
			var snapshot = ConversationSnapshot(
				projectPath: "/tmp/alpha",
				threads: [thread, activeThread],
				selectedThreadID: thread.id,
				entries: [],
				canLoadEarlierTurns: false,
				changedFiles: [],
				diff: "",
				draft: "Guide this task",
				canSend: false,
				accountDescription: "Synthetic",
				backendDescription: "Synthetic",
				executionState: .awaitingApproval,
				statusMessage: "Waiting for this task's approval",
				models: [],
				selectedModelID: nil,
				selectedEffort: nil,
				pendingInteractions: [],
				recentProjects: []
			)
			snapshot.activeThreadID = activeThread.id
			snapshot.activeExecutionState = .awaitingApproval
			snapshot.selectedTaskWorkspaceID = id
			snapshot.taskStatusSummary = "3 running tasks · 1 need a response"
			snapshot.taskWorkspaceMessage =
				"This task starts from committed HEAD. Source checkout edits stay in place."
			snapshot.taskWorkspaces = [
				TaskWorkspaceChoice(
					id: id,
					title: "Alpha task with a descriptive name",
					checkoutPath: "/tmp/alpha",
					branch: "codex/task/alpha",
					sourceWasDirty: true,
					phase: .active,
					executionState: .awaitingApproval,
					issue: nil,
					canRemoveCheckout: false
				),
				TaskWorkspaceChoice(
					id: UUID(),
					title: "Beta task",
					checkoutPath: "/tmp/beta",
					branch: "codex/task/beta",
					sourceWasDirty: false,
					phase: .active,
					executionState: .running,
					issue: nil,
					canRemoveCheckout: false
				),
			]
			navigation.render(snapshot)
			conversation.render(snapshot)
			inspector.changes.render(snapshot)
			controller.showWindow(nil)
			timing.mark("native.window.shown")
			// The transcript is empty. Navigation popovers and composer geometry are rendered
			// synchronously, so transcript text preparation is not a readiness dependency.

			try verifyPopoverLayouts(
				navigation: navigation,
				window: window
			)
			timing.mark("popovers.verified")
		}

	}

	private func verifyPopoverLayouts(
		navigation: NavigationViewController,
		window: NSWindow
	) throws
	{
		let sizes = [NSSize(
			width: 800,
			height: 500
		), NSSize(
			width: 1200,
			height: 760
		)]
		let openActions = try #require(
			findControl(
				in: navigation.view,
				label: "Add new project"
			) as? NSButton
		)
		window.makeKeyAndOrderFront(nil)
		try revealSidebarHeadingActions(containing: openActions)
		try #require(openActions.isEnabled)
		// Management remains available from the heading's context menu; the plus adds a project.
		// This fixture covers the retained popover's layout directly.
		navigation.toggleProjectActions(openActions)
		// Scope popover queries to this fixture, even when other tests have visible windows.
		try #require(navigation.projectActionsPopover.isShown)
		let actionsView = try #require(navigation.projectActionsPopover.contentViewController?.view)
		#expect(findControl(
			in: actionsView,
			label: "Show archived conversations"
		) == nil)
		let picker =
			try #require(findControl(
				in: actionsView,
				label: "Selected task checkout"
			) as? NSPopUpButton)
		#expect(picker.itemArray.contains
		{
			$0.title == "New Task Checkout…" && $0.action != nil
		})
		let actions = try #require(picker.itemArray.first
		{
			$0.title == "Task Actions"
		}?.submenu)
		#expect(actions.items.allSatisfy
		{
			!$0.isEnabled
		})
		for size in sizes
		{
			window.setFrame(
				NSRect(
					origin: window.frame.origin,
					size: size
				),
				display: true
			)
			window.layoutIfNeeded()
			#expect(window.frame.size == size)
			#expect(window.minSize == NSSize(
				width: 800,
				height: 500
			))
			for label in [
				"Selected task checkout",
				"Return to active task",
			]
			{
				let control = try #require(findControl(
					in: actionsView,
					label: label
				))
				let content = try #require(control.window?.contentView)
				#expect(
					content.bounds.contains(control.convert(
						control.bounds,
						to: content
					)),
					"\(label) must fit at \(size)"
				)
				#expect(control.frame.height > 0)
			}
		}
		navigation.toggleProjectActions(openActions)
		// Open the real search popover; layout coverage does not require text-input focus.
		navigation.showSearch()
		try #require(navigation.searchPopover.isShown)
		let search = navigation.searchField
		try #require(search.window?.isVisible == true)
		for size in sizes
		{
			window.setFrame(
				NSRect(
					origin: window.frame.origin,
					size: size
				),
				display: true
			)
			window.layoutIfNeeded()
			#expect(window.frame.size == size)
			let content = try #require(search.window?.contentView)
			#expect(content.bounds.contains(search.convert(
				search.bounds,
				to: content
			)))
		}
		// All asynchronous preparation precedes transient popovers so the SwiftPM host
		// does not suspend its async main executor inside their event-loop transition.
	}

	private func findControl(
		in view: NSView,
		label: String
	) -> NSView?
	{
		if view.accessibilityLabel() == label
		{
			return view
		}
		return view.subviews.lazy.compactMap
		{
			findControl(
				in: $0,
				label: label
			)
		}.first
	}

	private func findRequestDetails(in view: NSView) -> BoundedContentScrollView?
	{
		if let details = view as? BoundedContentScrollView
		{
			return details
		}
		return view.subviews.lazy.compactMap
		{
			findRequestDetails(in: $0)
		}.first
	}
}
