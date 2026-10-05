import AppKit

@MainActor
extension ConversationViewController
{
	func configureTurnNavigation(in container: NSView)
	{
		turnNavigationRail.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(turnNavigationRail)
		NSLayoutConstraint.activate([
			turnNavigationRail.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: 12
			),
			turnNavigationRail.widthAnchor.constraint(equalToConstant: 32),
			turnNavigationRail.topAnchor.constraint(
				equalTo: container.topAnchor,
				constant: 12
			),
			turnNavigationRail.bottomAnchor.constraint(
				equalTo: container.bottomAnchor,
				constant: -12
			),
		])
		turnNavigationRail.onLoadTurnPreview =
		{
			[weak self] in self?.onLoadTurnPreview?($0)
		}
		turnNavigationRail.onLoadEarlierReferences =
		{
			[weak self] in self?.onLoadEarlierTurnReferences?()
		}
		turnNavigationRail.onJump =
		{
			[weak self] summary in
			guard let self,
					turnNavigationRail.summaries.contains(where:
					{
						$0.entryID == summary.entryID
					})
			else
			{
				return
			}
			turnNavigationTask?.cancel()
			pendingNavigationTurnID = summary.turnID
			turnNavigationRail.updateActiveTurn(summary.turnID)
			if !summary.isContentLoaded
			{
				let owner = renderedPresentation?.owner
				turnNavigationTask = Task
				{
					[weak self] in
					do
					{
						try await Task
							.sleep(for: .milliseconds(ConversationCachePolicy.debounceMilliseconds))
					}
					catch
					{
						return
					}
					guard let self, !Task.isCancelled,
							renderedPresentation?.owner == owner
					else
					{
						return
					}
					turnNavigationTask = nil
					onJumpToTurnReference?(summary.turnID)
				}
				return
			}
			if let onJumpToTurnReference
			{
				onJumpToTurnReference(summary.turnID)
			}
			else
			{
				jumpToEntry(id: summary.entryID)
			}
		}
		turnNavigationRail.isBookmarked =
		{
			[weak self] summary in
			guard let self
			else
			{
				return false
			}
			return bookmarks.contains
			{
				$0.threadID == selectedThreadID && $0.turnID == summary.turnID
			}
		}
		turnNavigationRail.onBookmark =
		{
			[weak self] summary in
			guard let self, let selectedThreadID,
					turnNavigationRail.summaries.contains(where:
					{
						$0.entryID == summary.entryID
					}),
					let identity = ConversationEntryIdentity(summary.entryID)
			else
			{
				return
			}
			let existing = bookmarks.first
			{
				$0.threadID == selectedThreadID && $0.turnID == summary.turnID
			}
			onToggleBookmark?(existing ?? ConversationBookmark(
				threadID: selectedThreadID,
				turnID: summary.turnID,
				itemID: summary.isContentLoaded ? identity.itemID : nil,
				kind: .answer,
				label: String(summary.title.prefix(100))
			))
		}
	}

	func updateTurnNavigationSummaries(includeLoaded: Bool = true)
	{
		let loaded = includeLoaded && renderedContext == requestedContext ? transcriptPreparation
			.turnSummaries : []
		turnNavigationRail.render(ConversationTurnSummary.navigation(
			references: renderedPresentation?.navigation.turnReferences ?? [],
			loaded: loaded,
			cached: renderedPresentation?.navigation.turnPreviews ?? [],
			errors: renderedPresentation?.navigation.turnPreviewErrors ?? [:]
		))
	}

	func updateTurnNavigationPosition()
	{
		guard !isAnimatingJump
		else
		{
			return
		}
		guard !turnNavigationRail.summaries.isEmpty
		else
		{
			turnNavigationRail.updateActiveTurn(nil)
			return
		}
		let visible = collectionView.visibleRect
		guard let layout = collectionView.collectionViewLayout,
				layout.collectionViewContentSize.height > visible.height + 1
		else
		{
			return
		}
		if isNearBottom
		{
			turnNavigationRail.updateActiveTurn(turnNavigationRail.summaries.last?.turnID)
			return
		}
		let visibleItems = layout.layoutAttributesForElements(in: visible).filter
		{
			$0.representedElementCategory == .item
				&& $0.frame.intersects(visible)
		}
		let topmostItem = visibleItems.min(by:
			{
				$0.frame.minY < $1.frame.minY
			})
		let index = topmostItem?.indexPath?.item
		if let index, displayedRows.indices.contains(index),
			case .turnStatus(let timing) = displayedRows[index]
		{
			turnNavigationRail.updateActiveTurn(timing.turnID)
			return
		}
		guard let index, displayedRows.indices.contains(index),
				let sourceID = displayedRows[index].sourceEntryID,
				let identity = ConversationEntryIdentity(sourceID)
		else
		{
			return
		}
		turnNavigationRail.updateActiveTurn(identity.turnID)
	}
}
