import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationLongHistoryLayoutTests
{
	@Test func inspectorReflowKeepsCodeControlsAndUnframedDiagramsInsideTranscript() async throws
	{
		let fixture = try await makeReadingFixture()
		defer
		{
			tearDown(fixture)
		}
		let content = try #require(fixture.controller.transcript.preparedContents["canonical-user"])
		try #require(content.codeBlockRanges.count == 4)
		let scroll = try #require(fixture.collection.enclosingScrollView)
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		let diagramSource = "```mermaid\nflowchart LR\n"
			+ "    A[Markdown source] --> B[Parser]\n"
			+ "    B --> C[Rendered content]\n```"
		for (width, inspectorVisible) in [
			(980.0, false),
			(980.0, true),
			(980.0, false),
			(1200.0, false),
			(980.0, true),
			(980.0, false),
		]
		{
			fixture.window.setContentSize(NSSize(
				width: width,
				height: 760
			))
			fixture.panes.setReviewCollapsed(!inspectorVisible)
			await settleLayout(
				panes: fixture.panes,
				controller: fixture.controller,
				collection: fixture.collection
			)
			let text = try assertCopyControlCards(
				at: fixture.path,
				in: fixture.collection,
				content: content
			)
			let manager = try #require(text.layoutManager as? MarkdownLayoutManager)
			let diagramRange = try #require(content.codeBlockRanges.last)
			let container = try #require(text.textContainer)
			#expect(manager.codeBlockRect(
				atCharacter: diagramRange.location,
				in: container
			) == nil)
			let glyphs = manager.glyphRange(
				forCharacterRange: diagramRange,
				actualCharacterRange: nil
			)
			let card = manager.boundingRect(
				forGlyphRange: glyphs,
				in: container
			).offsetBy(
				dx: text.textContainerOrigin.x,
				dy: text.textContainerOrigin.y
			)
			let visibleCard = text.convert(
				card,
				to: fixture.collection
			)
			scroll.contentView.scroll(to: NSPoint(
				x: 0,
				y: visibleCard.minY - 20
			))
			scroll.reflectScrolledClipView(scroll.contentView)
			fixture.controller.transcript.readingPositionChanged()
			await settleLayout(
				panes: fixture.panes,
				controller: fixture.controller,
				collection: fixture.collection
			)
			_ = try assertCopyControlCards(
				at: fixture.path,
				in: fixture.collection,
				content: content
			)
			text.setSelectedRange(diagramRange)
			#expect(text.writeSelection(
				to: pasteboard,
				types: text.writablePasteboardTypes
			))
			#expect(pasteboard.string(forType: .string) == diagramSource)
		}
		fixture.collection.scrollToItems(
			at: [IndexPath(
				item: 0,
				section: 0
			)],
			scrollPosition: .top
		)
		await settleLayout(
			panes: fixture.panes,
			controller: fixture.controller,
			collection: fixture.collection
		)
		fixture.collection.scrollToItems(
			at: [fixture.path],
			scrollPosition: .top
		)
		await settleLayout(
			panes: fixture.panes,
			controller: fixture.controller,
			collection: fixture.collection
		)
		_ = try assertCopyControlCards(
			at: fixture.path,
			in: fixture.collection,
			content: content
		)
		#expect(fixture.controller.transcript.entries == fixture.entries)
	}

	@Test func inspectorAndWindowWidthChangesKeepTheRichUserReadingPosition() async throws
	{
		let fixture = try await makeReadingFixture()
		defer
		{
			tearDown(fixture)
		}
		let window = fixture.window
		let panes = fixture.panes
		let controller = fixture.controller
		let collection = fixture.collection
		let scroll = try #require(collection.enclosingScrollView)
		let path = fixture.path
		let entries = fixture.entries
		let markerOffset = try markerRect(
			at: path,
			in: collection
		).minY - scroll.contentView.bounds.minY
		#expect(controller.transcript.readingAnchor()?.sourceEntryID == "canonical-user")
		#expect(!controller.transcript.isNearBottom)
		var previousWidth = collection.bounds.width
		for (width, inspectorVisible) in [
			(980.0, true),
			(1200.0, true),
			(980.0, true),
			(980.0, false),
		]
		{
			window.setContentSize(NSSize(
				width: width,
				height: 760
			))
			panes.setReviewCollapsed(!inspectorVisible)
			await settleLayout(
				panes: panes,
				controller: controller,
				collection: collection
			)
			#expect(panes.split.splitViewItems[2].isCollapsed == !inspectorVisible)
			#expect(abs(collection.bounds.width - previousWidth) > 1)
			previousWidth = collection.bounds.width
			#expect(controller.transcript.readingAnchor()?.sourceEntryID == "canonical-user")
			let marker = try markerRect(
				at: path,
				in: collection
			)
			#expect(abs(marker.minY - scroll.contentView.bounds.minY - markerOffset) < 2)
			#expect(marker.intersects(scroll.contentView.bounds))
			#expect(controller.transcript.entries == entries)
		}
	}

	@Test func latestAndContextSwitchWinOverPendingWidthRestoration() async throws
	{
		let fixture = try await makeReadingFixture()
		defer
		{
			tearDown(fixture)
		}
		let controller = fixture.controller
		let collection = fixture.collection
		let scroll = try #require(collection.enclosingScrollView)
		#expect(controller.transcript.readingAnchor()?.sourceEntryID == "canonical-user")
		fixture.panes.setReviewCollapsed(false)
		try #require(controller.transcript.widthChangeReadingPosition != nil)
		controller.transcript.showLatestMessage()
		await settleLayout(
			panes: fixture.panes,
			controller: fixture.controller,
			collection: collection
		)
		#expect(collection.bounds.maxY - scroll.contentView.bounds.maxY < 48)
		#expect(controller.transcript.readingAnchor()?.sourceEntryID == "later-output")
		collection.scrollToItems(
			at: [fixture.path],
			scrollPosition: .top
		)
		await settleLayout(
			panes: fixture.panes,
			controller: fixture.controller,
			collection: collection
		)
		let marker = try markerRect(
			at: fixture.path,
			in: collection
		)
		scroll.contentView.scroll(to: NSPoint(
			x: 0,
			y: marker.minY + 1
		))
		scroll.reflectScrolledClipView(scroll.contentView)
		controller.transcript.readingPositionChanged()
		#expect(controller.transcript.readingAnchor()?.sourceEntryID == "canonical-user")
		fixture.panes.setReviewCollapsed(true)
		try #require(controller.transcript.widthChangeReadingPosition != nil)
		let replacement = ConversationEntry(
			id: "replacement",
			kind: .agent,
			title: "Codex",
			body: "Replacement conversation stays visible."
		)
		controller.render(snapshot(
			[replacement],
			thread: "replacement"
		))
		await controller.waitForRendering()
		let current = try #require(findCollection(in: controller.view))
		await settleLayout(
			panes: fixture.panes,
			controller: fixture.controller,
			collection: current
		)
		#expect(controller.transcript.entries == [replacement])
		#expect(current !== collection)
		#expect(collection.superview == nil && collection.dataSource == nil)
		#expect(current.numberOfItems(inSection: 0) == 1)
		let visible = textViews(in: current).filter
		{
			!$0.isHiddenOrHasHiddenAncestor
		}.map(\.string)
		#expect(visible == [replacement.body])
		#expect(controller.transcript.readingAnchor()?.sourceEntryID == replacement.id)
		#expect(current.enclosingScrollView?.contentView.bounds.minY == 0)
	}

	private func assertCopyControlCards(
		at path: IndexPath,
		in collection: NSCollectionView,
		content: PreparedConversationContent
	) throws -> NSTextView
	{
		let item = try #require(collection.item(at: path) as? ConversationCollectionItem)
		let text = try #require(textViews(in: item.view).first)
		let manager = try #require(text.layoutManager as? MarkdownLayoutManager)
		let container = try #require(text.textContainer)
		// Text layout and the item's overlay layout are separate AppKit lifecycle stages.
		// Drive both for this fixture before inspecting copy buttons after a width change.
		// The second pass applies any body-height constraints changed by viewDidLayout.
		for _ in 0 ..< 2
		{
			item.view.layoutSubtreeIfNeeded()
			manager.ensureLayout(for: container)
			item.viewDidLayout()
		}
		let buttons = allButtons(in: item.view).filter
		{
			($0.accessibilityLabel() ?? "").hasPrefix("Copy code block ")
		}.sorted
		{
			$0.tag < $1.tag
		}
		try #require(buttons.count == content.codeBlockRanges.count)
		for (index, range) in content.codeBlockRanges.enumerated()
		{
			let button = buttons[index]
			#expect(button.tag == index)
			#expect(button.accessibilityLabel() == "Copy code block \(index + 1)")
			#expect(button.title.isEmpty && button.imagePosition == .imageOnly)
			#expect(button.superview !== text)
			if let attachment = text.textStorage?.attribute(
				.attachment,
				at: range.location,
				effectiveRange: nil
			) as? MarkdownRichAttachment
			{
				#expect(manager.codeBlockRect(
					atCharacter: range.location,
					in: container
				) == nil)
				#expect(manager
					.codeBlockHeaderRect(
						atCharacter: range.location,
						in: container
					) == nil)
				#expect(button.isHidden == attachment.rendersNativeImage)
				if attachment.rendersNativeImage
				{
					(text as? MarkdownTextView)?.updateDiagramControls()
					let controls = try #require(text.subviews.compactMap
					{
						$0 as? MarkdownDiagramControls
					}.first
					{
						$0.attachment === attachment
					})
					#expect(text.bounds.contains(controls.frame))
				}
				else
				{
					#expect(text.bounds.contains(text.convert(
						button.bounds,
						from: button
					)))
				}
				continue
			}
			let card = try #require(manager.codeBlockRect(
				atCharacter: range.location,
				in: container
			)).offsetBy(
				dx: text.textContainerOrigin.x,
				dy: text.textContainerOrigin.y
			)
			let header = try #require(manager.codeBlockHeaderRect(
				atCharacter: range.location,
				in: container
			)).offsetBy(
				dx: text.textContainerOrigin.x,
				dy: text.textContainerOrigin.y
			)
			let buttonFrame = text.convert(
				button.bounds,
				from: button
			)
			#expect(header.contains(buttonFrame))
			#expect(card.contains(buttonFrame))
			#expect(text.bounds.contains(buttonFrame))
			if index < 3
			{
				#expect((text.string as NSString).substring(with: range) == content
					.codeBlocks[index])
			}
		}
		return text
	}

	private struct ReadingFixture
	{
		let window: NSWindow
		let panes: WindowPaneController
		let controller: ConversationViewController
		let collection: NSCollectionView
		let entries: [ConversationEntry]
		let path: IndexPath
	}

	private func tearDown(_ fixture: ReadingFixture)
	{
		fixture.controller.transcript.cancelWidthChangeReadingPosition()
		fixture.controller.transcript.turnNavigationRail.dismissPreview()
		for collection in [fixture.collection, fixture.controller.transcript.collectionView]
		{
			collection.delegate = nil
			collection.dataSource = nil
		}
		fixture.window.contentViewController = nil
		fixture.window.isReleasedWhenClosed = false
		fixture.window.close()
	}

	private func makeReadingFixture() async throws -> ReadingFixture
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let panes = WindowPaneController(
			navigation: NavigationViewController(),
			conversation: controller,
			inspector: InspectorViewController(),
			layoutStore: nil
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 980,
				height: 760
			),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = panes.split
		panes.restoreLayout(in: window)
		window.setContentSize(NSSize(
			width: 980,
			height: 760
		))
		panes.didPresentWindow()
		let collection = try #require(findCollection(in: controller.view))
		let scroll = try #require(collection.enclosingScrollView)
		#expect(scroll === controller.transcript.conversationScrollView)
		var entries = (0 ..< 120).map
		{
			ConversationEntry(
				id: "earlier-\($0)",
				kind: .agent,
				title: "Codex",
				body: "## Earlier message \($0)\n\n" + String(
					repeating: "Earlier wrapping text with Unicode 😀 café. ",
					count: 12
				) + "\n\n" + markdownHistoryBlock(index: $0)
			)
		}
		entries.append(ConversationEntry(
			id: "canonical-user",
			kind: .user,
			title: "You",
			body: ConversationMarkdownTestFixture.paritySource
		))
		entries.append(ConversationEntry(
			id: "later-output",
			kind: .agent,
			title: "Codex",
			body: String(
				repeating: "Following output keeps this reading position away from the bottom.\n\n",
				count: 40
			)
		))
		controller.render(snapshot(
			entries,
			thread: "rich-reading"
		))
		await controller.waitForRendering()
		await settleLayout(
			panes: panes,
			controller: controller,
			collection: collection
		)
		let path = IndexPath(
			item: 120,
			section: 0
		)
		collection.scrollToItems(
			at: [path],
			scrollPosition: .top
		)
		await settleLayout(
			panes: panes,
			controller: controller,
			collection: collection
		)
		let initialMarker = try markerRect(
			at: path,
			in: collection
		)
		scroll.contentView.scroll(to: NSPoint(
			x: 0,
			y: initialMarker.minY + 1
		))
		scroll.reflectScrolledClipView(scroll.contentView)
		controller.transcript.readingPositionChanged()
		await settleLayout(
			panes: panes,
			controller: controller,
			collection: collection
		)
		return ReadingFixture(
			window: window,
			panes: panes,
			controller: controller,
			collection: collection,
			entries: entries,
			path: path
		)
	}

	private func settleLayout(
		panes: WindowPaneController,
		controller: ConversationViewController,
		collection: NSCollectionView
	) async
	{
		for _ in 0 ..< 4
		{
			panes.split.view.layoutSubtreeIfNeeded()
			collection.layoutSubtreeIfNeeded()
			// Await width restoration before checking the reading anchor.
			await controller.transcript.widthChangeRestoreTask?.value
		}
	}

	private func markerRect(
		at path: IndexPath,
		in collection: NSCollectionView
	) throws -> NSRect
	{
		let item = try #require(collection.item(at: path))
		let text = try #require(textViews(in: item.view).first
		{
			$0.accessibilityLabel() == "You content"
		})
		let range = (text.string as NSString).range(of: "FINAL_MARKER")
		try #require(range.location != NSNotFound)
		let manager = try #require(text.layoutManager)
		let container = try #require(text.textContainer)
		manager.ensureLayout(for: container)
		let glyphs = manager.glyphRange(
			forCharacterRange: range,
			actualCharacterRange: nil
		)
		let bounds = manager.boundingRect(
			forGlyphRange: glyphs,
			in: container
		).offsetBy(
			dx: text.textContainerOrigin.x,
			dy: text.textContainerOrigin.y
		)
		return text.convert(
			bounds,
			to: collection
		)
	}

	private func markdownHistoryBlock(index: Int) -> String
	{
		switch index % 4
		{
		case 0: "- list item\n  - nested item with **bold** text"
		case 1: "> quoted history with `inline code` and 😀"
		case 2: "| Name | Value |\n| :--- | ---: |\n| earlier result | 42 |"
		default: "~~~text\n  exact code 😀\n~~~"
		}
	}

	private func allButtons(in view: NSView) -> [NSButton]
	{
		((view as? NSButton).map
		{
			[$0]
		} ?? []) + view.subviews.flatMap
		{
			allButtons(in: $0)
		}
	}

	private func textViews(in view: NSView) -> [NSTextView]
	{
		if let text = view as? NSTextView
		{
			return [text]
		}
		return view.subviews.flatMap
		{
			textViews(in: $0)
		}
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

	private func snapshot(
		_ entries: [ConversationEntry],
		thread: String
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/layout",
			threads: [],
			selectedThreadID: thread,
			entries: entries,
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
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
	}
}
