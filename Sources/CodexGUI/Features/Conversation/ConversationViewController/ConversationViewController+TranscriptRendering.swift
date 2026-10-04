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
		observeTranscriptChanges()
		configureTranscriptNavigationButtons()
	}

	private func observeTranscriptChanges()
	{
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
	}

	private func configureTranscriptNavigationButtons()
	{
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
		layout.willChangeContentWidth =
		{
			[weak self] attributes in
			self?.captureWidthChangeReadingPosition(using: attributes)
		}
		layout.minimumLineSpacing = 18
		layout.verticalGap =
		{
			[weak self] index in
			guard let self, self.displayedRows.indices.contains(index), index > 0,
					case .activity(let current) = self.displayedRows[index],
					case .activity(let previous) = self.displayedRows[index - 1],
					current.groupID == previous.groupID
			else
			{
				return 18
			}
			return 0
		}
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
		collectionView.register(
			ConversationActivityCollectionItem.self,
			forItemWithIdentifier: NSUserInterfaceItemIdentifier("activityItem")
		)
		collectionView.register(
			ConversationTurnStatusCollectionItem.self,
			forItemWithIdentifier: NSUserInterfaceItemIdentifier("turnStatusItem")
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
		displayedRows.count
	}

	func collectionView(
		_ collectionView: NSCollectionView,
		itemForRepresentedObjectAt indexPath: IndexPath
	) -> NSCollectionViewItem
	{
		let row = displayedRows[indexPath.item]
		let identifier: String
		switch row
		{
		case .activity: identifier = "activityItem"
		case .turnStatus: identifier = "turnStatusItem"
		case .message: identifier = "conversationItem"
		}
		let item = collectionView.makeItem(
			withIdentifier: NSUserInterfaceItemIdentifier(identifier),
			for: indexPath
		)
		configureTranscriptItem(
			item,
			for: row
		)
		return item
	}

	private func configureTranscriptItem(
		_ item: NSCollectionViewItem,
		for row: ConversationTranscriptRow
	)
	{
		let context = renderedContext
		switch row
		{
		case .activity(let activity):
			(item as? ConversationActivityCollectionItem)?.configure(
				activity,
				onToggle:
				{
					[weak self] in
					guard let self, self.renderedContext == context,
							self.requestedContext == context
					else
					{
						return
					}
					self.toggleActivity(activity)
				},
				onOpenFile:
				{
					[weak self] path in
					guard let self, self.renderedContext == context,
							self.requestedContext == context
					else
					{
						return
					}
					self.onOpenActivityFile(path)
				}
			)
			if let position = activityOutputPositions[activity.id]
			{
				(item as? ConversationActivityCollectionItem)?
					.restoreOutputReadingPosition(position)
			}
			return
		case .turnStatus(let timing):
			(item as? ConversationTurnStatusCollectionItem)?.configure(
				timing,
				now: Date()
			)
			return
		case .message: break
		}
		guard let item = item as? ConversationCollectionItem,
				case .message(let entry) = row
		else
		{
			return
		}

		guard let content = preparedContents[entry.id]
		else
		{
			return
		}
		item.configure(
			entry,
			content: content,
			expanded: expandedEntryIDs.contains(entry.id)
		)
		{
			[weak self] in
			guard let self, self.renderedContext == context, self.requestedContext == context
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
	}

	func collectionView(
		_ collectionView: NSCollectionView,
		layout collectionViewLayout: NSCollectionViewLayout,
		sizeForItemAt indexPath: IndexPath
	) -> NSSize
	{
		let width = ConversationFlowLayout.contentWidth(in: collectionView.bounds.width)
		let row = displayedRows[indexPath.item]
		switch row
		{
		case .activity(let activity):
			return ConversationActivityCollectionItem.itemSize(
				row: activity,
				width: width
			)
		case .turnStatus:
			return ConversationTurnStatusCollectionItem.itemSize(width: width)
		case .message: break
		}
		guard case .message(let entry) = row
		else
		{
			return .zero
		}
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
		guard liveResizeInProgress, displayedRows.indices.contains(indexPath.item)
		else
		{
			return
		}
		let id = displayedRows[indexPath.item].id
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
		if requestedContext == renderedContext,
			let activity = item as? ConversationActivityCollectionItem,
			let id = activity.activityID, let position = activity.outputReadingPosition()
		{
			activityOutputPositions[id] = position
		}
		guard liveResizeInProgress, displayedRows.indices.contains(indexPath.item)
		else
		{
			return
		}
		liveResizeVisibleIDs.remove(displayedRows[indexPath.item].id)
	}

	func waitForRendering() async
	{
		await transcriptPreparation.waitForRendering()
	}

	func prepareTranscript(_ snapshot: ConversationPresentation.Transcript)
	{
		let context = snapshot.owner.transcriptIdentity
		let displayTimings = snapshot.turnTimings.map
		{
			timing in
			let hasConfirmedActiveExecution =
				timingExecutionState.isBusy
					&& snapshot.selectedThreadID != nil
					&& snapshot.activeThreadID == snapshot.selectedThreadID
					&& snapshot.activeTurnID == timing.turnID
			guard timing.status == "inProgress", !hasConfirmedActiveExecution
			else
			{
				return timing
			}
			return ConversationTurnTiming(
				turnID: timing.turnID,
				status: "statusUnknown",
				startedAt: timing.startedAt,
				completedAt: timing.completedAt,
				durationMs: timing.durationMs
			)
		}
		let timingsChanged = requestedTurnTimings != displayTimings
		requestedTurnTimings = displayTimings
		prepareEntries(
			snapshot.entries,
			context: context,
			force: timingsChanged
		)
	}

	func prepareEntries(
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
			cancelWidthChangeReadingPosition()
			expandedEntryIDs.removeAll()
			collapsedGroupIDs.removeAll()
			expandedActivityIDs.removeAll()
			activityOutputPositions.removeAll()
			turnStatusTimer?.invalidate()
			turnStatusTimer = nil
		}
		requestedEntries = nextEntries
		requestedContext = context
		let keys = nextEntries.map
		{
			TranscriptPreparationCoordinator.ContentKey.make(
				for: $0,
				expanded: expandedEntryIDs.contains($0.id)
			)
		}
		transcriptPreparation.prepare(
			nextEntries,
			keys: keys,
			context: context
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
		var sourceEntryID: String? = nil
		var textLocation: Int? = nil
		var textOffset: CGFloat = 0
	}

	func readingAnchor() -> ReadingAnchor?
	{
		let visible = conversationScrollView.contentView.bounds
		let candidates =
			collectionView.collectionViewLayout?.layoutAttributesForElements(in: visible) ?? []
		return readingAnchor(using: candidates)
	}

	func readingAnchor(using candidates: [NSCollectionViewLayoutAttributes]) -> ReadingAnchor?
	{
		let visible = conversationScrollView.contentView.bounds
		let visibleItems = candidates.filter
		{
			$0.representedElementCategory == .item
				&& $0.frame.maxY > visible.minY && $0.frame.minY < visible.maxY
		}
		let itemsFromTop = visibleItems.sorted
		{
			$0.frame.minY < $1.frame.minY
		}
		guard let first = itemsFromTop.first,
				let index = first.indexPath?.item, displayedRows.indices.contains(index)
		else
		{
			return nil
		}
		var anchor = ReadingAnchor(
			entryID: displayedRows[index].id,
			offset: visible.minY - first.frame.minY,
			sourceEntryID: displayedRows[index].sourceEntryID
		)
		if case .message(let entry) = displayedRows[index],
			let content = preparedContents[entry.id],
			let text = ConversationCollectionItem.textReadingAnchor(
			content: content,
			width: first.frame.width,
			kind: entry.kind,
			offset: anchor.offset
			)
		{
			anchor.textLocation = text.character
			anchor.textOffset = text.offset
		}
		return anchor
	}

	private func applyEntries(
		_ nextEntries: [ConversationEntry],
		contents: [String: PreparedConversationContent],
		context: String?
	)
	{
		let contextChanged = renderedContext != context
		if contextChanged
		{
			cancelWidthChangeReadingPosition()
		}
		if !contextChanged
		{
			captureActivityOutputPositions()
		}
		let shouldFollowOutput = contextChanged || isNearBottom
		let anchor = shouldFollowOutput ? nil : readingAnchor()
		let nextRows = ConversationTranscriptRow.make(
			entries: nextEntries,
			timings: requestedTurnTimings,
			projectPath: projectPath,
			collapsedGroupIDs: collapsedGroupIDs,
			expandedActivityIDs: expandedActivityIDs
		)
		let previousRows = displayedRows
		let previousContents = preparedContents
		let sharedCount = min(
			previousRows.count,
			nextRows.count
		)
		let sharedIDsMatch = (0 ..< sharedCount).allSatisfy
		{
			previousRows[$0].id == nextRows[$0].id
		}
		let canUpdateRowsInPlace =
			!contextChanged && sharedIDsMatch && nextRows.count >= previousRows.count
		let changed = canUpdateRowsInPlace ? (0 ..< sharedCount).filter
		{
			previousRows[$0] != nextRows[$0]
				|| previousContents[previousRows[$0].id]?.attributedString
				!= contents[nextRows[$0].id]?.attributedString
		}.map
		{
			IndexPath(
				item: $0,
				section: 0
			)
		} : []
		let previousSizes = transcriptItemSizes(at: changed)

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
			displayedRows = nextRows
			replaceCollectionView()
		}
		renderedContext = context
		entries = nextEntries
		displayedRows = nextRows

		if canUpdateRowsInPlace
		{
			updateTranscriptItems(
				at: changed,
				previousRows: previousRows,
				sharedCount: sharedCount
			)
			invalidateTranscriptLayout(
				for: changed,
				previousRows: previousRows,
				previousSizes: previousSizes
			)
		}
		else
		{
			collectionView.reloadData()
		}

		turnNavigationRail.render(transcriptPreparation.turnSummaries)
		view.layoutSubtreeIfNeeded()
		collectionView.layoutSubtreeIfNeeded()
		restoreReadingPosition(
			followOutput: shouldFollowOutput,
			anchor: anchor
		)
		readingPositionChanged()
		scrollToRequestedItem()
		updateTurnStatusTimer()
	}

	private func transcriptItemSizes(at paths: [IndexPath]) -> [IndexPath: NSSize]
	{
		Dictionary(uniqueKeysWithValues: paths.compactMap
		{
			path -> (IndexPath, NSSize)? in
			collectionView.collectionViewLayout?.layoutAttributesForItem(at: path).map
			{
				(path, $0.frame.size)
			}
		})
	}

	private func updateTranscriptItems(
		at changedPaths: [IndexPath],
		previousRows: [ConversationTranscriptRow],
		sharedCount: Int
	)
	{
		let replacedPaths = Set(changedPaths.filter
		{
			!Self.shareCollectionItemClass(
				previousRows[$0.item],
				displayedRows[$0.item]
			)
		})
		let addedPaths = Set((sharedCount ..< displayedRows.count).map
		{
			IndexPath(
				item: $0,
				section: 0
			)
		})
		let requiresCollectionUpdates = !replacedPaths.isEmpty || !addedPaths.isEmpty
		if requiresCollectionUpdates
		{
			collectionView.performBatchUpdates
			{
				if !replacedPaths.isEmpty
				{
					collectionView.reloadItems(at: replacedPaths)
				}
				if !addedPaths.isEmpty
				{
					collectionView.insertItems(at: addedPaths)
				}
			}
		}

		for path in changedPaths where !replacedPaths.contains(path)
		{
			if let item = collectionView.item(at: path)
			{
				configureTranscriptItem(
					item,
					for: displayedRows[path.item]
				)
			}
		}
	}

	private func invalidateTranscriptLayout(
		for changedPaths: [IndexPath],
		previousRows: [ConversationTranscriptRow],
		previousSizes: [IndexPath: NSSize]
	)
	{
		guard let layout = collectionView.collectionViewLayout as? ConversationFlowLayout
		else
		{
			return
		}
		let metricsChanged = changedPaths.contains
		{
			path in
			previousSizes[path] != self.collectionView(
				collectionView,
				layout: layout,
				sizeForItemAt: path
			)
		}
		if metricsChanged
		{
			layout.invalidateContentMetrics()
			return
		}

		let spacingChanged = changedPaths.contains
		{
			path in
			[path.item, path.item + 1].contains
			{
				Self.hasCompactActivityGap(
					at: $0,
					in: previousRows
				)
					!= Self.hasCompactActivityGap(
						at: $0,
						in: displayedRows
					)
			}
		}
		if spacingChanged
		{
			layout.invalidateContentAttributes()
		}
	}

	private static func shareCollectionItemClass(
		_ previous: ConversationTranscriptRow,
		_ next: ConversationTranscriptRow
	) -> Bool
	{
		switch (previous, next)
		{
		case (.message, .message), (.activity, .activity), (.turnStatus, .turnStatus): true
		default: false
		}
	}

	private static func hasCompactActivityGap(
		at index: Int,
		in rows: [ConversationTranscriptRow]
	) -> Bool
	{
		guard index > 0, rows.indices.contains(index),
				case .activity(let current) = rows[index],
				case .activity(let previous) = rows[index - 1]
		else
		{
			return false
		}
		return current.groupID == previous.groupID
	}

}
