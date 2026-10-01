import AppKit

// Reading anchors, bookmarks, scrolling, and live-resize continuity.
@MainActor
extension ConversationViewController
{
	func restoreReadingPosition(
		followOutput: Bool,
		anchor: ReadingAnchor?
	)
	{
		if followOutput
		{
			scrollToBottom()
		}
		else if let anchor, let index = entries.firstIndex(where:
			{
				$0.id == anchor.entryID
			}),
			let attributes = collectionView.layoutAttributesForItem(
				at: IndexPath(
					item: index,
					section: 0
				)
			)
		{
			let clip = conversationScrollView.contentView
			let maximumY = max(
				0,
				collectionView.bounds.height - clip.bounds.height
			)
			clip.scroll(
				to: NSPoint(
					x: 0,
					y: min(
						maximumY,
						max(
							0,
							attributes.frame.minY + anchor.offset
						)
					)
				)
			)
			conversationScrollView.reflectScrolledClipView(clip)
		}
	}

	func renderJumpTargets(_ targets: [ConversationJumpTarget])
	{
		guard targets != jumpTargets
		else
		{
			return
		}
		jumpTargets = targets
		jumpButton.removeAllItems()
		jumpButton.addItem(withTitle: "Jump to…")
		jumpButton.item(at: 0)?.isEnabled = false
		for target in targets
		{
			let category: String
			switch target.kind
			{
			case .userRequest: category = "Request"
			case .changedFile: category = "File"
			case .failure: category = "Failure"
			}
			jumpButton.addItem(withTitle: "\(category): \(target.title)")
			jumpButton.lastItem?.representedObject = target.id
			jumpButton.lastItem?.toolTip = target.title
		}
		jumpButton.selectItem(at: 0)
		jumpButton.isEnabled = !targets.isEmpty
	}

	func scrollToRequestedItem()
	{
		guard let requestedJumpItemID,
				let index = entries.firstIndex(where:
				{
					$0.id == requestedJumpItemID
				})
		else
		{
			return
		}
		collectionView.scrollToItems(
			at: [IndexPath(
				item: index,
				section: 0
			)],
			scrollPosition: .top
		)
		collectionView.selectItems(
			at: [IndexPath(
				item: index,
				section: 0
			)],
			scrollPosition: .top
		)
		if liveResizeInProgress
		{
			resizeContext = renderedContext
			resizeFollowingOutput = false
			resizeReadingAnchor = readingAnchor()
		}
		self.requestedJumpItemID = nil
		updateBookmarkButton()
		onJumpDisplayed?()
	}

	func updateBookmarkButton()
	{
		let index = collectionView.selectionIndexPaths.first?.item
		bookmarkButton.isEnabled = index.map
		{
			entries.indices.contains($0)
		} == true
	}

	@objc func bookmarkSelected()
	{
		guard let index = collectionView.selectionIndexPaths.first?.item,
				entries.indices.contains(index), let selectedThreadID,
				let separator = entries[index].id.firstIndex(of: ":")
		else
		{
			return
		}
		let entry = entries[index]
		let turnID = String(entry.id[..<separator])
		let itemID = String(entry.id[entry.id.index(after: separator)...])
		let existing = bookmarks.first
		{
			$0.threadID == selectedThreadID && $0.turnID == turnID && $0.itemID == itemID
		}
		if let existing
		{
			onToggleBookmark?(existing)
			return
		}
		let alert = NSAlert()
		alert.messageText = "Bookmark Message"
		alert.informativeText = String(entry.body.prefix(300))
		alert.addButton(withTitle: "Answer")
		alert.addButton(withTitle: "Decision")
		alert.addButton(withTitle: "Cancel")
		guard let window = view.window
		else
		{
			return
		}
		let generation = selectionGeneration
		alert.beginSheetModal(for: window)
		{
			[weak self] response in
			guard self?.selectionGeneration == generation
			else
			{
				return
			}
			let kind: ConversationBookmarkKind
			switch response
			{
			case .alertFirstButtonReturn: kind = .answer
			case .alertSecondButtonReturn: kind = .decision
			default: return
			}
			self?.onToggleBookmark?(
				ConversationBookmark(
					threadID: selectedThreadID,
					turnID: turnID,
					itemID: itemID,
					kind: kind,
					label: String(entry.body.prefix(100))
				)
			)
		}
	}

	@objc func jumpToSelectedTarget()
	{
		guard let id = jumpButton.selectedItem?.representedObject as? String,
				let target = jumpTargets.first(where:
				{
					$0.id == id
				})
		else
		{
			return
		}
		onJumpTarget?(target)
		jumpButton.selectItem(at: 0)
	}

