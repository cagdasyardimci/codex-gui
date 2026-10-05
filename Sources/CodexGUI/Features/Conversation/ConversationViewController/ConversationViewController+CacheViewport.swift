import AppKit

@MainActor
extension ConversationViewController
{
	func queueViewportPublication()
	{
		guard !isAnimatingJump, renderedContext == requestedContext,
				onConversationViewportChanged != nil,
				let layout = collectionView.collectionViewLayout
		else
		{
			return
		}
		let visible = collectionView.visibleRect
		let rows = layout.layoutAttributesForElements(in: visible)
			.filter
			{
				$0.representedElementCategory == .item && $0.frame.intersects(visible)
			}
			.sorted
			{
				$0.frame.minY < $1.frame.minY
			}
		let turnIDs = rows.compactMap
		{
			attributes -> String? in
			guard let path = attributes.indexPath, displayedRows.indices.contains(path.item)
			else
			{
				return nil
			}
			let row = displayedRows[path.item]
			if case .turnStatus(let timing) = row
			{
				return timing.turnID
			}
			return row.sourceEntryID?.split(
				separator: ":",
				maxSplits: 1
			).first.map(String.init)
		}
		let viewport = ConversationViewport(
			turnIDs: Set(turnIDs),
			anchorTurnID: turnIDs.first,
			firstTurnID: turnIDs.first,
			lastTurnID: turnIDs.last,
			nearTop: visible.minY < visible.height,
			nearBottom: layout.collectionViewContentSize
				.height - visible.maxY < visible.height
		)
		guard viewport != lastPublishedViewport
		else
		{
			return
		}
		viewportPublicationTask?.cancel()
		let owner = renderedPresentation?.owner
		viewportPublicationTask = Task
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
			guard let self, !Task.isCancelled, renderedPresentation?.owner == owner
			else
			{
				return
			}
			lastPublishedViewport = viewport
			viewportPublicationTask = nil
			onConversationViewportChanged?(viewport)
		}
	}
}
