import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationViewControllerTests
{
	@Test func sameTranscriptInAnotherStoreCancelsOldPreparationAndKeepsCurrentDraft() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		_ = controller.view
		let entry = ConversationEntry(
			id: "turn:answer",
			kind: .agent,
			title: "Codex",
			body: "The same reported answer"
		)
		let originalOwner = ConversationPresentationTestFixture.presentationOwner(sessionID: UUID())
		var initial = snapshot([entry])
		initial.workspaceOwner = originalOwner
		controller.render(ConversationPresentation(initial))
		await controller.waitForRendering()
		let previousCollection = try #require(findCollection(in: controller.view))
		let old = ConversationEntry(
			id: entry.id,
			kind: .agent,
			title: "Codex",
			body: String(
				repeating: "Obsolete streamed markdown **text**.\n",
				count: 100
			)
		)
		var obsolete = snapshot([old])
		obsolete.workspaceOwner = originalOwner
		controller.render(ConversationPresentation(obsolete))
		var current = ConversationSnapshot(
			projectPath: "/tmp/replay",
			threads: [],
			selectedThreadID: "replay",
			entries: [entry],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "Current store draft",
			canSend: true,
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
		current.workspaceOwner = ConversationPresentationTestFixture
			.presentationOwner(sessionID: UUID())
		controller.render(ConversationPresentation(current))
		await controller.waitForRendering()
		let collection = try #require(findCollection(in: controller.view))
		#expect(collection !== previousCollection)
		#expect(collection.numberOfItems(inSection: 0) == 1)
		let composer = try #require(findTextView(
			in: controller.view,
			label: "Message to Codex"
		))
		#expect(composer.string == "Current store draft")
		composer.setSelectedRange(NSRange(
			location: 3,
			length: 5
		))
		current.usageError = "Unrelated usage update"
		controller.render(ConversationPresentation(current))
		await controller.waitForRendering()
		#expect(findCollection(in: controller.view) === collection)
		#expect(composer.selectedRange() == NSRange(
			location: 3,
			length: 5
		))
	}

	@Test(arguments: ["session", "selection"])
	func retainedInteractionCardRespondsThroughItsCapturedOwnerCallback(change: String) throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let interaction = PendingInteraction(
			id: "same-id",
			threadId: "replay",
			turnId: "turn",
			itemId: "command",
			approvalId: nil,
			kind: .commandApproval,
			reason: nil,
			command: "swift test",
			cwd: "/tmp/replay",
			grantRoot: nil,
			networkHost: nil,
			networkProtocol: nil,
			questions: [],
			requestedPermissions: nil,
			additionalPermissions: nil,
			availableDecisions: [.decline]
		)
		var pending = ConversationSnapshot(
			projectPath: "/tmp/replay",
			threads: [],
			selectedThreadID: "replay",
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: .awaitingApproval,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [interaction],
			recentProjects: []
		)
		var responses: [String] = []
		controller.onRespond =
		{
			_, _ in responses.append("store-a")
		}
		pending.workspaceOwner = ConversationPresentationTestFixture
			.presentationOwner(sessionID: UUID())
		controller.render(ConversationPresentation(pending))
		let oldCard = try #require(findInteractionCard(in: controller.view))
		let oldDeny = try #require(findButton(
			in: oldCard,
			title: "Deny"
		))
		controller.onRespond =
		{
			_, _ in responses.append("store-b")
		}
		if change == "session"
		{
			pending.workspaceOwner = ConversationPresentationTestFixture
				.presentationOwner(sessionID: UUID())
		}
		else
		{
			pending.workspaceSelectionEpoch += 1
		}
		controller.render(ConversationPresentation(pending))
		let currentCard = try #require(findInteractionCard(in: controller.view))
		#expect(currentCard !== oldCard)
		oldDeny.performClick(nil)
		#expect(responses == ["store-a"])
		try #require(findButton(
			in: currentCard,
			title: "Deny"
		)).performClick(nil)
		#expect(responses == ["store-a", "store-b"])
	}

	private func findInteractionCard(in view: NSView) -> InteractionCardView?
	{
		if let card = view as? InteractionCardView
		{
			return card
		}
		return view.subviews.lazy.compactMap
		{
			findInteractionCard(in: $0)
		}.first
	}

	@Test func bookmarkAvailabilityTracksSelectionWithoutAnotherRender() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 700,
				height: 760
			),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = controller
		window.setContentSize(NSSize(
			width: 700,
			height: 760
		))
		controller.render(
			snapshot([ConversationEntry(
				id: "turn:answer",
				kind: .agent,
				title: "Codex",
				body: "Answer"
			)])
		)
		await controller.waitForRendering()
		let collection = try #require(findCollection(in: controller.view))
		let bookmark = try #require(findButton(
			in: controller.view,
			title: "Bookmark Selected…"
		))
		let selected: Set<IndexPath> = [IndexPath(
			item: 0,
			section: 0
		)]
		#expect(!bookmark.isEnabled)

		// Programmatic selection does not send the delegate events that a user click sends.
		collection.selectItems(
			at: selected,
			scrollPosition: []
		)
		collection.delegate?.collectionView?(collection, didSelectItemsAt: selected)
		#expect(bookmark.isEnabled)
		collection.deselectItems(at: selected)
		collection.delegate?.collectionView?(collection, didDeselectItemsAt: selected)
		#expect(!bookmark.isEnabled)
	}

	@Test func smallWindowKeepsDraftContextAndApprovalDetailsScrollable() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 360,
				height: 415
			),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = controller
		window.setContentSize(NSSize(
			width: 360,
			height: 415
		))
		let approval = PendingInteraction(
			id: "approval",
			threadId: "replay",
			turnId: "turn",
			itemId: "command",
			approvalId: nil,
			kind: .commandApproval,
			reason: String(
				repeating: "Inspect the requested command. ",
				count: 8
			),
			command: "swift test",
			cwd: "/tmp/replay",
			grantRoot: nil,
			networkHost: nil,
			networkProtocol: nil,
			questions: [],
			requestedPermissions: nil,
			additionalPermissions: nil,
			availableDecisions: [.accept, .decline]
		)
		var draft = ConversationSnapshot(
			projectPath: "/tmp/replay",
			threads: [],
			selectedThreadID: "replay",
			entries: [],
			canLoadEarlierTurns: true,
			changedFiles: [],
			diff: "",
			draft: String(
				repeating: "Long editable request\n",
				count: 30
			),
			canSend: false,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: .awaitingApproval,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [approval],
			recentProjects: []
		)
		draft.activeThreadID = "replay"
		draft.activeExecutionState = .awaitingApproval
		draft.activeActivity = "Waiting for approval"
		draft.draftContext = (1 ... 8).map
		{
			ComposerContextItem(
				kind: .fileReference,
				title: "Reference \($0)",
				path: "Sources/File\($0)"
			)
		}
		controller.render(draft)
		controller.view.layoutSubtreeIfNeeded()
		#expect(controller.view.fittingSize.height <= controller.view.bounds.height + 1)
		let details = try #require(findBoundedScroll(in: controller.view))
		#expect(!details.isHidden)
		#expect(details.frame.height >= 36)
		#expect(details.frame.height <= 140)
		#expect(try #require(details.documentView).frame.height > details.contentSize.height)
		let message = try #require(findTextView(
			in: controller.view,
			label: "Message to Codex"
		))
		#expect(try #require(message.enclosingScrollView).frame.height >= 50)
	}

	@Test func changesPaneResizesExistingAndStreamedItems() async throws
	{
		_ = NSApplication.shared
		let defaults = try #require(UserDefaults(suiteName: "ConversationLayoutTests.\(UUID())"))
		let state = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults))
		let windowController = MainWindowController(
			store: state.store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			}
		)
		let window = try #require(windowController.window)
		let split = windowController.paneController.split
		let controller = try #require(
			split.splitViewItems[1].viewController as? ConversationViewController
		)
		let collection = try #require(findCollection(in: controller.view))
		var entries = (0 ..< 30).map
		{
			ConversationEntry(
				id: "message-\($0)",
				kind: .agent,
				title: "Codex",
				body: String(
					repeating: "Streamed message content ",
					count: 8
				)
			)
		}
		split.view.layoutSubtreeIfNeeded()
		controller.render(snapshot(entries))
		await controller.waitForRendering()
		collection.layoutSubtreeIfNeeded()

		for collapsed in [true, false, true, false]
		{
			split.splitViewItems[2].isCollapsed = collapsed
			split.view.layoutSubtreeIfNeeded()
			collection.layoutSubtreeIfNeeded()
			for index in [0, entries.count - 1]
			{
				let attributes = try #require(
					collection.layoutAttributesForItem(at: IndexPath(
						item: index,
						section: 0
					))
				)
				#expect(attributes.frame.maxX <= collection.bounds.width - 8)
			}
			entries[0].body += "\nMore output"
			entries.append(
				ConversationEntry(
					id: "message-\(entries.count)",
					kind: .agent,
					title: "Codex",
					body: "More output"
				)
			)
			controller.render(snapshot(entries))
			await controller.waitForRendering()
			collection.layoutSubtreeIfNeeded()
		}
	}

	@Test func streamingCanReloadExistingItemsAndInsertNewItemsInTheSameSnapshot() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 700,
				height: 760
			),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = controller
		window.setContentSize(NSSize(
			width: 700,
			height: 760
		))
		let collection = try #require(findCollection(in: controller.view))
		controller.view.layoutSubtreeIfNeeded()
		var entries = [
			ConversationEntry(
				id: "command",
				kind: .command,
				title: "Command",
				body: "start"
			)
		]
		controller.render(snapshot(entries))
		await controller.waitForRendering()
		collection.layoutSubtreeIfNeeded()
		#expect(collection.numberOfItems(inSection: 0) == 1)
		let firstItemPath = IndexPath(
			item: 0,
			section: 0
		)
		let initialItem = try #require(collection.item(at: firstItemPath))
		#expect(
			try #require(findTextView(
				in: initialItem.view,
				label: "Command content"
			))
			.string == "start"
		)

		for index in 1 ... 30
		{
			entries[0].body += "\nOutput \(index)"
			entries.append(
				ConversationEntry(
					id: "message-\(index)",
					kind: .agent,
					title: "Codex",
					body: "Message \(index)"
				)
			)
			controller.render(snapshot(entries))
			await controller.waitForRendering()
			collection.layoutSubtreeIfNeeded()
			#expect(collection.numberOfItems(inSection: 0) == entries.count)
			collection.scrollToItems(
				at: [firstItemPath],
				scrollPosition: .top
			)
			collection.layoutSubtreeIfNeeded()
			let changedItem = try #require(collection.item(at: firstItemPath))
			let changedText = try #require(findTextView(
				in: changedItem.view,
				label: "Command content"
			))
			#expect(changedText.string == entries[0].body)
		}

		entries[0].body = "Finished"
		controller.render(snapshot(entries))
		await controller.waitForRendering()
		collection.layoutSubtreeIfNeeded()
		#expect(collection.numberOfItems(inSection: 0) == 31)
		collection.scrollToItems(
			at: [firstItemPath],
			scrollPosition: .top
		)
		collection.layoutSubtreeIfNeeded()
		let finishedItem = try #require(collection.item(at: firstItemPath))
		#expect(
			try #require(findTextView(
				in: finishedItem.view,
				label: "Command content"
			)).string
				== "Finished"
		)

		for width in [450.0, 900.0, 380.0]
		{
			window.setContentSize(NSSize(
				width: width,
				height: 760
			))
			controller.view.layoutSubtreeIfNeeded()
			collection.layoutSubtreeIfNeeded()
			let attributes = try #require(
				collection.layoutAttributesForItem(at: IndexPath(
					item: 0,
					section: 0
				))
			)
			#expect(attributes.frame.maxX <= collection.bounds.width - 8)
		}

		entries = [
			ConversationEntry(
				id: "other-thread",
				kind: .user,
				title: "You",
				body: "Another chat"
			)
		]
		controller.render(snapshot(entries))
		await controller.waitForRendering()
		collection.layoutSubtreeIfNeeded()
		#expect(collection.numberOfItems(inSection: 0) == 1)
		#expect(controller.collectionView(
			collection,
			numberOfItemsInSection: 0
		) == 1)
	}

	@Test func earlierReadingPositionSurvivesStreamingAndHistoryPrepend() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 700,
				height: 760
			),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = controller
		window.setContentSize(NSSize(
			width: 700,
			height: 760
		))
		controller.view.layoutSubtreeIfNeeded()
		let collection = try #require(findCollection(in: controller.view))
		let scroll = try #require(collection.enclosingScrollView)
		var entries = (0 ..< 80).map
		{
			ConversationEntry(
				id: "entry-\($0)",
				kind: .agent,
				title: "Codex",
				body: "## Message \($0)\n\n" + String(
					repeating: "Readable text. ",
					count: 20
				)
			)
		}
		controller.render(snapshot(entries))
		await controller.waitForRendering()
		let first = try #require(
			collection.layoutAttributesForItem(at: IndexPath(
				item: 20,
				section: 0
			))
		)
		scroll.contentView.scroll(to: NSPoint(
			x: 0,
			y: first.frame.minY + 12
		))
		scroll.reflectScrolledClipView(scroll.contentView)
		let relativeY = first.frame.minY - scroll.contentView.bounds.minY
		entries[0].body += String(
			repeating: "Earlier entry grew. ",
			count: 30
		)
		entries.append(ConversationEntry(
			id: "new",
			kind: .agent,
			title: "Codex",
			body: "New output"
		))
		controller.render(snapshot(entries))
		await controller.waitForRendering()
		let updated = try #require(
			collection.layoutAttributesForItem(at: IndexPath(
				item: 20,
				section: 0
			))
		)
		#expect(abs(updated.frame.minY - scroll.contentView.bounds.minY - relativeY) < 1)

		entries.insert(
			ConversationEntry(
				id: "older",
				kind: .user,
				title: "You",
				body: "Older history"
			),
			at: 0
		)
		controller.render(snapshot(entries))
		await controller.waitForRendering()
		let prepended = try #require(
			collection.layoutAttributesForItem(at: IndexPath(
				item: 21,
				section: 0
			))
		)
		#expect(abs(prepended.frame.minY - scroll.contentView.bounds.minY - relativeY) < 1)
		let latest = try #require(findButton(
			in: controller.view,
			title: "Latest Message"
		))
		#expect(!latest.isHidden)
		latest.performClick(nil)
		#expect(collection.bounds.maxY - scroll.contentView.bounds.maxY < 48)
	}

	@Test func browsingAnotherConversationKeepsDraftEditableAndRoutesBackToTask() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		_ = controller.view
		var returned = false
		controller.onReturnToActiveTask =
		{
			returned = true
		}
		var otherConversation = snapshot([])
		otherConversation.activeThreadID = "working"
		otherConversation.activeExecutionState = .awaitingApproval
		controller.render(otherConversation)

		let returnButton = try #require(findButton(
			in: controller.view,
			title: "Return to Task"
		))
		let stopButton = try #require(findButton(
			in: controller.view,
			title: "Stop"
		))
		let sendButton = try #require(findButton(
			in: controller.view,
			title: "Send"
		))
		let composer = try #require(findTextView(
			in: controller.view,
			label: "Message to Codex"
		))
		#expect(!returnButton.isHidden)
		#expect(returnButton.isEnabled)
		#expect(!stopButton.isEnabled)
		#expect(!sendButton.isEnabled)
		#expect(composer.isEditable)
		returnButton.performClick(nil)
		#expect(returned)

		var activeConversation = otherConversation
		activeConversation.activeThreadID = "replay"
		activeConversation.activeExecutionState = .running
		activeConversation.canSteer = true
		controller.render(activeConversation)
		#expect(stopButton.isEnabled)
		#expect(returnButton.isHidden)
	}

	@Test func taskProgressUsesReportedPlanAndActivity() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		_ = controller.view
		let plan = try #require(
			TurnPlanUpdate(json: [
				"threadId": "replay",
				"turnId": "turn-1",
				"plan": [
					["step": "Inspect", "status": "completed"],
					["step": "Fix", "status": "inProgress"],
				],
			])
		)
		var active = snapshot([])
		active.activeThreadID = "replay"
		active.activeExecutionState = .running
		active.activePlan = plan
		active.activeActivity = "Running a command"
		controller.render(active)
		let planButton = try #require(findButton(
			in: controller.view,
			title: "Plan 1/2"
		))
		let activity = try #require(findLabel(
			in: controller.view,
			label: "Reported task activity"
		))
		#expect(!planButton.isHidden)
		#expect(activity.stringValue == "Running a command")

		active.activePlan = nil
		active.activeActivity = nil
		controller.render(active)
		#expect(planButton.isHidden)
		#expect(activity.stringValue.isEmpty)
	}

	@Test func interruptedTaskShowsStoppedAcrossViews() throws
	{
		_ = NSApplication.shared
		let thread = try #require(
			ThreadSummary(json: [
				"id": "replay",
				"name": "Interrupted work",
				"cwd": "/tmp/replay",
			])
		)
		var stopped = snapshot(
			[],
			executionState: .stopped,
			threads: [thread]
		)
		stopped.activeThreadID = "replay"
		stopped.activeExecutionState = .stopped
		let conversation = ConversationViewController()
		_ = conversation.view
		conversation.render(stopped)
		let stateLabel = try #require(findLabel(
			in: conversation.view,
			label: "Execution state"
		))
		let stopButton = try #require(findButton(
			in: conversation.view,
			title: "Stop"
		))
		#expect(stateLabel.stringValue == "Stopped")
		#expect(!stopButton.isEnabled)

		let navigation = NavigationViewController()
		_ = navigation.view
		navigation.render(stopped)
		let projectActions = try #require(findButton(
			in: navigation.view,
			title: "Project Actions"
		))
		let table = try #require(findTable(in: navigation.view))
		let row = try #require(table.view(
			atColumn: 0,
			row: 1,
			makeIfNecessary: true
		))
		#expect(projectActions.toolTip?.contains("Task: Stopped") == true)
		#expect(row.accessibilityLabel()?.contains("Stopped task") == true)
	}

	private func findButton(
		in view: NSView,
		title: String
	) -> NSButton?
	{
		if let button = view as? NSButton, button.title == title
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			findButton(
				in: $0,
				title: title
			)
		}.first
	}

	private func findBoundedScroll(in view: NSView) -> BoundedContentScrollView?
	{
		if let scroll = view as? BoundedContentScrollView
		{
			return scroll
		}
		return view.subviews.lazy.compactMap
		{
			findBoundedScroll(in: $0)
		}.first
	}

	private func findCollection(in view: NSView) -> NSCollectionView?
	{
		if let collection = view as? NSCollectionView
		{
			return collection
		}
		return view.subviews.lazy.compactMap
		{
			findCollection(in: $0)
		}.first
	}

	private func findTable(in view: NSView) -> NSTableView?
	{
		if let table = view as? NSTableView
		{
			return table
		}
		return view.subviews.lazy.compactMap
		{
			findTable(in: $0)
		}.first
	}

	private func findTextView(
		in view: NSView,
		label: String
	) -> NSTextView?
	{
		if let textView = view as? NSTextView, textView.accessibilityLabel() == label
		{
			return textView
		}
		return view.subviews.lazy.compactMap
		{
			findTextView(
				in: $0,
				label: label
			)
		}.first
	}

	private func findLabel(
		in view: NSView,
		label: String
	) -> NSTextField?
	{
		if let textField = view as? NSTextField, textField.accessibilityLabel() == label
		{
			return textField
		}
		return view.subviews.lazy.compactMap
		{
			findLabel(
				in: $0,
				label: label
			)
		}.first
	}

	@Test func activityDisclosuresSurviveStreamingAndJumpExpandsBackingSource() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		var entry = ConversationEntry(
			id: "turn:command",
			kind: .command,
			title: "Command",
			body: "",
			activity: .command(ConversationCommand(
				command: "echo hello",
				cwd: "/tmp",
				output: "",
				status: "inProgress",
				exitCode: nil,
				durationMs: nil,
				actions: []
			))
		)
		controller.render(snapshot([entry]))
		await controller.waitForRendering()
		guard case .activity(let command) = controller.displayedRows[1]
		else
		{
			Issue.record("Expected command activity"); return
		}
		controller.toggleActivity(command)
		await controller.waitForRendering()
		entry.activity = .command(ConversationCommand(
			command: "echo hello",
			cwd: "/tmp",
			output: "hello",
			status: "completed",
			exitCode: 0,
			durationMs: 20,
			actions: []
		))
		controller.render(snapshot([entry]))
		await controller.waitForRendering()
		guard case .activity(let streamed) = controller.displayedRows[1],
				case .activity(let group) = controller.displayedRows[0]
		else
		{
			Issue.record("Expected retained activities"); return
		}
		#expect(streamed.expanded)
		#expect(streamed.command?.output == "hello")
		controller.toggleActivity(group)
		await controller.waitForRendering()
		#expect(controller.displayedRows.count == 1)
		controller.jumpToEntry(id: entry.id)
		await controller.waitForRendering()
		#expect(controller.displayedRows.count == 2)
		#expect(controller.requestedJumpItemID == nil)
		#expect(controller.bookmarkButton.isEnabled)
		#expect(controller.entries == [entry])
	}

	@Test func retainedActivityCallbacksCannotChangeOrOpenAnotherOwner() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let entry = ConversationEntry(
			id: "turn:read",
			kind: .command,
			title: "Read",
			body: "",
			activity: .command(ConversationCommand(
				command: "cat file",
				cwd: "/tmp",
				output: "",
				status: "completed",
				exitCode: 0,
				durationMs: nil,
				actions: [CodexCommandAction(
					kind: .read,
					command: "cat file",
					path: "file"
				)]
			))
		)
		var initial = snapshot([entry])
		initial.workspaceOwner = ConversationPresentationTestFixture
			.presentationOwner(sessionID: UUID())
		controller.render(initial)
		await controller.waitForRendering()
		let retained = controller.collectionView(
			controller.collectionView,
			itemForRepresentedObjectAt: IndexPath(
				item: 1,
				section: 0
			)
		)
		var opened: [String] = []
		controller.onOpenActivityFile =
		{
			opened.append($0)
		}
		var replacement = snapshot([entry])
		replacement.workspaceOwner = ConversationPresentationTestFixture
			.presentationOwner(sessionID: UUID())
		controller.render(replacement)
		_ = retained.perform(NSSelectorFromString("toggle"))
		_ = retained.perform(NSSelectorFromString("openFile"))
		await controller.waitForRendering()
		_ = retained.perform(NSSelectorFromString("toggle"))
		_ = retained.perform(NSSelectorFromString("openFile"))
		#expect(opened.isEmpty)
		#expect(controller.expandedActivityIDs.isEmpty)
		#expect(controller.collapsedGroupIDs.isEmpty)
	}

	@Test func terminalExecutionStopsTimingAndTimingRowsCannotBeBookmarked() async
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let entry = ConversationEntry(
			id: "turn:user",
			kind: .user,
			title: "You",
			body: "Request"
		)
		var active = snapshot([entry])
		active.activeThreadID = "replay"
		active.activeTurnID = "turn"
		active.turnTimings = [ConversationTurnTiming(
			turnID: "turn",
			status: "inProgress",
			startedAt: Date(timeIntervalSince1970: 1)
		)]
		controller.render(active)
		await controller.waitForRendering()
		#expect(controller.turnStatusTimer != nil)
		controller.collectionView.selectItems(
			at: [IndexPath(
				item: 1,
				section: 0
			)],
			scrollPosition: .top
		)
		controller.updateBookmarkButton()
		#expect(!controller.bookmarkButton.isEnabled)
		var terminal = snapshot(
			[entry],
			executionState: .disconnected
		)
		terminal.turnTimings = active.turnTimings
		controller.render(terminal)
		await controller.waitForRendering()
		#expect(controller.turnStatusTimer == nil)
		guard case .turnStatus(let timing) = controller.displayedRows[1]
		else
		{
			Issue.record("Expected timing row"); return
		}
		#expect(timing.status == "statusUnknown")
		#expect(timing.completedAt == nil)
		#expect(timing.durationMs == nil)
		controller.viewDidDisappear()
	}

	@Test func innerShellReadingPositionSurvivesDisclosureAndStaysScoped() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let command = ConversationCommand(
			command: "echo output",
			cwd: "/tmp",
			output: String(
				repeating: "line of output\n",
				count: 200
			),
			status: "completed",
			exitCode: 0,
			durationMs: nil,
			actions: []
		)
		let entry = ConversationEntry(
			id: "turn:command",
			kind: .command,
			title: "Command",
			body: "",
			activity: .command(command)
		)
		controller.render(snapshot([entry]))
		await controller.waitForRendering()
		guard case .activity(let row) = controller.displayedRows[1]
		else
		{
			return
		}
		controller.toggleActivity(row)
		await controller.waitForRendering()
		let item = try #require(controller.collectionView(
			controller.collectionView,
			itemForRepresentedObjectAt: IndexPath(
				item: 1,
				section: 0
			)
		)
			as? ConversationActivityCollectionItem)
		func layout(_ item: ConversationActivityCollectionItem)
		{
			item.view.frame = NSRect(
				x: 0,
				y: 0,
				width: 500,
				height: 314
			)
			item.view.layoutSubtreeIfNeeded()
			item.viewDidLayout()
		}
		layout(item)
		item.restoreOutputReadingPosition(.init(
			origin: NSPoint(
				x: 0,
				y: 80
			),
			selection: NSRange(
				location: 20,
				length: 10
			)
		))
		layout(item)
		controller.collectionView(
			controller.collectionView,
			didEndDisplaying: item,
			forRepresentedObjectAt: IndexPath(
				item: 1,
				section: 0
			)
		)
		#expect(try #require(controller.activityOutputPositions[row.id]).origin.y == 80)
		controller.toggleActivity(row)
		await controller.waitForRendering()
		controller.toggleActivity(row)
		await controller.waitForRendering()
		let reopened = try #require(controller.collectionView(
			controller.collectionView,
			itemForRepresentedObjectAt: IndexPath(
				item: 1,
				section: 0
			)
		)
			as? ConversationActivityCollectionItem)
		layout(reopened)
		#expect(try #require(reopened.outputReadingPosition()).origin.y == 80)
		#expect(try #require(reopened.outputReadingPosition()).selection.length == 10)
		var other = snapshot([entry])
		other.workspaceOwner = ConversationPresentationTestFixture
			.presentationOwner(sessionID: UUID())
		controller.render(other)
		await controller.waitForRendering()
		#expect(controller.activityOutputPositions.isEmpty)
	}

	@Test func onlyMatchingActiveTurnCanTickAndHistoricalOutcomeStaysUnknown() async
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let entries = ["old", "new"].map
		{
			ConversationEntry(
				id: "\($0):user",
				kind: .user,
				title: "You",
				body: "Request"
			)
		}
		var active = snapshot(entries)
		active.activeThreadID = "replay"
		active.activeTurnID = "new"
		active.turnTimings = ["old", "new"].map
		{
			ConversationTurnTiming(
				turnID: $0,
				status: "inProgress",
				startedAt: Date()
			)
		}
		controller.render(active)
		await controller.waitForRendering()
		#expect(controller.requestedTurnTimings.map(\.status) == ["statusUnknown", "inProgress"])
		#expect(controller.turnStatusTimer != nil)
		active.activeThreadID = "other"
		controller.render(active)
		await controller.waitForRendering()
		#expect(controller.requestedTurnTimings.allSatisfy
		{
			$0.status == "statusUnknown"
		})
		#expect(controller.turnStatusTimer == nil)
		#expect(active.turnTimings.allSatisfy
		{
			$0.status == "inProgress"
		})
	}

	@Test func compactActivityFramesPreserveMessageSpacingAndBottomNavigation() async throws
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
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		let command = ConversationCommand(
			command: "echo output",
			cwd: "/tmp",
			output: "",
			status: "completed",
			exitCode: 0,
			durationMs: nil,
			actions: []
		)
		let commands = ["a", "b"].map
		{
			ConversationEntry(
				id: "turn:\($0)",
				kind: .command,
				title: "Command",
				body: "",
				activity: .command(command)
			)
		}
		let messages = (0 ..< 50).map
		{
			ConversationEntry(
				id: "turn:message-\($0)",
				kind: .agent,
				title: "Codex",
				body: "Answer"
			)
		}
		controller.render(snapshot(commands + messages))
		await controller.waitForRendering()
		controller.view.layoutSubtreeIfNeeded()
		let collection = controller.collectionView
		collection.layoutSubtreeIfNeeded()
		let frames = try controller.displayedRows.indices.map
		{
			try #require(collection.layoutAttributesForItem(at: IndexPath(
				item: $0,
				section: 0
			)))
			.frame
		}
		#expect(abs(frames[1].minY - frames[0].minY - 30) < 1)
		#expect(abs(frames[2].minY - frames[1].minY - 30) < 1)
		#expect(abs(frames[3].minY - frames[2].maxY - 18) < 1)
		#expect(abs(frames[4].minY - frames[3].maxY - 18) < 1)
		let layout = try #require(collection.collectionViewLayout)
		#expect(frames.allSatisfy
		{
			$0.maxY <= layout.collectionViewContentSize.height
		})
		controller.jumpToEntry(id: try #require(messages.last).id)
		#expect(controller.requestedJumpItemID == nil)
		#expect(collection.selectionIndexPaths.first?.item == controller.displayedRows.count - 1)
		let rectFrames = layout.layoutAttributesForElements(in: frames[2]).map(\.frame)
		#expect(rectFrames.contains(frames[2]))
		window.orderOut(nil)
	}

	private func snapshot(
		_ entries: [ConversationEntry],
		executionState: ExecutionState = .running,
		threads: [ThreadSummary] = []
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/replay",
			threads: threads,
			selectedThreadID: "replay",
			entries: entries,
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: executionState,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
	}
}