	var isNearBottom: Bool
	{
		let clipView = conversationScrollView.contentView
		let visibleBottom = clipView.bounds.maxY
		let contentBottom = collectionView.bounds.maxY
		return contentBottom - visibleBottom < 48
	}

	private func scrollToBottom()
	{
		guard !entries.isEmpty
		else
		{
			return
		}
		collectionView.scrollToItems(
			at: [IndexPath(
				item: entries.count - 1,
				section: 0
			)],
			scrollPosition: .bottom
		)
	}

	@objc func transcriptWillStartLiveResize(_ notification: Notification)
	{
		guard notification.object as? NSWindow === view.window
		else
		{
			return
		}
		resizeContext = renderedContext
		resizeFollowingOutput = isNearBottom
		resizeReadingAnchor = resizeFollowingOutput ? nil : readingAnchor()
		needsFinalResizeMetrics = false
		liveResizeInProgress = true
		updateLiveResizeVisibleItems()
	}

	@objc func transcriptDidEndLiveResize(_ notification: Notification)
	{
		guard notification.object as? NSWindow === view.window, liveResizeInProgress
		else
		{
			return
		}
		let sameContext = resizeContext == renderedContext
		let followOutput = sameContext ? resizeFollowingOutput : isNearBottom
		let anchor = sameContext ? resizeReadingAnchor : readingAnchor()
		liveResizeInProgress = false
		visibleResizeRefreshTimer?.invalidate()
		visibleResizeRefreshTimer = nil
		liveResizeVisibleIDs.removeAll()
		if needsFinalResizeMetrics
		{
			(collectionView.collectionViewLayout as? ConversationFlowLayout)?
				.invalidateContentMetrics()
			view.layoutSubtreeIfNeeded()
			collectionView.layoutSubtreeIfNeeded()
		}
		needsFinalResizeMetrics = false
		resizeContext = nil
		resizeReadingAnchor = nil
		restoreReadingPosition(
			followOutput: followOutput,
			anchor: anchor
		)
		readingPositionChanged()
		scrollToRequestedItem()
	}

	@objc func transcriptDidLiveScroll(_ notification: Notification)
	{
		guard liveResizeInProgress
		else
		{
			return
		}
		resizeContext = renderedContext
		resizeFollowingOutput = isNearBottom
		resizeReadingAnchor = resizeFollowingOutput ? nil : readingAnchor()
		updateLiveResizeVisibleItems()
	}

	private func updateLiveResizeVisibleItems()
	{
		liveResizeVisibleIDs = Set(
			collectionView.indexPathsForVisibleItems().compactMap
			{
				indexPath in
				entries.indices.contains(indexPath.item) ? entries[indexPath.item].id : nil
			}
		)
		let width = ConversationFlowLayout.contentWidth(in: collectionView.bounds.width)
		if liveResizeVisibleIDs.contains(where:
			{
				id in
				measuredItemSizes[id].map
				{
					$0.size.width != width
				} == true
			})
		{
			scheduleVisibleResizeMetrics()
		}
	}

	func scheduleVisibleResizeMetrics()
	{
		guard visibleResizeRefreshTimer == nil
		else
		{
			return
		}
		let timer = Timer(
			timeInterval: 0,
			target: self,
			selector: #selector(refreshVisibleResizeMetrics(_:)),
			userInfo: nil,
			repeats: false
		)
		visibleResizeRefreshTimer = timer
		// Common modes keep visible rows current while resize or scroll tracking is active.
		RunLoop.main.add(
			timer,
			forMode: .common
		)
	}

	@objc private func refreshVisibleResizeMetrics(_ timer: Timer)
	{
		visibleResizeRefreshTimer = nil
		guard liveResizeInProgress
		else
		{
			return
		}
		(collectionView.collectionViewLayout as? ConversationFlowLayout)?.invalidateContentMetrics()
	}

	@objc func readingPositionChanged()
	{
		updateTurnNavigationPosition()
		latestButton.isHidden = entries.isEmpty || isNearBottom
		if liveResizeInProgress
		{
			updateLiveResizeVisibleItems()
		}
	}

	@objc func showLatestMessage()
	{
		if liveResizeInProgress
		{
			resizeContext = renderedContext
			resizeFollowingOutput = true
			resizeReadingAnchor = nil
		}
		scrollToBottom()
		readingPositionChanged()
	}

	@objc func loadEarlierTurns()
	{
		onLoadEarlierTurns?()
	}

}
