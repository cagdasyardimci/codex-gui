import AppKit

@MainActor
extension ConversationViewController
{
	func captureActivityOutputPositions()
	{
		for item in collectionView.visibleItems()
		{
			guard let activity = item as? ConversationActivityCollectionItem,
					let id = activity.activityID,
					let position = activity.outputReadingPosition()
			else
			{
				continue
			}
			activityOutputPositions[id] = position
		}
	}

	func toggleActivity(_ row: ConversationActivityRow)
	{
		if row.kind == .group
		{
			if !expandedGroupIDs.insert(row.groupID).inserted
			{
				expandedGroupIDs.remove(row.groupID)
			}
		}
		else if row.kind == .image
		{
			if !collapsedImageIDs.insert(row.groupID).inserted
			{
				collapsedImageIDs.remove(row.groupID)
			}
		}
		else if !expandedActivityIDs.insert(row.id).inserted
		{
			expandedActivityIDs.remove(row.id)
		}
		prepareEntries(
			requestedEntries,
			context: requestedContext,
			force: true
		)
	}

	func toggleTurnWork(_ turnID: String)
	{
		if !expandedTurnIDs.insert(turnID).inserted
		{
			expandedTurnIDs.remove(turnID)
		}
		prepareEntries(
			requestedEntries,
			context: requestedContext,
			force: true
		)
	}

	func updateTurnStatusTimer(now: @escaping @MainActor () -> Date =
	{
		Date()
	})
	{
		guard transcriptIsVisible, timingExecutionState.isBusy,
				requestedTurnTimings.contains(where:
				{
					$0.status == "inProgress" && $0.startedAt != nil
				})
		else
		{
			turnStatusTimer?.invalidate()
			turnStatusTimer = nil
			return
		}
		// Streaming updates must not postpone the next tick by recreating the timer.
		guard turnStatusTimer == nil
		else
		{
			return
		}
		let context = requestedContext
		let timer = Timer(
			timeInterval: 1,
			repeats: true
		)
		{
			[weak self] _ in
			MainActor.assumeIsolated
			{
				guard let self, self.requestedContext == context,
						self.timingExecutionState.isBusy
				else
				{
					return
				}
				for item in self.collectionView.visibleItems()
				{
					(item as? ConversationTurnStatusCollectionItem)?.refresh(now: now())
				}
			}
		}
		turnStatusTimer = timer
		RunLoop.main.add(
			timer,
			forMode: .common
		)
	}

}
