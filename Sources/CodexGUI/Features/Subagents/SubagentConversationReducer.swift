import Foundation

@MainActor
enum SubagentConversationReducer
{
	enum Action
	{
		case select(
			CodexSubagentActivity,
			requestID: Int
		)
		case back
		case refresh(requestID: Int)
		case retry(requestID: Int)
		case loadEarlier(requestID: Int)
		case loaded(
			requestID: Int,
			detail: ThreadDetail
		)
		case earlierLoaded(
			requestID: Int,
			turns: [CodexTurn],
			nextCursor: String?
		)
		case failed(
			requestID: Int,
			message: String,
			paginationCursor: String?
		)
	}

	enum Effect: Equatable
	{
		case cancel
		case read(
			threadID: String,
			requestID: Int
		)
		case earlier(
			threadID: String,
			cursor: String,
			requestID: Int
		)
	}

	static func reduce(
		_ state: inout SubagentConversationState,
		_ action: Action
	) -> [Effect]
	{
		switch action
		{
		case .select(
			let agent,
			let requestID
		):
			guard let threadID = agent.conversationThreadID
			else
			{
				return []
			}
			state = SubagentConversationState(agent: agent)
			beginRequest(
				requestID,
				state: &state
			)
			return [.cancel, .read(
				threadID: threadID,
				requestID: requestID
			)]
		case .back:
			state = SubagentConversationState()
			return [.cancel]
		case .refresh(let requestID):
			guard let threadID = state.selectedThreadID
			else
			{
				return []
			}
			beginRequest(
				requestID,
				state: &state
			)
			return [.read(
				threadID: threadID,
				requestID: requestID
			)]
		case .retry(let requestID):
			guard !state.isLoading, let threadID = state.selectedThreadID
			else
			{
				return []
			}
			let cursor = state.failedPaginationCursor
			beginRequest(
				requestID,
				state: &state
			)
			if let cursor
			{
				return [.earlier(
					threadID: threadID,
					cursor: cursor,
					requestID: requestID
				)]
			}
			return [.read(
				threadID: threadID,
				requestID: requestID
			)]
		case .loadEarlier(let requestID):
			guard !state.isLoading, let threadID = state.selectedThreadID,
					let cursor = state.nextCursor
			else
			{
				return []
			}
			beginRequest(
				requestID,
				state: &state
			)
			return [.earlier(
				threadID: threadID,
				cursor: cursor,
				requestID: requestID
			)]
		case .loaded(
			let requestID,
			let detail
		):
			guard state.requestID == requestID, detail.summary.id == state.selectedThreadID
			else
			{
				return []
			}
			let incomingTurns = Dictionary(uniqueKeysWithValues: detail.turns.map
			{
				($0.id, $0)
			})
			let existingTurnIDs = Set(state.loadedTurns.map(\.id))
			let updatedTurns = state.loadedTurns.map
			{
				incomingTurns[$0.id] ?? $0
			}
			let appendedTurns = detail.turns.filter
			{
				!existingTurnIDs.contains($0.id)
			}
			// Retain turns that aged out of the latest page; replace matching turns completely.
			state.loadedTurns = updatedTurns + appendedTurns
			projectTranscript(&state)
			if !state.hasLoadedEarlierPages
			{
				state.nextCursor = detail.nextTurnsCursor
			}
			state.settings = detail.settings
			finishRequest(&state)
		case .earlierLoaded(
			let requestID,
			let turns,
			let nextCursor
		):
			guard state.requestID == requestID
			else
			{
				return []
			}
			let existingTurnIDs = Set(state.loadedTurns.map(\.id))
			let earlierTurns = turns.filter
			{
				!existingTurnIDs.contains($0.id)
			}
			state.loadedTurns = earlierTurns + state.loadedTurns
			projectTranscript(&state)
			state.hasLoadedEarlierPages = true
			state.nextCursor = nextCursor
			finishRequest(&state)
		case .failed(
			let requestID,
			let message,
			let paginationCursor
		):
			guard state.requestID == requestID
			else
			{
				return []
			}
			state.requestID = nil
			state.isLoading = false
			state.error = message
			state.failedPaginationCursor = paginationCursor
		}
		return []
	}

	private static func beginRequest(
		_ requestID: Int,
		state: inout SubagentConversationState
	)
	{
		state.requestID = requestID
		state.isLoading = true
		state.error = nil
		state.failedPaginationCursor = nil
	}

	private static func finishRequest(_ state: inout SubagentConversationState)
	{
		state.requestID = nil
		state.isLoading = false
		state.error = nil
		state.failedPaginationCursor = nil
	}

	private static func projectTranscript(_ state: inout SubagentConversationState)
	{
		state.entries = ConversationContentReducer.entries(for: state.loadedTurns)
		state.turnTimings = state.loadedTurns.map
		{
			ConversationTurnTiming(turn: $0)
		}
	}
}
