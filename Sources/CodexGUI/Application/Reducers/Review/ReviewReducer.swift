import Foundation

struct ReviewMarkerIdentity: Hashable
{
	let reference: ReviewReference
	let fingerprint: String
}

struct ReviewMarkerReadOperation: Equatable
{
	let context: OperationContext
	let conversation: ConversationKey
	let turnID: String
	let sourceRevision: Int
	let markerRevision: Int
	let identities: [ReviewMarkerIdentity]
}

struct ReviewMarkerWriteOperation: Equatable
{
	let context: OperationContext
	let conversation: ConversationKey
	let identity: ReviewMarkerIdentity
	let reviewed: Bool
	let sourceRevision: Int
	let markerRevision: Int
}

/// Review state is derived from reported turn content, never from a presumed Git revision.
@MainActor
enum ReviewReducer
{
	static let reducer = WorkspaceReducer(reduce: reduce)

	static func valid(
		_ context: OperationContext,
		_ model: WorkspaceModel
	) -> Bool
	{
		context.belongsTo(
			workspace: model.identity,
			generation: model.connection.generation
		)
	}

	static func identities(_ turn: ReviewTurn) -> [ReviewMarkerIdentity]
	{
		turn.files.flatMap
		{
			file in
			[ReviewMarkerIdentity(
				reference: ReviewReference(
					threadID: turn.threadID,
					turnID: turn.turnID,
					file: file
				),
				fingerprint: file.fingerprint
			)] + file.hunks.map
			{
				hunk in
				ReviewMarkerIdentity(
					reference: ReviewReference(
						threadID: turn.threadID,
						turnID: turn.turnID,
						file: file,
						hunk: hunk
					),
					fingerprint: hunk.fingerprint
				)
			}
		}
	}

	static func selectedTurn(
		_ model: WorkspaceModel,
		_ key: ConversationKey
	) -> ReviewTurn?
	{
		guard let review = model.review.conversations[key]
		else
		{
			return nil
		}
		return review.turns.first
		{
			$0.turnID == review.selectedTurnID
		}
	}

	static func reviewedReferences(
		_ model: WorkspaceModel,
		_ key: ConversationKey
	)
		-> Set<ReviewReference>
	{
		guard let turn = selectedTurn(
			model,
			key
		), let review = model.review.conversations[key]
		else
		{
			return []
		}
		return Set(identities(turn).compactMap
		{
			identity in
			review.markerFingerprints[identity.reference] == identity.fingerprint
				? identity.reference : nil
		})
	}

	/// Both composer and review use this exact source check before composing a draft revision.
	static func accepts(
		_ context: OperationContext,
		_ request: ChangeRequest,
		model: WorkspaceModel
	) -> Bool
	{
		let key = ConversationKey.thread(request.reference.threadID)
		guard valid(
			context,
			model
		), context.threadID == request.reference.threadID,
		model.conversations.selectedConversation == key,
		model.review.conversations[key]?.sourceRevision == request.sourceRevision,
		model.conversations.content[key]?.reviewSourceRevision == request.sourceRevision,
		let turn = selectedTurn(
			model,
			key
		), turn.turnID == request.reference.turnID,
		let file = turn.files.first(where:
			{
				$0.path == request.reference.path
			}),
		file.path == request.file.path, file.fingerprint == request.file.fingerprint,
		file.diff == request.file.diff, file.previousPath == request.file.previousPath,
		file.kind == request.file.kind
		else
		{
			return false
		}
		if let hunkID = request.reference.hunkID
		{
			guard let captured = request.hunk,
					let hunk = file.hunks.first(where:
					{
						$0.id == hunkID
					})
			else
			{
				return false
			}
			return hunk.id == captured.id && hunk.header == captured.header
				&& hunk.fingerprint == captured.fingerprint && hunk.text == captured.text
		}
		return request.hunk == nil
	}

