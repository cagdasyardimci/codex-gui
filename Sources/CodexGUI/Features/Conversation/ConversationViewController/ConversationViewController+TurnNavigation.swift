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
			turnNavigationRail.topAnchor.constraint(equalTo: conversationScrollView.topAnchor),
			turnNavigationRail.bottomAnchor
				.constraint(equalTo: conversationScrollView.bottomAnchor),
		])
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
			jumpToEntry(id: summary.entryID)
			readingPositionChanged()
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
					entries.contains(where:
					{
						$0.id == summary.entryID
					}),
					let separator = summary.entryID.firstIndex(of: ":")
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
				itemID: String(summary.entryID[summary.entryID.index(after: separator)...]),
				kind: .answer,
				label: String(summary.title.prefix(100))
			))
		}
	}

	func updateTurnNavigationPosition()
	{
		let visibleTop = conversationScrollView.contentView.bounds.minY
		let visibleIndices = collectionView.indexPathsForVisibleItems().map(\.item).sorted()
		let index = visibleIndices.first
		{
			guard let frame = collectionView.layoutAttributesForItem(
				at: IndexPath(
					item: $0,
					section: 0
				)
			)?.frame
			else
			{
				return false
			}
			return frame.maxY > visibleTop
		}
		if let index, displayedRows.indices.contains(index),
			case .turnStatus(let timing) = displayedRows[index]
		{
			turnNavigationRail.updateActiveTurn(timing.turnID)
			return
		}
		guard let index, displayedRows.indices.contains(index),
				let sourceID = displayedRows[index].sourceEntryID,
				let separator = sourceID.firstIndex(of: ":")
		else
		{
			turnNavigationRail.updateActiveTurn(nil)
			return
		}
		turnNavigationRail.updateActiveTurn(String(sourceID[..<separator]))
	}
}
