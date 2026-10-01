import AppKit

// Transcript preparation, collection items, and measured row content.
@MainActor
extension ConversationViewController
{
	func configureTranscriptControls()
	{
		configureCollectionView()
		conversationScrollView.documentView = collectionView
		conversationScrollView.hasVerticalScroller = true
		conversationScrollView.autohidesScrollers = true
		conversationScrollView.drawsBackground = false
		conversationScrollView.borderType = .noBorder
		conversationScrollView.contentView.postsBoundsChangedNotifications = true
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(readingPositionChanged),
			name: NSView.boundsDidChangeNotification,
			object: conversationScrollView.contentView
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(transcriptWillStartLiveResize(_:)),
			name: NSWindow.willStartLiveResizeNotification,
			object: nil
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(transcriptDidEndLiveResize(_:)),
			name: NSWindow.didEndLiveResizeNotification,
			object: nil
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(transcriptDidLiveScroll(_:)),
			name: NSScrollView.didLiveScrollNotification,
			object: conversationScrollView
		)
		latestButton.target = self
		latestButton.action = #selector(showLatestMessage)
		latestButton.setAccessibilityLabel("Return to latest message")
		DesktopTheme.styleButton(
			latestButton,
			icon: .arrowDown
		)
		latestButton.imagePosition = .imageOnly
		latestButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
		latestButton.isHidden = true
		bookmarkButton.target = self
		bookmarkButton.action = #selector(bookmarkSelected)
		bookmarkButton
			.setAccessibilityLabel("Bookmark the selected message as an answer or decision")
		DesktopTheme.styleButton(
			bookmarkButton,
			icon: .savedXs
		)
		bookmarkButton.imagePosition = .imageOnly
		bookmarkButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
		bookmarkButton.isEnabled = false
		jumpButton.target = self
		jumpButton.action = #selector(jumpToSelectedTarget)
		jumpButton.setAccessibilityLabel("Jump to a request, changed file, or failure")
		jumpButton.widthAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
		loadEarlierButton.target = self
		loadEarlierButton.action = #selector(loadEarlierTurns)
		loadEarlierButton.setAccessibilityLabel("Load earlier messages in this conversation")
		DesktopTheme.styleButton(
			loadEarlierButton,
			icon: .history
		)
		loadEarlierButton.widthAnchor.constraint(lessThanOrEqualToConstant: 150).isActive = true
		loadEarlierButton.lineBreakMode = .byTruncatingTail
	}

	private func configureCollectionView()
	{
		let layout = ConversationFlowLayout()
		layout.minimumLineSpacing = 18
		layout.sectionInset = NSEdgeInsets(
			top: 20,
			left: 16,
			bottom: 28,
			right: 16
		)
		collectionView.collectionViewLayout = layout
		collectionView.autoresizingMask = [.width]
		collectionView.backgroundColors = [.clear]
		collectionView.register(
			ConversationCollectionItem.self,
			forItemWithIdentifier: NSUserInterfaceItemIdentifier("conversationItem")
		)
		collectionView.dataSource = self
		collectionView.delegate = self
		collectionView.isSelectable = true
		collectionView.setAccessibilityLabel("Conversation messages and activity")
	}

	private func replaceCollectionView()
	{
		// reloadData can re-expose offscreen reusable item views from the previous
		// conversation. Give each conversation its own document-view lifecycle.
		collectionView.dataSource = nil
		collectionView.delegate = nil
		collectionView = NSCollectionView(
			frame: NSRect(
				origin: .zero,
				size: conversationScrollView.contentSize
			)
		)
		configureCollectionView()
		conversationScrollView.documentView = collectionView
		conversationScrollView.contentView.scroll(to: .zero)
	}

	func collectionView(
		_ collectionView: NSCollectionView,
		didSelectItemsAt indexPaths: Set<IndexPath>
	)
	{
		updateBookmarkButton()
	}

	func collectionView(
		_ collectionView: NSCollectionView,
		didDeselectItemsAt indexPaths: Set<IndexPath>
	)
	{
		updateBookmarkButton()
	}

	func jumpToEntry(id: String)
	{
		requestedJumpItemID = id
		scrollToRequestedItem()
	}

	func numberOfSections(in collectionView: NSCollectionView) -> Int
	{
		1
	}

	func collectionView(
		_ collectionView: NSCollectionView,
		numberOfItemsInSection section: Int
	) -> Int
	{
		entries.count
	}

	func collectionView(
		_ collectionView: NSCollectionView,
		itemForRepresentedObjectAt indexPath: IndexPath
	) -> NSCollectionViewItem
	{
		let item = collectionView.makeItem(
			withIdentifier: NSUserInterfaceItemIdentifier("conversationItem"),
			for: indexPath
		)
		guard let item = item as? ConversationCollectionItem
		else
		{
			return item
		}
		let entry = entries[indexPath.item]
		guard let content = preparedContents[entry.id]
		else
		{
			return item
		}
		item.configure(
			entry,
			content: content,
			expanded: expandedEntryIDs.contains(entry.id)
		)
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			if self.expandedEntryIDs.contains(entry.id)
			{
				self.expandedEntryIDs.remove(entry.id)
			}
			else
			{
				self.expandedEntryIDs.insert(entry.id)
			}
			self.prepareEntries(
				self.requestedEntries,
				context: self.requestedContext,
				force: true
			)
		}
		return item
	}

	func collectionView(
		_ collectionView: NSCollectionView,
		layout collectionViewLayout: NSCollectionViewLayout,
		sizeForItemAt indexPath: IndexPath
	) -> NSSize
	{
		let width = ConversationFlowLayout.contentWidth(in: collectionView.bounds.width)
		let entry = entries[indexPath.item]
		guard let content = preparedContents[entry.id]
		else
		{
			return NSSize(
				width: width,
				height: 72
			)
		}
		if let measured = measuredItemSizes[entry.id], measured.content === content,
			measured.kind == entry.kind, measured.expandable == entry.isExpandable
		{
			if measured.size.width == width
			{
				return measured.size
			}
			if liveResizeInProgress && !liveResizeVisibleIDs.contains(entry.id)
			{
				// Only the height is temporary. Rows still fit the actual current reading width.
				needsFinalResizeMetrics = true
				return NSSize(
					width: width,
					height: measured.size.height
				)
			}
		}
		let size = ConversationCollectionItem.itemSize(
			content: content,
			width: width,
			expandable: entry.isExpandable,
			kind: entry.kind
		)
		measuredItemSizes[entry.id] = MeasuredItemSize(
			content: content,
			kind: entry.kind,
			expandable: entry.isExpandable,
			size: size
		)
		return size
	}

	func collectionView(
		_ collectionView: NSCollectionView,
		willDisplay item: NSCollectionViewItem,
		forRepresentedObjectAt indexPath: IndexPath
	)
	{
		guard liveResizeInProgress, entries.indices.contains(indexPath.item)
		else
		{
			return
		}
		let id = entries[indexPath.item].id
		liveResizeVisibleIDs.insert(id)
		let width = ConversationFlowLayout.contentWidth(in: collectionView.bounds.width)
		if let measured = measuredItemSizes[id], measured.size.width != width
		{
			scheduleVisibleResizeMetrics()
		}
	}

	func collectionView(
		_ collectionView: NSCollectionView,
		didEndDisplaying item: NSCollectionViewItem,
		forRepresentedObjectAt indexPath: IndexPath
	)
	{
		guard liveResizeInProgress, entries.indices.contains(indexPath.item)
		else
		{
			return
		}
		liveResizeVisibleIDs.remove(entries[indexPath.item].id)
	}

	func waitForRendering() async
	{
		await transcriptPreparation.waitForRendering()
	}

	func prepareTranscript(_ snapshot: ConversationPresentation.Transcript)
	{
		let context = snapshot.owner.transcriptIdentity
		prepareEntries(
			snapshot.entries,
			context: context
		)
	}

	private func prepareEntries(
		_ nextEntries: [ConversationEntry],
		context: String?,
		force: Bool = false
	)
	{
		guard force || requestedEntries != nextEntries || requestedContext != context
		else
		{
			return
		}
		if requestedContext != context
		{
			expandedEntryIDs.removeAll()
		}
		requestedEntries = nextEntries
		requestedContext = context
		let keys = nextEntries.map
		{
			TranscriptPreparationCoordinator.ContentKey(
				body: displayedBody(for: $0),
				markdown: $0.kind == .agent
			)
		}
		transcriptPreparation.prepare(
			nextEntries,
			keys: keys
		)
		{
			[weak self] contents in
			self?.applyEntries(
				nextEntries,
				contents: contents,
				context: context
			)
		}
	}

	struct ReadingAnchor
	{
		let entryID: String
		let offset: CGFloat
	}

	func readingAnchor() -> ReadingAnchor?
	{
		let visible = conversationScrollView.contentView.bounds
		let candidates =
			collectionView.collectionViewLayout?.layoutAttributesForElements(in: visible) ?? []
		guard
			let first = candidates.filter(
				{
					$0.representedElementCategory == .item
				}
			)
			.sorted(by:
				{
					$0.frame.minY < $1.frame.minY
				}).first,
			let index = first.indexPath?.item, entries.indices.contains(index)
		else
		{
			return nil
		}
		return ReadingAnchor(
			entryID: entries[index].id,
			offset: visible.minY - first.frame.minY
		)
	}

	private func applyEntries(
		_ nextEntries: [ConversationEntry],
		contents: [String: PreparedConversationContent],
		context: String?
	)
	{
		let contextChanged = renderedContext != context
		let shouldFollowOutput = contextChanged || isNearBottom
		let anchor = shouldFollowOutput ? nil : readingAnchor()
		let previousEntries = entries
		let previousContents = preparedContents
		let sharedCount = min(
			previousEntries.count,
			nextEntries.count
		)
		let sharedIDsMatch = (0 ..< sharedCount).allSatisfy
		{
			previousEntries[$0].id == nextEntries[$0].id
		}
		preparedContents = contents
		if contextChanged
		{
			measuredItemSizes.removeAll()
			liveResizeVisibleIDs.removeAll()
		}
		else
		{
			// Retain sizes only for the current transcript's unchanged prepared content.
			measuredItemSizes = measuredItemSizes.filter
			{
				id, measured in
				contents[id] === measured.content
			}
		}
		if contextChanged && renderedContext != nil
		{
			entries = nextEntries
			replaceCollectionView()
		}
		renderedContext = context
		if !contextChanged && sharedIDsMatch && nextEntries.count >= previousEntries.count
		{
			let changed = (0 ..< sharedCount).filter
			{
				previousEntries[$0] != nextEntries[$0]
					|| previousContents[previousEntries[$0].id]?.attributedString
					!= contents[nextEntries[$0].id]?.attributedString
			}.map
			{
				IndexPath(
					item: $0,
					section: 0
				)
			}
			let added = (sharedCount ..< nextEntries.count).map
			{
				IndexPath(
					item: $0,
					section: 0
				)
			}
			collectionView.performBatchUpdates
			{
				entries = nextEntries
				if !changed.isEmpty
				{
					collectionView.reloadItems(at: Set(changed))
				}
				if !added.isEmpty
				{
					collectionView.insertItems(at: Set(added))
				}
			}
		}
		else
		{
			entries = nextEntries
			collectionView.reloadData()
		}
		view.layoutSubtreeIfNeeded()
		collectionView.layoutSubtreeIfNeeded()
		restoreReadingPosition(
			followOutput: shouldFollowOutput,
			anchor: anchor
		)
		readingPositionChanged()
		scrollToRequestedItem()
	}

	private func displayedBody(for entry: ConversationEntry) -> String
	{
		guard entry.isExpandable && !expandedEntryIDs.contains(entry.id)
		else
		{
			return entry.body
		}
		let lines = entry.body.components(separatedBy: .newlines)
		return lines.prefix(2).joined(separator: "\n")
	}

}