	static func reduce(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	)
		-> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		switch action
		{
		case .connection(.projectOpened(
			let identity,
			_
		)):
			if model.identity == identity && !model.execution.isTaskActive
			{
				model.review = ReviewModel()
			}
		case .review(.turnSelected(
			let context,
			let key,
			let id
		)):
			guard valid(
				context,
				model
			), model.conversations.selectedConversation == key,
			context.threadID == threadID(key),
			model.review.conversations[key]?.turns
			.contains(where:
				{
					$0.turnID == id
				}) == true
			else
			{
				return result
			}
			model.review.conversations[key]?.selectedTurnID = id
			model.review.conversations[key]?.pendingMarkerLoad = nil
			model.review.conversations[key]?.loadedMarkerSnapshot = nil
		case .review(.markerRequested(
			let context,
			let identity,
			let reviewed
		)):
			guard applyRequestedMarker(
				context: context,
				identity: identity,
				reviewed: reviewed,
				model: &model,
				result: &result
			)
			else
			{
				return result
			}
		case .review(.markersReceived(
			let operation,
			let outcome
		)):
			guard applyReceivedMarkers(
				operation: operation,
				outcome: outcome,
				model: &model
			)
			else
			{
				return result
			}
		case .review(.markerPersistenceFinished(
			let operation,
			let outcome
		)):
			guard finishMarkerPersistence(
				operation: operation,
				outcome: outcome,
				model: &model
			)
			else
			{
				return result
			}
		default: break
		}
		if let context = observationContext(action), valid(
			context,
			model
		)
		{
			model.review.observationContext = context
		}
		refresh(
			&model,
			result: &result
		)
		return result
	}

	private static func applyRequestedMarker(
		context: OperationContext,
		identity: ReviewMarkerIdentity,
		reviewed: Bool,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	) -> Bool
	{
		let key = ConversationKey.thread(identity.reference.threadID)
		guard valid(
			context,
			model
		), context.threadID == identity.reference.threadID,
		model.conversations.selectedConversation == key,
		let turn = selectedTurn(
			model,
			key
		), identities(turn).contains(identity),
		var review = model.review.conversations[key]
		else
		{
			return false
		}
		review.markerRevision += 1
		review.pendingMarkerLoad = nil
		review.loadedMarkerSnapshot = nil
		let operation = ReviewMarkerWriteOperation(
			context: context,
			conversation: key,
			identity: identity,
			reviewed: reviewed,
			sourceRevision: review.sourceRevision,
			markerRevision: review.markerRevision
		)
		review.pendingMarkerWrites[identity.reference] = operation
		review.markerFingerprints[identity.reference] = reviewed ? identity.fingerprint : nil
		review.error = nil
		model.review.conversations[key] = review
		result.effects.append(.writeReviewMarker(operation))
		return true
	}

	private static func applyReceivedMarkers(
		operation: ReviewMarkerReadOperation,
		outcome: OperationResult<[ReviewMarkerIdentity]>,
		model: inout WorkspaceModel
	) -> Bool
	{
		guard valid(
			operation.context,
			model
		),
			var review = model.review.conversations[operation.conversation],
			review.pendingMarkerLoad == operation
		else
		{
			return false
		}
		// A matching ticket always retires, even when its conversation is offscreen.
		// A superseded ticket cannot retire a newer read or alter its source snapshot.
		review.pendingMarkerLoad = nil
		guard model.conversations.content[operation.conversation]?.reviewSourceRevision
			== operation.sourceRevision,
			review.sourceRevision == operation.sourceRevision,
			review.markerRevision == operation.markerRevision,
			review.selectedTurnID == operation.turnID,
			let turn = selectedTurn(
				model,
				operation.conversation
			),
			identities(turn) == operation.identities
		else
		{
			review.loadedMarkerSnapshot = nil
			model.review.conversations[operation.conversation] = review
			return false
		}

		switch outcome
		{
		case .succeeded(let marked):
			let accepted = Set(marked).intersection(operation.identities)
			for identity in operation.identities
			{
				review.markerFingerprints[identity.reference] = accepted.contains(identity)
					? identity.fingerprint : nil
			}
			review.error = nil
		case .failed(let failure): review.error = failure.message
		}
		model.review.conversations[operation.conversation] = review
		return true
	}

	private static func finishMarkerPersistence(
		operation: ReviewMarkerWriteOperation,
		outcome: OperationResult<Void>,
		model: inout WorkspaceModel
	) -> Bool
	{
		guard valid(
			operation.context,
			model
		),
			var review = model.review.conversations[operation.conversation],
			review.pendingMarkerWrites[operation.identity.reference] == operation
		else
		{
			return false
		}
		review.pendingMarkerWrites[operation.identity.reference] = nil
		if model.conversations.selectedConversation == operation.conversation,
			review.markerRevision == operation.markerRevision,
			review.sourceRevision == operation.sourceRevision,
			selectedTurn(
			model,
			operation.conversation
			).map(
			{
				identities($0)
					.contains(operation.identity)
			}
			) == true
		{
			switch outcome
			{
			case .succeeded: review.error = nil
			case .failed(let failure): review.error = failure.message
			}
		}
		model.review.conversations[operation.conversation] = review
		return true
	}

	/// Runs after accepted content composition and before the store publishes its atomic value.
	static func reduceDomainEvent(
		_ model: inout WorkspaceModel,
		_ event: WorkspaceDomainEvent
	) -> WorkspaceReduction
	{
		if case .submissionPrepared(let prepared) = event,
			prepared.submission.context.threadID == nil
		{
			let key = ConversationKey.thread(prepared.thread.summary.id)
			model.review.conversations[key] = model.review.conversations[.newChat]
			model.review.conversations[.newChat] = nil
			model.review.observationContext = prepared.submission.context
		}
		if case .connectionBegan = event
		{
			invalidatePending(&model)
		}
		if case .connectionDisconnected = event
		{
			invalidatePending(&model)
		}
		var result = WorkspaceReduction()
		refresh(
			&model,
			result: &result
		)
		return result
	}

	private static func invalidatePending(_ model: inout WorkspaceModel)
	{
		model.review.observationContext = nil
		for key in model.review.conversations.keys
		{
			model.review.conversations[key]?.pendingMarkerLoad = nil
			model.review.conversations[key]?.loadedMarkerSnapshot = nil
			model.review.conversations[key]?.pendingMarkerWrites.removeAll()
		}
	}

	private static func refresh(
		_ model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		for (key, content) in model.conversations.content
		{
			var review = model.review.conversations[key] ?? ConversationReviewModel()
			if review.sourceRevision != content.reviewSourceRevision
			{
				let wasFollowingLatestTurn = review.selectedTurnID == nil
					|| review.selectedTurnID == review.turns.last?.turnID
				review.turns = analyzedTurns(
					in: content,
					conversation: key,
					parsedChanges: &review.parsedChanges
				)
				if wasFollowingLatestTurn || !review.turns.contains(where:
					{
						$0.turnID == review.selectedTurnID
					})
				{
					review.selectedTurnID = review.turns.last?.turnID
				}
				review.sourceRevision = content.reviewSourceRevision
				review.pendingMarkerLoad = nil
				review.loadedMarkerSnapshot = nil
			}
			model.review.conversations[key] = review
			guard key == model.conversations.selectedConversation,
					let context = model.review.observationContext, valid(
					context,
					model
					),
					let turn = selectedTurn(
					model,
					key
					), review.pendingMarkerLoad == nil
			else
			{
				continue
			}
			let snapshot = identities(turn)
			// Read only after a source/selection event; successful results don't loop reads.
			guard review.loadedMarkerSnapshot != snapshot
			else
			{
				continue
			}
			var scoped = context
			scoped.threadID = turn.threadID
			scoped.turnID = turn.turnID
			let operation = ReviewMarkerReadOperation(
				context: scoped,
				conversation: key,
				turnID: turn.turnID,
				sourceRevision: review.sourceRevision,
				markerRevision: review.markerRevision,
				identities: snapshot
			)
			model.review.conversations[key]?.pendingMarkerLoad = operation
			model.review.conversations[key]?.loadedMarkerSnapshot = snapshot
			result.effects.append(.readReviewMarkers(operation))
		}
	}

	private static func analyzedTurns(
		in content: ConversationContentModel,
		conversation: ConversationKey,
		parsedChanges: inout [String: ReviewParsedChanges]
	) -> [ReviewTurn]
	{
		guard let threadID = threadID(conversation)
		else
		{
			return []
		}

		return ReviewAnalyzer.reviews(
			threadID: threadID,
			turns: content.loadedTurns,
			hasEarlierHistory: content.nextTurnsCursor != nil,
			liveChangeTurnID: content.liveChangeTurnID,
			parsedChanges: &parsedChanges
		)
	}

	private static func threadID(_ key: ConversationKey) -> String?
	{
		if case .thread(let id) = key
		{
			return id
		}
		return nil
	}

	private static func observationContext(_ action: WorkspaceAction) -> OperationContext?
	{
		switch action
		{
		case .review(.turnSelected(
			let context,
			_,
			_
		)),
		.review(.markerRequested(
			let context,
			_,
			_
		)),
		.review(.changeRequestPrepared(
			let context,
			_
		)): return context
		case .execution(.backendObserved(
			let context,
			_,
			_
		)),
		.execution(.reconciliationFinished(
			let context,
			_
		)),
		.execution(.submissionPrepared(
			let context,
			_
		)): return context
		case .execution(.historyObserved(
			let operation,
			_
		)): return operation.context
		case .conversations(.historyReceived(
			let operation,
			_
		)): return operation.context
		case .conversations(.selectionReceived(
			let context,
			_
		)),
		.conversations(.newChatOpened(let context)): return context

		case .conversations(.itemStarted(
			let context,
			_
		)),
		.conversations(.itemFinished(
			let context,
			_
		)),
		.conversations(.agentMessageDelta(
			let context,
			_
		)),
		.conversations(.commandOutputDelta(
			let context,
			_
		)),
		.conversations(.fileChangesReceived(
			let context,
			_
		)),
		.conversations(.aggregateDiffReceived(
			let context,
			_
		)): return context
		case .conversations(.earlierTurnsReceived(
			let operation,
			_
		)): return operation.context
		default: return nil
		}
	}
}
