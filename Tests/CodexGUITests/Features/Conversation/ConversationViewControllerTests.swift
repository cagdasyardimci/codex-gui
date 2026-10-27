import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ConversationViewControllerTests
{

	@Test(.timeLimit(.minutes(1)))
	func immediatePendingRowPreservesHistoryAndSupersededChatCannotReturn() async throws
	{
		_ = NSApplication.shared
		let gate = TranscriptPreparationTestGate(heldBody: "First request")
		defer
		{
			gate.release()
		}
		let preparation = TranscriptPreparationCoordinator(prepareContent: gate.prepare)
		let controller = ConversationViewController(transcriptPreparation: preparation)
		let history = ConversationEntry(
			id: "turn:reply",
			kind: .agent,
			title: "Codex",
			body: "**Previous reply**"
		)
		controller.render(snapshot([history]))
		await controller.waitForRendering()
		let prepared = try #require(controller.transcript.preparedContents[history.id])
		let first = ConversationEntry(
			id: "local:first",
			kind: .user,
			title: "You",
			body: "First request"
		)
		controller.render(snapshot([history, first]))
		#expect(controller.transcript.entries == [history, first])
		#expect(controller.transcript.preparedContents[history.id] === prepared)
		let obsoleteTask = preparation.preparationTask
		#expect(obsoleteTask != nil)
		let started = await gate.waitUntilStarted()
		#expect(started)
		guard started
		else
		{
			gate.release()
			await obsoleteTask?.value
			return
		}
		let second = ConversationEntry(
			id: "local:second",
			kind: .user,
			title: "You",
			body: "Second request"
		)
		let edit = ConversationEntry(
			id: "local:edit",
			kind: .tool,
			title: "Changes",
			body: "Current.swift",
			activity: .fileChanges(
				[FileChange(json: [
					"path": "Current.swift",
					"kind": "update",
					"diff": "@@ -1 +1 @@\n-before\n+current",
				])!],
				status: "completed"
			)
		)
		let reply = ConversationEntry(
			id: "local:reply",
			kind: .agent,
			title: "Codex",
			body: "**Current** answer"
		)
		let currentEntries = [second, edit, reply]
		var current = snapshot(
			currentEntries,
			selectedThreadID: "other"
		)
		current.turnTimings = [ConversationTurnTiming(
			turnID: "local",
			status: "completed",
			startedAt: nil,
			completedAt: nil,
			durationMs: nil
		)]
		controller.render(current)
		#expect(controller.transcript.entries == [second])
		#expect(controller.transcript.preparedContents[history.id] == nil)
		await controller.waitForRendering()
		#expect(controller.transcript.entries == currentEntries)
		#expect(controller.transcript.preparedContents[reply.id]?.attributedString
			.string == "Current answer")
		#expect(controller.transcript.turnNavigationRail.summaries
			.map(\.reply) == ["Current answer"])
		gate.release()
		await obsoleteTask?.value
		#expect(controller.transcript.selectedThreadID == "other")
		#expect(controller.transcript.entries == currentEntries)
		#expect(controller.transcript.displayedRows.map(\.id)
			== [second.id, reply.id, "local:file-change-summary"])
		#expect(controller.transcript.preparedContents[history.id] == nil)
		#expect(controller.transcript.preparedContents[first.id] == nil)
		#expect(controller.transcript.preparedContents[reply.id]?.attributedString
			.string == "Current answer")
		#expect(controller.transcript.turnNavigationRail.summaries.map(\.entryID) == [second.id])
		#expect(controller.transcript.turnNavigationRail.summaries
			.map(\.title) == ["Second request"])
		#expect(controller.transcript.turnNavigationRail.summaries
			.map(\.reply) == ["Current answer"])
		#expect(preparation.preparedNetChanges["local"]?.changes.map(\.path) == ["Current.swift"])
		#expect(preparation.preparedNetChanges["local"]?.changes.map(\.diff)
			== ["@@ -1,1 +1,1 @@\n-before\n+current"])
	}

	@Test func userAndAgentMarkdownRenderWhileOtherRolesKeepLiteralSource() async throws
	{
		_ = NSApplication.shared
		let body = "# Shared heading\n\n**bold** [site](https://example.com/path)\n\n"
			+ "| Name | Value |\n| --- | --- |\n| item | 42 |\n\n"
			+ "```swift\n  let value = \"😀\"  \n```"
		let kinds: [ConversationEntryKind] = [.user, .agent, .command, .tool, .notice]
		let entries = kinds.enumerated().map
		{
			index, kind in
			ConversationEntry(
				id: "role-\(index)",
				kind: kind,
				title: "Role",
				body: body
			)
		}
		let controller = ConversationViewController()
		controller.render(snapshot(entries))
		await controller.waitForRendering()
		#expect(controller.transcript.entries == entries)
		for entry in entries
		{
			let content = try #require(controller.transcript.preparedContents[entry.id])
			let display = content.attributedString
			if entry.kind == .user || entry.kind == .agent
			{
				#expect(!display.string.contains("# Shared heading"))
				#expect(display.string.contains("Shared heading"))
				#expect(!display.string.contains("**bold**"))
				#expect(content.codeBlocks == ["  let value = \"😀\"  \n"])
				let link = (display.string as NSString).range(of: "site")
				#expect((display.attribute(
					.link,
					at: link.location,
					effectiveRange: nil
				)
					as? URL)?.absoluteString == "https://example.com/path")
				let cell = (display.string as NSString).range(of: "item")
				let paragraph = try #require(display.attribute(
					.paragraphStyle,
					at: cell.location,
					effectiveRange: nil
				) as? NSParagraphStyle)
				#expect(paragraph.textBlocks.first is NSTextTableBlock)
			}
			else
			{
				#expect(display.string == body)
				#expect(content.codeBlocks.isEmpty)
				#expect(content.codeBlockRanges.isEmpty)
				#expect(display.attribute(
					.link,
					at: 0,
					effectiveRange: nil
				) == nil)
			}
			#expect(entry.body == body)
		}
	}

	@Test func userSoftBreaksRemainVisibleWithoutChangingAgentOrLiteralPreparation() async throws
	{
		_ = NSApplication.shared
		let body = "First line\nSecond line\n\n**formatted**"
		let entries: [ConversationEntry] = [
			ConversationEntry(
				id: "user",
				kind: .user,
				title: "You",
				body: body
			),
			ConversationEntry(
				id: "agent",
				kind: .agent,
				title: "Codex",
				body: body
			),
			ConversationEntry(
				id: "tool",
				kind: .tool,
				title: "Tool",
				body: body
			),
		]
		let controller = ConversationViewController()
		controller.render(snapshot(entries))
		await controller.waitForRendering()
		let user = try #require(controller.transcript.preparedContents["user"])
		let agent = try #require(controller.transcript.preparedContents["agent"])
		let tool = try #require(controller.transcript.preparedContents["tool"])
		#expect(user.attributedString.string == "First line\nSecond line\nformatted")
		#expect(agent.attributedString.string == "First line Second line\nformatted")
		#expect(tool.attributedString.string == body)
		#expect(user !== agent)
		#expect(controller.transcript.entries == entries)
	}

	@Test(.timeLimit(.minutes(1)))
	func sameTranscriptInAnotherStoreCancelsOldPreparationAndKeepsCurrentDraft() async throws
	{
		_ = NSApplication.shared
		let obsoleteBody = String(
			repeating: "Obsolete streamed markdown **text**.\n",
			count: 100
		)
		let gate = TranscriptPreparationTestGate(heldBody: obsoleteBody)
		let preparation = TranscriptPreparationCoordinator(prepareContent: gate.prepare)
		let controller = ConversationViewController(transcriptPreparation: preparation)
		var startedPreparations: [Task<Void, Never>] = []
		func render(_ snapshot: ConversationSnapshot)
		{
			controller.render(ConversationPresentation(snapshot))
			if let task = preparation.preparationTask
			{
				startedPreparations.append(task)
			}
		}
		func finishPreparations() async
		{
			gate.release()
			for task in startedPreparations
			{
				task.cancel()
				await task.value
			}
		}
		do
		{
			_ = controller.view
			let entry = ConversationEntry(
				id: "turn:answer",
				kind: .agent,
				title: "Codex",
				body: "The same reported answer"
			)
			let originalOwner = ConversationPresentationTestFixture
				.presentationOwner(sessionID: UUID())
			var initial = snapshot([entry])
			initial.workspaceOwner = originalOwner
			render(initial)
			await controller.waitForRendering()
			let previousCollection = try #require(findCollection(in: controller.view))
			let old = ConversationEntry(
				id: entry.id,
				kind: .agent,
				title: "Codex",
				body: obsoleteBody
			)
			var obsolete = snapshot([old])
			obsolete.workspaceOwner = originalOwner
			render(obsolete)
			let obsoleteTask = try #require(preparation.preparationTask)
			try #require(await gate.waitUntilStarted())
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
			render(current)
			await controller.waitForRendering()
			let collection = try #require(findCollection(in: controller.view))
			#expect(collection !== previousCollection)
			#expect(collection.numberOfItems(inSection: 0) == 1)
			#expect(controller.transcript.entries == [entry])
			#expect(controller.transcript.displayedRows.map(\.id) == [entry.id])
			#expect(controller.transcript.preparedContents[entry.id]?.attributedString.string
				== "The same reported answer")
			gate.release()
			await obsoleteTask.value
			#expect(controller.transcript.entries == [entry])
			#expect(controller.transcript.displayedRows.map(\.id) == [entry.id])
			#expect(controller.transcript.preparedContents[entry.id]?.attributedString.string
				== "The same reported answer")
			#expect(findCollection(in: controller.view) === collection)
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
			render(current)
			await controller.waitForRendering()
			#expect(findCollection(in: controller.view) === collection)
			#expect(composer.selectedRange() == NSRange(
				location: 3,
				length: 5
			))
			await finishPreparations()
		}
		catch
		{
			await finishPreparations()
			throw error
		}
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

	@Test(arguments: [
		ExecutionState.running,
		.awaitingApproval,
		.awaitingAnswer,
	])
	func composerSharesOneActionSlotAcrossDraftChanges(state: ExecutionState) throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		func activeSnapshot(draft: String = "") -> ConversationSnapshot
		{
			var active = snapshot(
				[],
				draft: draft,
				canSend: true
			)
			active.activeThreadID = "replay"
			active.activeExecutionState = state
			active.canSteer = true
			return active
		}
		var stops = 0
		var sends = 0
		var steered: [String] = []
		controller.onStop =
		{
			stops += 1
		}
		controller.onSend =
		{
			sends += 1
		}
		controller.onSteer =
		{
			steered.append($0)
		}
		let buttons = [controller.sendButton, controller.steerButton, controller.stopButton]

		for draft in ["", "Follow up", "", " \n"]
		{
			controller.render(activeSnapshot(draft: draft))
			let visible = buttons.filter
			{
				!$0.isHidden
			}
			#expect(visible.count == 1)
			let button = try #require(visible.first)
			#expect(button.isEnabled)
			if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			{
				#expect(button === controller.stopButton)
			}
			else
			{
				#expect(button === (state == .running
						? controller.steerButton : controller.sendButton))
			}
			try #require(button.dispatchConfiguredAction())
		}
		#expect(stops == 3)
		#expect(sends == (state == .running ? 0 : 1))
		#expect(steered == (state == .running ? ["Follow up"] : []))

		var active = activeSnapshot()
		active.draftContext = [ComposerContextItem(
			kind: .fileReference,
			title: "File"
		)]
		controller.render(active)
		#expect(controller.stopButton.isHidden)
		#expect(buttons.filter
		{
			!$0.isHidden
		}.count == 1)

		active.draftContext = []
		active.activeThreadID = "another-thread"
		controller.render(active)
		#expect(controller.stopButton.isHidden)
		#expect(controller.steerButton.isHidden)
		#expect(!controller.sendButton.isHidden)
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
		let second = ConversationEntry(
			id: "turn:second",
			kind: entry.kind,
			title: entry.title,
			body: entry.body,
			activity: entry.activity
		)
		controller.render(snapshot([entry, second]))
		await controller.waitForRendering()
		#expect(controller.transcript.displayedRows.count == 1)
		let initialGroup = try #require(controller.transcript.displayedRows.first)
		guard case .activity(let collapsedGroup) = initialGroup
		else
		{
			Issue.record("Expected collapsed group")
			return
		}
		#expect(collapsedGroup.kind == .group)
		#expect(!collapsedGroup.expanded)
		controller.transcript.toggleActivity(collapsedGroup)
		await controller.waitForRendering()
		#expect(controller.transcript.displayedRows.count == 3)
		guard case .activity(let command) = controller.transcript.displayedRows[1]
		else
		{
			Issue.record("Expected command activity")
			return
		}
		controller.transcript.toggleActivity(command)
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
		controller.render(snapshot([entry, second]))
		await controller.waitForRendering()
		guard case .activity(let streamed) = controller.transcript.displayedRows[1],
				case .activity(let group) = controller.transcript.displayedRows[0]
		else
		{
			Issue.record("Expected retained activities")
			return
		}
		#expect(streamed.expanded)
		#expect(streamed.command?.output == "hello")
		controller.transcript.toggleActivity(group)
		await controller.waitForRendering()
		#expect(controller.transcript.displayedRows.count == 1)
		controller.jumpToEntry(id: second.id)
		await controller.waitForRendering()
		#expect(controller.transcript.displayedRows.count == 3)
		#expect(controller.transcript.requestedJumpItemID == nil)
		#expect(controller.transcript.entries == [entry, second])
		let otherConversation = snapshot(
			[entry, second],
			selectedThreadID: "other"
		)
		controller.render(otherConversation)
		await controller.waitForRendering()
		#expect(controller.transcript.displayedRows.count == 1)
		#expect(controller.transcript.expandedGroupIDs.isEmpty)
		controller.render(snapshot([entry, second]))
		await controller.waitForRendering()
		#expect(controller.transcript.displayedRows.count == 1)
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
		let activityIndex = try #require(controller.transcript.displayedRows.firstIndex
		{
			$0.sourceEntryID == entry.id
		})
		let retained = controller.transcript.collectionView(
			controller.transcript.collectionView,
			itemForRepresentedObjectAt: IndexPath(
				item: activityIndex,
				section: 0
			)
		)
		var opened: [String] = []
		controller.transcript.onOpenActivityFile =
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
		#expect(controller.transcript.expandedActivityIDs.isEmpty)
		#expect(controller.transcript.collapsedImageIDs.isEmpty)
	}

	@Test func terminalExecutionStopsTiming() async
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
		#expect(controller.transcript.turnStatusTimer != nil)
		#expect(!controller.transcript.displayedRows.contains
		{
			if case .turnStatus = $0
			{
				true
			}
			else
			{
				false
			}
		})
		var terminal = snapshot(
			[entry],
			executionState: .disconnected
		)
		terminal.turnTimings = active.turnTimings
		controller.render(terminal)
		await controller.waitForRendering()
		#expect(controller.transcript.turnStatusTimer == nil)
		#expect(!controller.transcript.displayedRows.contains
		{
			if case .turnStatus = $0
			{
				true
			}
			else
			{
				false
			}
		})
		controller.viewDidDisappear()
	}

	@Test func innerShellReadingPositionSurvivesDisclosureAndStaysScoped() async throws
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
		window.prepareForTesting()
		window.contentViewController = controller
		defer
		{
			controller.transcript.collectionView.dataSource = nil
			controller.transcript.collectionView.delegate = nil
			window.contentViewController = nil
			window.close()
		}
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
		let activityIndex = try #require(controller.transcript.displayedRows.firstIndex
		{
			$0.sourceEntryID == entry.id
		})
		guard case .activity(let row) = controller.transcript.displayedRows[activityIndex]
		else
		{
			Issue.record("Expected command activity row")
			return
		}
		controller.transcript.toggleActivity(row)
		await controller.waitForRendering()
		let item = try #require(controller.transcript.collectionView.item(
			at: IndexPath(
				item: activityIndex,
				section: 0
			)
		)
			as? ConversationActivityCollectionItem)
		func layout(_ item: ConversationActivityCollectionItem)
		{
			controller.view.layoutSubtreeIfNeeded()
			item.view.layoutSubtreeIfNeeded()
			item.viewDidLayout()
		}
		layout(item)
		item.restoreOutputReadingPosition(ConversationActivityCollectionItem.OutputReadingPosition(
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
		controller.transcript.collectionView(
			controller.transcript.collectionView,
			didEndDisplaying: item,
			forRepresentedObjectAt: IndexPath(
				item: activityIndex,
				section: 0
			)
		)
		#expect(try #require(controller.transcript.activityOutputPositions[row.id]).origin.y == 80)
		controller.transcript.toggleActivity(row)
		await controller.waitForRendering()
		controller.transcript.toggleActivity(row)
		await controller.waitForRendering()
		let reopened = try #require(controller.transcript.collectionView.item(
			at: IndexPath(
				item: activityIndex,
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
		#expect(controller.transcript.activityOutputPositions.isEmpty)
	}

	private func snapshot(
		_ entries: [ConversationEntry],
		executionState: ExecutionState = .running,
		threads: [ThreadSummary] = [],
		selectedThreadID: String = "replay",
		draft: String = "",
		canSend: Bool = false,
		canLoadEarlierTurns: Bool = false
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/replay",
			threads: threads,
			selectedThreadID: selectedThreadID,
			entries: entries,
			canLoadEarlierTurns: canLoadEarlierTurns,
			changedFiles: [],
			diff: "",
			draft: draft,
			canSend: canSend,
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
