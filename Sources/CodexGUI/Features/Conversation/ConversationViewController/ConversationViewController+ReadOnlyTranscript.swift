import AppKit

@MainActor
extension ConversationViewController
{
	/// Reuses the canonical transcript renderer without selecting a workspace conversation.
	func renderTranscript(_ presentation: ConversationPresentation.Transcript)
	{
		guard transcriptOnly
		else
		{
			return
		}
		_ = view
		guard renderedReadOnlyTranscript != presentation
		else
		{
			return
		}
		if renderedReadOnlyTranscript?.owner != presentation.owner
		{
			resetTranscriptNavigation()
			selectionGeneration += 1
			bookmarks.removeAll()
		}
		renderedReadOnlyTranscript = presentation
		projectPath = presentation.owner.projectPath
		selectedThreadID = presentation.selectedThreadID
		// History reads do not establish live execution ownership or elapsed running time.
		timingExecutionState = .ready
		loadEarlierButton.isHidden = !presentation.canLoadEarlierTurns
		updateTranscriptUtilityRowVisibility()
		prepareTranscript(presentation)
		updateTurnStatusTimer()
	}

	func resetTranscriptNavigation()
	{
		turnNavigationTask?.cancel()
		viewportPublicationTask?.cancel()
		lastPublishedViewport = nil
		cancelNavigationMotion()
		pendingNavigationTurnID = nil
		requestedJumpItemID = nil
		jumpAnimationRevision += 1
		isAnimatingJump = false
		turnNavigationRail.dismissPreview()
		turnNavigationRail.render([])
	}
}
