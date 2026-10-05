import Foundation

extension WorkspaceStoreInputs
{
	/// Follow-ups return through the same identity-capture boundary as user intents.
	func captureConversationRead(_ followUp: ConversationReadFollowUp)
	{
		let scope = followUp.scope
		guard !store.isRetired, scope.workspace == store.model.identity,
				scope.generation == store.model.connection.generation,
				store.model.connection.isConnected
		else
		{
			return
		}
		switch followUp
		{
		case .references(
			_,
			let cursor
		):
			guard store.model.conversations.selectedConversation == .thread(scope.threadID)
			else
			{
				return
			}
			requestTurnReferences(
				context: store.operationContext(threadID: scope.threadID),
				cursor: cursor
			)
		case .window(
			_,
			let reference,
			let commandRevision
		):
			guard store.model.conversations.selectedConversation == .thread(scope.threadID),
					store.model.conversations.turnReferenceIndices[scope.threadID]?
					.windowQueue.first == reference
			else
			{
				return
			}
			store.dispatch(.conversations(.turnContentsRequested(ConversationTurnReadOperation(
				context: store.operationContext(threadID: scope.threadID),
				reference: reference,
				commandRevision: commandRevision,
				isWindow: true
			))))
		case .previewExpiry:
			store.dispatch(.conversations(.previewExpiryRequested(
				store.operationContext(threadID: scope.threadID)
			)))
		}
	}

	func requestTurnReferences(
		context: OperationContext,
		cursor: String?
	)
	{
		var operation = TurnReferenceReadOperation(
			context: context,
			cursor: cursor
		)
		if let threadID = context.threadID, let path = context.workspace.canonicalCheckoutPath,
			let summary = store.model.conversations.threads.first(where:
			{
				$0.id == threadID
			}),
			(try? CheckoutIdentity.validate(
			cwd: summary.cwd,
			expectedDirectory: URL(fileURLWithPath: path)
			)) != nil
		{
			operation.summaryOwnership = ConversationSummaryOwnership(
				summaryCWD: summary.cwd,
				canonicalCheckoutPath: path
			)
		}
		store.dispatch(.conversations(.turnReferencesRequested(operation)))
	}
}
