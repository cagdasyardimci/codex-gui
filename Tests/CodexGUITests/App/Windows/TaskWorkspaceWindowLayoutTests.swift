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
			#expect(taskCell.textField?.stringValue == "●  Recovering task · \(title)")
			#expect(taskCell.accessibilityLabel() == "\(title) task, open chat Recovering task")
			let popoverLabel = try #require(findControl(
				in: controller.statusView,
				label: "Current task status"
			) as? NSTextField)
			#expect(popoverLabel.stringValue == title)
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

	@Test func hiddenBusyLayoutKeepsApprovalAndContextWithinMinimumContent() async throws
	{
		_ = NSApplication.shared
		let suite = "BusyTaskWindowLayout.\(UUID().uuidString)"
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
		let window = try #require(controller.window)
		let split = controller.paneController.split
		let conversation = try #require(
			split.splitViewItems[1].viewController.children.first as? ConversationViewController
		)
		let directory =
			"/tmp/native-final/task-workspaces/checkouts/"
				+ "native-task-beta-61-long-identity"
		let thread = try #require(
			ThreadSummary(json: ["id": "beta", "name": "Beta task", "cwd": directory])
		)
		let approvals = (0 ..< 3).map
		{
			index in
			PendingInteraction(
				id: "approval-\(index)",
				threadId: "beta",
				turnId: "turn",
				itemId: "command",
				approvalId: nil,
				kind: .commandApproval,
				reason: "Synthetic approval fixture; no command will run.",
				command: "printf synthetic-approval",
				cwd: directory,
				grantRoot: nil,
				networkHost: nil,
				networkProtocol: nil,
				questions: [],
				requestedPermissions: nil,
				additionalPermissions: nil,
				availableDecisions: [.accept, .decline, .cancel]
			)
		}
		var snapshot = ConversationSnapshot(
			projectPath: directory,
			threads: [thread],
			selectedThreadID: "beta",
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "Draft for beta",
			canSend: false,
			accountDescription: "Synthetic",
			backendDescription: "Synthetic",
			executionState: .awaitingApproval,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: approvals,
			recentProjects: []
		)
		snapshot.activeThreadID = "beta"
		snapshot.activeExecutionState = .awaitingApproval
		snapshot.activeActivity = "printf synthetic-approval"
		snapshot.activePlan = TurnPlanUpdate(json: [
			"threadId": "beta",
			"turnId": "turn",
			"plan": [["step": "Apply requested change", "status": "inProgress"]],
		])
		snapshot.taskStatusSummary = "2 running tasks · 2 need a response"
		snapshot.taskWorkspaces = ["Alpha", "Beta"].map
		{
			TaskWorkspaceChoice(
				id: UUID(),
				title: $0,
				checkoutPath: directory + $0,
				branch: "codex/task/\($0)",
				sourceWasDirty: false,
				phase: .active,
				executionState: .awaitingApproval,
				issue: nil,
				canRemoveCheckout: false
			)
		}
		snapshot.selectedTaskWorkspaceID = snapshot.taskWorkspaces.last?.id
		controller.renderSnapshot(snapshot)
		controller.paneController.setReviewCollapsed(false)
		window.setFrame(
			NSRect(
				origin: window.frame.origin,
				size: NSSize(
					width: 800,
					height: 500
				)
			),
			display: false
		)
		await conversation.waitForRendering()
		window.layoutIfNeeded()
		split.view.layoutSubtreeIfNeeded()
		#expect(!window.isVisible)
		#expect(window.frame.size == NSSize(
			width: 800,
			height: 500
		))
		#expect(split.view.fittingSize.height <= window.contentLayoutRect.height)
		#expect(controller.statusButton.fittingSize.width <= 36)
		#expect(controller.statusButton.toolTip
			== "\(snapshot.accountDescription) · Awaiting approval")
		let details = try #require(findRequestDetails(in: conversation.view))
		#expect(!details.isHidden)
		#expect(details.frame.height >= 36 && details.frame.height <= 140)
		#expect(try #require(details.documentView).frame.height > details.contentSize.height)
		for label in [
			"Add attachments or inspect request context",
			"Send message",
			"Stop current task",
		]
		{
			let control = try #require(findControl(
				in: conversation.view,
				label: label
			))
			#expect(!control.isHidden)
			#expect(control.frame.height > 0)
			#expect(
				conversation.view.bounds.contains(control.convert(
					control.bounds,
					to: conversation.view
				))
			)
		}
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
			let id = UUID()
			var snapshot = ConversationSnapshot(
				projectPath: "/tmp/alpha",
				threads: [thread],
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
			snapshot.activeThreadID = thread.id
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
				label: "Project and conversation actions"
			) as? NSButton
		)
		window.makeKeyAndOrderFront(nil)
		try #require(openActions.isEnabled)
		// Open the real popover through its configured action; click-animation polling is unrelated
		// to layout coverage and can stop SwiftPM's async-main run loop via HIToolbox's wakeup.
		try #require(openActions.sendAction(
			try #require(openActions.action),
			to: openActions.target
		))
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
				"Running task summary",
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
		try #require(openActions.sendAction(
			try #require(openActions.action),
			to: openActions.target
		))
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
