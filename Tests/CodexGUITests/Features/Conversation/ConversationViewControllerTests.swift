import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationViewControllerTests
{
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
		#expect(controller.entries == entries)
		for entry in entries
		{
			let content = try #require(controller.preparedContents[entry.id])
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
		let user = try #require(controller.preparedContents["user"])
		let agent = try #require(controller.preparedContents["agent"])
		let tool = try #require(controller.preparedContents["tool"])
		#expect(user.attributedString.string == "First line\nSecond line\nformatted")
		#expect(agent.attributedString.string == "First line Second line\nformatted")
		#expect(tool.attributedString.string == body)
		#expect(user !== agent)
		#expect(controller.entries == entries)
	}

	@Test func canonicalScreenshotPromptUsesRichUserPreparationWithoutChangingItsSource(
	) async throws
	{
		_ = NSApplication.shared
		let body = ConversationMarkdownTestFixture.paritySource
		let entry = ConversationEntry(
			id: "canonical-user",
			kind: .user,
			title: "You",
			body: body
		)
		let controller = ConversationViewController()
		controller.render(snapshot([entry]))
		await controller.waitForRendering()
		let content = try #require(controller.preparedContents[entry.id])
		let text = content.attributedString
		#expect(controller.entries == [entry])
		#expect(controller.entries.first?.body == body)
		#expect(text.string.contains("Markdown Rendering Test"))
		#expect(!text.string.contains("# Markdown Rendering Test"))
		#expect(text.string.contains("This is a soft line break.\n"
				+ "This should continue the same paragraph."))
		#expect(text.string.contains("FINAL_MARKER"))
		#expect(text.string.contains("TABLE_END_MARKER"))
		#expect(text.string.contains("Inline math: $E = mc^2$"))
		#expect(text.string.contains("<span>HTML_PROBE</span>"))
		#expect(!text.string.contains("│"))
		#expect(text.string.contains("◦\tNested bullet"))
		#expect(text.string.contains("▪\tThird-level bullet"))
		try #require(content.codeBlocks.count == 4)
		try #require(content.codeBlockRanges.count == 4)
		for index in 0 ..< 3
		{
			#expect((text.string as NSString).substring(with: content.codeBlockRanges[index])
				== content.codeBlocks[index])
		}
		#expect(content.codeBlocks[3] == "flowchart LR\n"
			+ "    A[Markdown source] --> B[Parser]\n"
			+ "    B --> C[Rendered content]\n")
		let mathSource = "$$\n\\int_0^1 x^2\\,dx = \\frac{1}{3}\n$$"
		let diagramSource = "```mermaid\n" + content.codeBlocks[3] + "```"
		var richSources: [String] = []
		text.enumerateAttribute(
			.attachment,
			in: NSRange(
				location: 0,
				length: text.length
			)
		)
		{
			value, range, _ in
			if let attachment = value as? ConversationRichAttachment
			{
				richSources.append(attachment.source)
				#expect((text.string as NSString).substring(with: range) == "\u{FFFC}")
				#expect(text.attribute(
					.conversationSourceText,
					at: range.location,
					effectiveRange: nil
				) as? String == attachment.source)
			}
		}
		#expect(richSources == [mathSource, diagramSource])
	}

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
		#expect(controller.displayedRows.count == 1)
		let initialGroup = try #require(controller.displayedRows.first)
		guard case .activity(let collapsedGroup) = initialGroup
		else
		{
			Issue.record("Expected collapsed group")
			return
		}
		#expect(collapsedGroup.kind == .group)
		#expect(!collapsedGroup.expanded)
		controller.toggleActivity(collapsedGroup)
		await controller.waitForRendering()
		#expect(controller.displayedRows.count == 3)
		guard case .activity(let command) = controller.displayedRows[1]
		else
		{
			Issue.record("Expected command activity")
			return
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
		controller.render(snapshot([entry, second]))
		await controller.waitForRendering()
		guard case .activity(let streamed) = controller.displayedRows[1],
				case .activity(let group) = controller.displayedRows[0]
		else
		{
			Issue.record("Expected retained activities")
			return
		}
		#expect(streamed.expanded)
		#expect(streamed.command?.output == "hello")
		controller.toggleActivity(group)
		await controller.waitForRendering()
		#expect(controller.displayedRows.count == 1)
		controller.jumpToEntry(id: second.id)
		await controller.waitForRendering()
		#expect(controller.displayedRows.count == 3)
		#expect(controller.requestedJumpItemID == nil)
		#expect(controller.entries == [entry, second])
		let otherConversation = snapshot(
			[entry, second],
			selectedThreadID: "other"
		)
		controller.render(otherConversation)
		await controller.waitForRendering()
		#expect(controller.displayedRows.count == 1)
		#expect(controller.expandedGroupIDs.isEmpty)
		controller.render(snapshot([entry, second]))
		await controller.waitForRendering()
		#expect(controller.displayedRows.count == 1)
	}

	@Test func completedWorkCollapsesKeepsReplyAndJumpRevealsCommentary() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let commentary = ConversationEntry(
			id: "turn:comment",
			kind: .agent,
			title: "Codex",
			body: "Checking files"
		)
		let command = ConversationEntry(
			id: "turn:command",
			kind: .command,
			title: "Command",
			body: "",
			activity: .command(ConversationCommand(
				command: "git status",
				cwd: nil,
				output: "",
				status: "completed",
				exitCode: 0,
				durationMs: 1,
				actions: []
			))
		)
		let reply = ConversationEntry(
			id: "turn:reply",
			kind: .agent,
			title: "Codex",
			body: "Done"
		)
		var completed = snapshot([commentary, command, reply])
		completed.turnTimings = [ConversationTurnTiming(
			turnID: "turn",
			status: "completed",
			durationMs: 184000
		)]
		controller.render(completed)
		await controller.waitForRendering()
		#expect(controller.displayedRows.map(\.id) == ["timing:turn", reply.id])
		let item = try #require(controller.collectionView(
			controller.collectionView,
			itemForRepresentedObjectAt: IndexPath(
				item: 0,
				section: 0
			)
		)
			as? ConversationTurnStatusCollectionItem)
		let disclosure = try #require(item.view.subviews.compactMap
		{
			$0 as? NSButton
		}.first)
		#expect(disclosure.accessibilityLabel() == "Expand Worked for 3m 4s")
		disclosure.performClick(nil)
		await controller.waitForRendering()
		#expect(controller.displayedRows.map(\.id) == ["timing:turn",
														commentary.id,
														command.id,
														reply.id])
		controller.toggleTurnWork("turn")
		await controller.waitForRendering()
		#expect(controller.displayedRows.map(\.id) == ["timing:turn", reply.id])
		controller.jumpToEntry(id: command.id)
		await controller.waitForRendering()
		#expect(controller.expandedTurnIDs.contains("turn"))
		#expect(controller.requestedJumpItemID == nil)
		var switched = snapshot(
			[commentary, command, reply],
			selectedThreadID: "other"
		)
		switched.turnTimings = completed.turnTimings
		controller.render(switched)
		await controller.waitForRendering()
		#expect(controller.expandedTurnIDs.isEmpty)
		#expect(controller.displayedRows.map(\.id) == ["timing:turn", reply.id])
		completed.turnTimings = [ConversationTurnTiming(
			turnID: "turn",
			status: "inProgress",
			startedAt: Date()
		)]
		controller.render(completed)
		await controller.waitForRendering()
		#expect(controller.displayedRows.contains
		{
			$0.id == commentary.id
		})
		controller.turnStatusTimer?.invalidate()
	}

	@Test func collapsedActivitySpacingMatchesReferenceOnBothSides()
	{
		let message = ConversationEntry(
			id: "turn:message",
			kind: .agent,
			title: "Codex",
			body: "Update"
		)
		var activity = ConversationActivityRow(
			id: "group",
			sourceEntryID: "turn:tool",
			groupID: "group",
			kind: .group,
			title: "Ran commands"
		)
		let collapsed: [ConversationTranscriptRow] = [.message(message),
														.activity(activity),
														.message(message)]
		#expect(ConversationViewController.verticalGap(
			at: 1,
			in: collapsed
		) == 8)
		#expect(ConversationViewController.verticalGap(
			at: 2,
			in: collapsed
		) == 8)
		activity.expanded = true
		let expanded: [ConversationTranscriptRow] = [.message(message),
														.activity(activity),
														.message(message)]
		#expect(ConversationViewController.verticalGap(
			at: 1,
			in: expanded
		) == 18)
		#expect(ConversationViewController.verticalGap(
			at: 2,
			in: expanded
		) == 18)
		let timing = ConversationTurnTiming(
			turnID: "turn",
			status: "completed",
			durationMs: 310000
		)
		#expect(ConversationViewController.verticalGap(
			at: 1,
			in: [.turnStatus(timing), .message(message)]
		) == 14)
		let user = ConversationEntry(
			id: "next:user",
			kind: .user,
			title: "You",
			body: "Next request"
		)
		#expect(ConversationViewController.verticalGap(
			at: 1,
			in: [.message(message), .message(user)]
		) == 40)
		#expect(ConversationViewController.verticalGap(
			at: 1,
			in: [.message(user), .turnStatus(timing)]
		) == 50)
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
		let activityIndex = try #require(controller.displayedRows.firstIndex
		{
			$0.sourceEntryID == entry.id
		})
		let retained = controller.collectionView(
			controller.collectionView,
			itemForRepresentedObjectAt: IndexPath(
				item: activityIndex,
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
		#expect(controller.collapsedImageIDs.isEmpty)
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
		#expect(controller.turnStatusTimer != nil)
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
			Issue.record("Expected timing row")
			return
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
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		defer
		{
			controller.collectionView.dataSource = nil
			controller.collectionView.delegate = nil
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
		let activityIndex = try #require(controller.displayedRows.firstIndex
		{
			$0.sourceEntryID == entry.id
		})
		guard case .activity(let row) = controller.displayedRows[activityIndex]
		else
		{
			Issue.record("Expected command activity row")
			return
		}
		controller.toggleActivity(row)
		await controller.waitForRendering()
		let item = try #require(controller.collectionView.item(
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
		controller.collectionView(
			controller.collectionView,
			didEndDisplaying: item,
			forRepresentedObjectAt: IndexPath(
				item: activityIndex,
				section: 0
			)
		)
		#expect(try #require(controller.activityOutputPositions[row.id]).origin.y == 80)
		controller.toggleActivity(row)
		await controller.waitForRendering()
		controller.toggleActivity(row)
		await controller.waitForRendering()
		let reopened = try #require(controller.collectionView.item(
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
		guard case .activity(let group) = try #require(controller.displayedRows.first)
		else
		{
			Issue.record("Expected a collapsed command group")
			return
		}
		#expect(!group.expanded)
		controller.toggleActivity(group)
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
		#expect(abs(frames[3].minY - frames[2].maxY - 8) < 1)
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
		threads: [ThreadSummary] = [],
		selectedThreadID: String = "replay"
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/replay",
			threads: threads,
			selectedThreadID: selectedThreadID,
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
