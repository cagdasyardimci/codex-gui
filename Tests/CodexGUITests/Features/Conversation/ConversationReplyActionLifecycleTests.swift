import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ConversationReplyActionLifecycleTests
{

	private func assertFollowingBottom(_ controller: ConversationViewController) throws
	{
		let layout = try #require(controller.transcript.collectionView
			.collectionViewLayout as? ConversationFlowLayout)
		let last = try #require(controller.transcript.displayedRows.last)
		let lastFrame = try frame(
			for: last.id,
			in: controller
		)
		let clip = controller.transcript.conversationScrollView.contentView
		let contentHeight = layout.collectionViewContentSize.height
		try #require(contentHeight > clip.bounds.height)
		#expect(controller.transcript.collectionView.isFlipped)
		#expect(abs(contentHeight - lastFrame.maxY - layout.sectionInset.bottom) < 0.5)
		#expect(abs(clip.bounds.maxY - contentHeight) < 0.5)
		#expect(abs(clip.bounds.maxY - lastFrame.maxY - layout.sectionInset.bottom) < 0.5)
		#expect(controller.transcript.isNearBottom)
	}

	@Test(
		.appKitIsolation
	) func replyActionsFollowTerminalTurnsAndRejectPreviousConversationCallbacks() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 888,
				height: 876
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentViewController = controller
		defer
		{
			window.orderOut(nil)
		}
		var toggled: [ConversationBookmark] = []
		controller.onToggleBookmark =
		{
			toggled.append($0)
		}
		let first = [
			entry(
				"first:request",
				kind: .user
			),
			entry(
				"first:commentary",
				kind: .agent
			),
			entry(
				"first:reply",
				kind: .agent
			),
			ConversationEntry(
				id: "first:blank",
				kind: .agent,
				title: "Codex",
				body: " "
			),
		]
		var snapshot = snapshot(entries: first)
		let firstTiming = ConversationTurnTiming(
			turnID: "first",
			status: "completed",
			startedAt: Date(timeIntervalSince1970: 100)
		)
		snapshot.turnTimings = [firstTiming]
		await render(
			snapshot,
			in: controller
		)
		#expect(controller.transcript.replyActionEntryIDs == ["first:reply"])
		let firstHeight = try frame(
			for: "first:reply",
			in: controller
		).height
		let firstBookmark = try menuRow(
			"Bookmark turn",
			for: "first:reply",
			in: controller
		)
		firstBookmark.onInvoke?()
		let bookmark = try #require(toggled.first)
		#expect(bookmark.threadID == "chat" && bookmark.turnID == "first")
		#expect(bookmark.itemID == "reply" && bookmark.kind == .answer)

		// A bookmark publication changes only navigation, leaving the same transcript item alive.
		snapshot.projectContext.bookmarks = [bookmark]
		await render(
			snapshot,
			in: controller
		)
		_ = try menuRow(
			"Remove turn bookmark",
			for: "first:reply",
			in: controller
		)
		#expect(try frame(
			for: "first:reply",
			in: controller
		).height == firstHeight)

		let secondEntries = first + [
			entry(
				"second:request",
				kind: .user
			),
			entry(
				"second:reply",
				kind: .agent
			),
		]
		snapshot = self.snapshot(entries: secondEntries)
		snapshot.projectContext.bookmarks = [bookmark]
		snapshot.turnTimings = [
			firstTiming,
			ConversationTurnTiming(
				turnID: "second",
				status: "inProgress"
			),
		]
		await render(
			snapshot,
			in: controller
		)
		#expect(controller.transcript.replyActionEntryIDs == ["first:reply"])
		#expect(try frame(
			for: "first:reply",
			in: controller
		).height == firstHeight)
		let firstView = try messageView(
			for: "first:reply",
			in: controller
		)
		let copy = try #require(button(
			"Copy response",
			in: firstView
		))
		#expect(copy.isEnabled)
		let secondView = try messageView(
			for: "second:reply",
			in: controller
		)
		#expect(button(
			"Copy response",
			in: secondView
		) == nil)

		let secondTiming = ConversationTurnTiming(
			turnID: "second",
			status: "completed"
		)
		snapshot.turnTimings = [firstTiming, secondTiming]
		await render(
			snapshot,
			in: controller
		)
		#expect(controller.transcript.replyActionEntryIDs == ["first:reply", "second:reply"])
		#expect(try frame(
			for: "first:reply",
			in: controller
		).height == firstHeight)
		_ = try menuRow(
			"Remove turn bookmark",
			for: "first:reply",
			in: controller
		)
		let previousConversationButton = try menuRow(
			"Bookmark turn",
			for: "second:reply",
			in: controller
		)

		snapshot = self.snapshot(
			entries: secondEntries,
			threadID: "another-chat"
		)
		snapshot.turnTimings = [firstTiming, secondTiming]
		await render(
			snapshot,
			in: controller
		)
		previousConversationButton.onInvoke?()
		#expect(toggled.count == 1)
		let currentBookmark = try menuRow(
			"Bookmark turn",
			for: "second:reply",
			in: controller
		)
		currentBookmark.onInvoke?()
		#expect(toggled.count == 2)
		#expect(toggled.last?.threadID == "another-chat" && toggled.last?.turnID == "second")
	}

	@Test(.appKitIsolation) func editOpensExactPromptAndCancelRestoresTheMessage() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 888,
				height: 876
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentViewController = controller
		defer
		{
			window.orderOut(nil)
		}
		let original = "First line\n**Exact source**"
		let directory = try DraftImageImportTestFixture.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let imageURL = directory.appendingPathComponent("attachment.png")
		try DraftImageImportTestFixture.png().write(to: imageURL)
		let attachment = try #require(UserMessageReference(
			json: ["type": "localImage", "path": imageURL.path],
			id: "first:image"
		))
		let message = ConversationEntry(
			id: "first:request",
			kind: .user,
			title: "You",
			body: "Presented text",
			imageAttachments: [attachment]
		)
		let earlier = ConversationEntry(
			id: "other:request",
			kind: .user,
			title: "You",
			body: "Earlier"
		)
		var editAvailable = false
		controller.transcript.editablePrompt =
		{
			threadID, id in
			guard threadID == "chat"
			else
			{
				return nil
			}
			if id == earlier.id
			{
				return earlier.body
			}
			return editAvailable && id == message.id ? original : nil
		}
		controller.transcript.onRevisePrompt =
		{
			_, _, _ in nil
		}
		var presentation = snapshot(entries: [earlier, message])
		presentation.editablePromptEntryIDs = [earlier.id]
		await render(
			presentation,
			in: controller
		)
		let row = try messageView(
			for: message.id,
			in: controller
		)
		let edit = try #require(button(
			"Edit message",
			in: row
		))
		#expect(!edit.isEnabled)
		editAvailable = true
		presentation.editablePromptEntryIDs.insert(message.id)
		await render(
			presentation,
			in: controller
		)
		#expect(edit.isEnabled)
		try #require(edit.dispatchConfiguredAction())
		let editor = try #require(controller.transcript.editingPrompt?.editor)
		#expect(editor.superview === row)
		#expect(editor.textView.string == original)
		let strip = try #require(descendant(
			UserMessageImageAttachmentsView.self,
			in: row
		))
		#expect(!strip.isHidden && !strip.frame.isEmpty)
		#expect(!editor.frame.intersects(strip.frame))
		#expect(button(
			"Send",
			in: editor
		)?.isEnabled == false)
		editor.textView.string = ""
		editor.refreshSend()
		#expect(button(
			"Send",
			in: editor
		)?.isEnabled == true)
		let cancel = try #require(button(
			"Cancel",
			in: editor
		))
		try #require(cancel.dispatchConfiguredAction())
		#expect(controller.transcript.editingPrompt == nil)
		#expect(button(
			"Edit message",
			in: row
		)?.isEnabled == true)
	}

	@Test func userActionsCopyExactSourceOutsideTheBubbleAndRetireOnReuse() throws
	{
		_ = NSApplication.shared
		let source = "First line\n\n**Keep this source** 🧩"
		let content = PreparedConversationContent(MarkdownContentParser.parse(
			source,
			markdown: true
		))
		let item = ConversationCollectionItem()
		let entry = ConversationEntry(
			id: "turn:user",
			kind: .user,
			title: "You",
			body: source
		)
		let size = ConversationCollectionItem.itemSize(
			content: content,
			width: 480,
			expandable: false,
			kind: .user
		)
		item.view.setFrameSize(size)
		item.configure(
			entry,
			content: content,
			expanded: false,
			timestamp: Date(timeIntervalSince1970: 0),
			onToggle:
			{
			}
		)
		item.view.layoutSubtreeIfNeeded()
		let edit = try #require(button(
			"Edit message",
			in: item.view
		))
		#expect(!edit.isEnabled && !edit.dispatchConfiguredAction())
		let copy = try #require(button(
			"Copy message",
			in: item.view
		))
		let actions = try #require(copy.superview as? ConversationReplyActionsView)
		#expect(actions.superview === item.view)
		let actionFrame = actions.convert(
			actions.bounds,
			to: item.view
		)
		#expect(item.view.bounds.contains(actionFrame))
		let text = try #require(descendant(
			MarkdownTextView.self,
			in: item.view
		))
		let textFrame = text.convert(
			text.bounds,
			to: item.view
		)
		#expect(textFrame.minY >= actionFrame.maxY)
		#expect(button(
			"Read aloud",
			in: item.view
		) == nil)
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		actions.writeResponse(to: pasteboard)
		#expect(pasteboard.string(forType: .string) == source)
		item.prepareForReuse()
		pasteboard.clearContents()
		actions.writeResponse(to: pasteboard)
		#expect(pasteboard.string(forType: .string) == nil)
		#expect(!copy.dispatchConfiguredAction())
		item.configure(
			ConversationEntry(
				id: "next:reply",
				kind: .agent,
				title: "Codex",
				body: source
			),
			content: content,
			expanded: false,
			showsReplyActions: true,
			onToggle:
			{
			}
		)
		#expect(button(
			"Copy response",
			in: item.view
		) != nil)
		#expect(button(
			"Read aloud",
			in: item.view
		) != nil)
		#expect(button(
			"Copy message",
			in: item.view
		) == nil)
		let feedback = try #require(button(
			"Give feedback",
			in: item.view
		))
		#expect(!feedback.isEnabled && !feedback.dispatchConfiguredAction())
		#expect(button(
			"Edit message",
			in: item.view
		) == nil)

	}

	@Test(.appKitIsolation) func branchMenuRoutesCapturedChatAndRejectsChangedEligibilityAndOwner(
	) async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 888,
				height: 876
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentViewController = controller
		defer
		{
			window.orderOut(nil)
		}
		var allowed = false
		var branched: [ResultFeedbackTarget] = []
		controller.transcript.canBranch =
		{
			_, _ in allowed
		}
		controller.transcript.onBranch =
		{
			threadID, turnID in branched.append(.init(
				threadID: threadID,
				turnID: turnID
			))
		}
		controller.onToggleBookmark =
		{
			_ in
		}
		let entries = [entry(
			"first:request",
			kind: .user
		), entry(
			"first:reply",
			kind: .agent
		), entry(
			"second:request",
			kind: .user
		), entry(
			"second:reply",
			kind: .agent
		)]
		var presentation = snapshot(entries: entries)
		presentation.turnTimings = [ConversationTurnTiming(
			turnID: "first",
			status: "completed"
		), ConversationTurnTiming(
			turnID: "second",
			status: "completed"
		)]
		await render(
			presentation,
			in: controller
		)
		let firstView = try messageView(
			for: "first:reply",
			in: controller
		)
		let more = try #require(button(
			"More response actions",
			in: firstView
		))
		let actions = try #require(more.superview as? ConversationReplyActionsView)
		try #require(more.dispatchConfiguredAction())
		#expect(actions.actionMenu?.rows.map
		{
			$0.accessibilityLabel()
		} == ["Bookmark turn"])
		allowed = true
		try #require(more.dispatchConfiguredAction())
		let menu = try #require(actions.actionMenu)
		let row = try #require(menu.rows.first)
		#expect(row.accessibilityLabel() == "Branch in new chat")
		row.onInvoke?()
		let expected = [ResultFeedbackTarget(
			threadID: "chat",
			turnID: "first"
		)]
		#expect(branched == expected)
		allowed = false
		row.onInvoke?()
		#expect(branched == expected)
		allowed = true
		var other = snapshot(
			entries: entries,
			threadID: "other-chat"
		)
		other.turnTimings = presentation.turnTimings
		await render(
			other,
			in: controller
		)
		row.onInvoke?()
		#expect(branched == expected)
		#expect(!menu.host.isShown)
		// A retained menu must not adopt a callback installed when its view is reused.
		actions.configure(
			source: "Different reply",
			bookmarked: false,
			onToggleBookmark: nil,
			onBranch:
			{
				branched.append(.init(
					threadID: "reused",
					turnID: "reused"
				))
			}
		)
		row.onInvoke?()
		#expect(branched == expected)
		actions.reset()
	}

	@Test func messageActionsUseCatalogueArtworkAndReferenceTimestampSpacing() throws
	{
		_ = NSApplication.shared
		let actions = ConversationReplyActionsView()
		let timestamp = try #require(Calendar.current.date(from: DateComponents(
			year: 2026,
			month: 11,
			day: 17,
			hour: 13,
			minute: 42
		)))
		for isUser in [true, false]
		{
			actions.configure(
				source: "Message",
				bookmarked: false,
				onToggleBookmark: nil,
				isUserMessage: isUser,
				onBranch: isUser ? nil :
				{
				},
				timestamp: timestamp
			)
			actions.setFrameSize(NSSize(
				width: 280,
				height: ConversationReplyActionsView.height
			))
			actions.layoutSubtreeIfNeeded()
			let labels = actions.arrangedSubviews.compactMap
			{
				$0 as? DesktopTextField
			}
			let label = try #require(labels.first)
			#expect(label.stringValue == "1:42 PM")
			#expect(label.font == AppKitFontResolver.font(TypographyTokens.Transcript.timestamp))
			let copy = try #require(button(
				isUser ? "Copy message" : "Copy response",
				in: actions
			) as? DesktopStyledButton)
			#expect(copy.presentation == .transcriptAction)
			#expect(copy.frame.width == 26)
			if isUser
			{
				#expect(actions.arrangedSubviews.first === label)
				#expect(abs(copy.alignmentRect(forFrame: copy.frame).minX - label
						.alignmentRect(forFrame: label.frame).maxX - 8) < 0.5)
			}
			else
			{
				let more = try #require(button(
					"More response actions",
					in: actions
				))
				#expect(actions.arrangedSubviews.last === label)
				#expect(abs(label.alignmentRect(forFrame: label.frame).minX - more
						.alignmentRect(forFrame: more.frame).maxX - 8) < 0.5)
				let read = try #require(button(
					"Read aloud",
					in: actions
				))
				#expect(read.image?.tiffRepresentation == DesktopIcons.image(
					.soundOnReadOutLoudSpeaker,
					size: LayoutTokens.Transcript.replyIconSize,
					accessibilityDescription: "Read aloud"
				).tiffRepresentation)
			}
		}
	}

	@Test(.appKitIsolation) func feedbackChoicesUseCapturedHandlersAndRetireWithAvailability(
	) throws
	{
		_ = NSApplication.shared
		let actions = ConversationReplyActionsView()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 300,
				height: 80
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentView?.addSubview(actions)
		defer
		{
			actions.reset(); window.orderOut(nil)
		}
		var ratings: [ResultFeedbackRating] = []
		actions.configure(
			source: "Reply",
			bookmarked: false,
			onToggleBookmark: nil,
			interactions: .init(onFeedback:
				{
					ratings.append($0)
				})
		)
		actions.setFrameSize(actions.fittingSize)
		let feedbackButton = try #require(button(
			"Give feedback",
			in: actions
		))
		try #require(feedbackButton.dispatchConfiguredAction())
		let menu = try #require(actions.actionMenu)
		#expect(menu.rows.map
		{
			$0.accessibilityLabel()
		} == ["Good response", "Bad response"])
		let good = try #require(menu.rows.first)
		good.onInvoke?()
		#expect(ratings == [.good])
		actions.setInteractions(.init())
		good.onInvoke?()
		#expect(ratings == [.good])
		#expect(!feedbackButton.dispatchConfiguredAction())
		actions.configure(
			source: "New reply",
			bookmarked: false,
			onToggleBookmark: nil,
			interactions: .init(onFeedback:
				{
					ratings.append($0)
				})
		)
		good.onInvoke?()
		#expect(ratings == [.good])
		try #require(feedbackButton.dispatchConfiguredAction())
		try #require(actions.actionMenu?.rows.last).onInvoke?()
		#expect(ratings == [.good, .bad])
	}

	private func menuRow(
		_ label: String,
		for entryID: String,
		in controller: ConversationViewController
	) throws -> DesktopMenuRow
	{
		let view = try messageView(
			for: entryID,
			in: controller
		)
		let more = try #require(button(
			"More response actions",
			in: view
		))
		try #require(more.dispatchConfiguredAction())
		let actions = try #require(more.superview as? ConversationReplyActionsView)
		return try #require(actions.actionMenu?.rows.first
		{
			$0.accessibilityLabel() == label
		})
	}

	private func descendant<T: NSView>(
		_ type: T.Type,
		in view: NSView
	) -> T?
	{
		if let match = view as? T
		{
			return match
		}
		return view.subviews.lazy.compactMap
		{
			descendant(
				type,
				in: $0
			)
		}.first
	}

	private func render(
		_ snapshot: ConversationSnapshot,
		in controller: ConversationViewController
	) async
	{
		controller.render(snapshot)
		await controller.waitForRendering()
		controller.view.layoutSubtreeIfNeeded()
		controller.transcript.collectionView.layoutSubtreeIfNeeded()
	}

	private func frame(
		for id: String,
		in controller: ConversationViewController
	) throws -> NSRect
	{
		let path = try indexPath(
			for: id,
			in: controller
		)
		return try #require(controller.transcript.collectionView
			.layoutAttributesForItem(at: path)).frame
	}

	private func messageView(
		for id: String,
		in controller: ConversationViewController
	) throws -> NSView
	{
		let path = try indexPath(
			for: id,
			in: controller
		)
		let transcript = controller.transcript
		let collection = transcript.collectionView
		let scroll = transcript.conversationScrollView
		let frame = try #require(collection.collectionViewLayout?
			.layoutAttributesForItem(at: path)).frame
		if collection.item(at: path) == nil
		{
			scroll.contentView.scroll(to: NSPoint(
				x: 0,
				y: frame.minY
			))
			scroll.reflectScrolledClipView(scroll.contentView)
			transcript.readingPositionChanged()
			collection.layoutSubtreeIfNeeded()
		}
		return try #require(
			collection.item(at: path),
			"Expected visible row \(id)"
		).view
	}

	private func indexPath(
		for id: String,
		in controller: ConversationViewController
	) throws -> IndexPath
	{
		let index = try #require(controller.transcript.displayedRows.firstIndex
		{
			$0.id == id
		})
		return IndexPath(
			item: index,
			section: 0
		)
	}

	private func button(
		_ label: String,
		in view: NSView
	) -> NSButton?
	{
		if let button = view as? NSButton, button.accessibilityLabel() == label,
			!button.isHiddenOrHasHiddenAncestor
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			button(
				label,
				in: $0
			)
		}.first
	}

	private func entry(
		_ id: String,
		kind: ConversationEntryKind
	) -> ConversationEntry
	{
		ConversationEntry(
			id: id,
			kind: kind,
			title: kind == .user ? "You" : "Codex",
			body: "First paragraph.\n\nSecond paragraph keeps the response height measurable."
		)
	}

	private func snapshot(
		entries: [ConversationEntry],
		threadID: String = "chat"
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/reply-actions",
			threads: [],
			selectedThreadID: threadID,
			entries: entries,
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
	}
}
