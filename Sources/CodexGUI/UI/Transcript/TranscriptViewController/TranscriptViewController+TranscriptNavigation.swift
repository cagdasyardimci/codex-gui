import AppKit
import QuartzCore

// Reading anchors, bookmarks, scrolling, and live-resize continuity.
@MainActor
extension TranscriptViewController
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
		else if let anchor, let index = displayedRows.firstIndex(where:
			{
				$0.id == anchor.entryID
			}) ?? displayedRows.firstIndex(where:
			{
				anchor.sourceEntryID != nil && $0.sourceEntryID == anchor.sourceEntryID
			}),
			let attributes = collectionView.layoutAttributesForItem(
				at: IndexPath(
					item: index,
					section: 0
				)
			)
		{
			let clip = conversationScrollView.contentView
			var offset = anchor.offset
			if let character = anchor.textLocation,
				case .message(let entry) = displayedRows[index],
				let content = preparedContents[entry.id],
				let textOffset = ConversationCollectionItem.textReadingOffset(
				content: content,
				width: attributes.frame.width,
				kind: entry.kind,
				character: character,
				lineOffset: anchor.textOffset,
				imageAttachmentCount: entry.imageAttachments.count
				)
			{
				offset = textOffset
			}
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
							attributes.frame.minY + offset
						)
					)
				)
			)
			conversationScrollView.reflectScrolledClipView(clip)
		}
	}

	struct WidthChangeReadingPosition
	{
		let context: String?
		let followOutput: Bool
		let anchor: ReadingAnchor?
	}

	func captureWidthChangeReadingPosition(using attributes: [NSCollectionViewLayoutAttributes])
	{
		guard !liveResizeInProgress, !restoringWidthChangeReadingPosition,
				!displayedRows.isEmpty, requestedContext == renderedContext
		else
		{
			return
		}
		if let position = widthChangeReadingPosition, position.context == renderedContext
		{
			return
		}
		cancelWidthChangeReadingPosition()
		let followsOutput = isNearBottom
		let anchor = followsOutput ? nil : readingAnchor(using: attributes)
		widthChangeReadingPosition = WidthChangeReadingPosition(
			context: renderedContext,
			followOutput: followsOutput,
			anchor: anchor
		)
		widthChangeRestoreTask = Task
		{
			[weak self] in
			await Task.yield()
			guard !Task.isCancelled, let self,
					let position = self.widthChangeReadingPosition,
					position.context == self.renderedContext,
					position.context == self.requestedContext
			else
			{
				return
			}
			self.restoringWidthChangeReadingPosition = true
			defer
			{
				self.restoringWidthChangeReadingPosition = false
				self.widthChangeReadingPosition = nil
				self.widthChangeRestoreTask = nil
			}
			self.view.layoutSubtreeIfNeeded()
			self.collectionView.layoutSubtreeIfNeeded()
			self.restoreReadingPosition(
				followOutput: position.followOutput,
				anchor: position.anchor
			)
			self.readingPositionChanged()
		}
	}

	func cancelWidthChangeReadingPosition()
	{
		widthChangeRestoreTask?.cancel()
		widthChangeRestoreTask = nil
		widthChangeReadingPosition = nil
	}

	func scrollToRequestedItem()
	{
		guard let requestedJumpItemID
		else
		{
			return
		}
		var revealedWork = false
		if let turnID = workEntryIDsByTurn.first(where:
			{
				$0.value.contains(requestedJumpItemID)
			})?
			.key,
			expandedTurnIDs.insert(turnID).inserted
		{
			revealedWork = true
		}
		let allRows = ConversationTranscriptRow.make(
			entries: entries,
			projectPath: projectPath,
			expandedGroupIDs: Set(entries.map
			{
				"activity-group:\($0.id)"
			}),
			preparedNetChanges: transcriptPreparation.preparedNetChanges
		)
		if let group = allRows.compactMap(
			{
				row -> ConversationActivityRow? in
				guard case .activity(let activity) = row,
						activity.sourceEntryID == requestedJumpItemID,
						activity.kind != .group
				else
				{
					return nil
				}
				return activity
			}
		).first,
			(group.kind == .image
				? collapsedImageIDs.remove(group.groupID) != nil
				: allRows.contains
				{
					if case .activity(let row) = $0
					{
						return row.kind == .group && row.groupID == group.groupID
					}
					return false
				} && expandedGroupIDs.insert(group.groupID).inserted)
		{
			prepareEntries(
				requestedEntries,
				context: requestedContext,
				force: true
			)
			return
		}
		if revealedWork
		{
			prepareEntries(
				requestedEntries,
				context: requestedContext,
				force: true
			)
			return
		}
		guard let index = displayedRows.firstIndex(where:
			{
				$0.id == requestedJumpItemID
			}) ?? displayedRows.firstIndex(where:
			{
				$0.sourceEntryID == requestedJumpItemID
			})
		else
		{
			return
		}

		cancelWidthChangeReadingPosition()
		let path = IndexPath(
			item: index,
			section: 0
		)
		collectionView.selectItems(
			at: [path],
			scrollPosition: []
		)
		if let attributes = collectionView.collectionViewLayout?
			.layoutAttributesForItem(at: path)
		{
			let clip = conversationScrollView.contentView
			var destination = clip.bounds
			destination.origin.y = attributes.frame.minY
			destination = clip.constrainBoundsRect(destination)
			animateJump(to: destination.origin)
		}

		if liveResizeInProgress
		{
			resizeContext = renderedContext
			resizeFollowingOutput = false
			resizeReadingAnchor = readingAnchor()
		}
		self.requestedJumpItemID = nil
		pendingNavigationTurnID = nil
		if !isAnimatingJump
		{
			readingPositionChanged()
		}
		onJumpDisplayed?()
	}

	private func animateJump(to destination: NSPoint)
	{
		cancelNavigationMotion()
		let clip = conversationScrollView.contentView
		let origin = clip.bounds.origin
		guard origin != destination,
				!shouldReduceMotion()
		else
		{
			applyJumpOrigin(destination)
			return
		}

		let revision = jumpAnimationRevision
		let frameRate = min(
			120,
			max(
				60,
				view.window?.screen?.maximumFramesPerSecond ?? 60
			)
		)
		let started = CACurrentMediaTime()
		isAnimatingJump = true
		jumpAnimationCompletion = Task
		{
			@MainActor [weak self] in
			while !Task.isCancelled
			{
				let elapsed = min(
					1,
					(CACurrentMediaTime() - started) / 0.22
				)
				let eased = CGFloat(TransitionEasing.easeInEaseOut(elapsed))
				do
				{
					guard let self, self.jumpAnimationRevision == revision
					else
					{
						return
					}
					if elapsed >= 1 || self.shouldReduceMotion()
					{
						self.applyJumpOrigin(destination)
						guard self.jumpAnimationRevision == revision
						else
						{
							return
						}
						self.isAnimatingJump = false
						self.jumpAnimationCompletion = nil
						self.readingPositionChanged()
						return
					}
					self.applyJumpOrigin(NSPoint(
						x: origin.x + (destination.x - origin.x) * eased,
						y: origin.y + (destination.y - origin.y) * eased
					))
				}
				do
				{
					try await Task.sleep(nanoseconds: UInt64(1_000_000_000 / frameRate))
				}
				catch
				{
					return
				}
			}
		}
	}

	private func applyJumpOrigin(_ origin: NSPoint)
	{
		let clip = conversationScrollView.contentView
		var bounds = clip.bounds
		bounds.origin = origin
		clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
		conversationScrollView.reflectScrolledClipView(clip)
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
		guard !displayedRows.isEmpty
		else
		{
			return
		}
		collectionView.layoutSubtreeIfNeeded()
		let clip = conversationScrollView.contentView
		let contentHeight = collectionView.collectionViewLayout?.collectionViewContentSize.height
			?? collectionView.bounds.height
		// Follow the full transcript extent in the collection's flipped coordinates,
		// including the space after the reply.
		// Aligning the last item alone leaves the section's bottom inset offscreen.
		clip.scroll(to: NSPoint(
			x: 0,
			y: collectionView.isFlipped ? max(
				0,
				contentHeight - clip.bounds.height
			) : 0
		))
		conversationScrollView.reflectScrolledClipView(clip)
	}

	@objc func transcriptWillStartLiveResize(_ notification: Notification)
	{
		guard notification.object as? NSWindow === view.window
		else
		{
			return
		}
		beginTranscriptResize(reason: .window)
	}

	func beginTranscriptResize(reason: TranscriptResizeReason)
	{
		guard transcriptResizeReasons.insert(reason).inserted, !liveResizeInProgress
		else
		{
			return
		}
		cancelWidthChangeReadingPosition()
		resizeContext = renderedContext
		resizeFollowingOutput = isNearBottom
		resizeReadingAnchor = resizeFollowingOutput ? nil : readingAnchor()
		needsFinalResizeMetrics = false
		liveResizeInProgress = true
		updateLiveResizeVisibleItems()
	}

	@objc func transcriptDidEndLiveResize(_ notification: Notification)
	{
		guard notification.object as? NSWindow === view.window
		else
		{
			return
		}
		endTranscriptResize(reason: .window)
	}

	func endTranscriptResize(reason: TranscriptResizeReason)
	{
		guard transcriptResizeReasons.remove(reason) != nil, transcriptResizeReasons.isEmpty,
				liveResizeInProgress
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
		cancelWidthChangeReadingPosition()
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
				displayedRows.indices.contains(indexPath.item) ? displayedRows[indexPath.item]
					.id : nil
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
		if let event = NSApp.currentEvent, event.type == .scrollWheel,
			event.windowNumber == view.window?.windowNumber,
			conversationScrollView.bounds.contains(conversationScrollView.convert(
			event.locationInWindow,
			from: nil
			)),
			(isAnimatingJump || requestedJumpItemID != nil || pendingNavigationTurnID != nil)
		{
			turnNavigationTask?.cancel()
			requestedJumpItemID = nil
			pendingNavigationTurnID = nil
			cancelNavigationMotion()
			onJumpDisplayed?()
		}
		updateTurnNavigationPosition()
		queueViewportPublication()
		latestButton.isHidden = entries.isEmpty || isNearBottom
		updateTranscriptUtilityRowVisibility()
		if liveResizeInProgress
		{
			updateLiveResizeVisibleItems()
		}
	}

	func cancelNavigationMotion()
	{
		jumpAnimationRevision += 1
		jumpAnimationCompletion?.cancel()
		jumpAnimationCompletion = nil
		isAnimatingJump = false
	}

	@objc func showLatestMessage()
	{
		turnNavigationTask?.cancel()
		cancelNavigationMotion()
		if let turnID = turnNavigationRail.summaries.last?.turnID, let onJumpToTurnReference
		{
			onJumpToTurnReference(turnID)
			return
		}
		cancelWidthChangeReadingPosition()
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
