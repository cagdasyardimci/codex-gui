import Foundation

@MainActor
final class SubagentConversationRuntime
{
	private(set) var state = SubagentConversationState()
	var onChange: ((SubagentConversationState) -> Void)?

	private let service: any CodexService
	private let projectPath: String?
	private var nextRequestID = 0
	private var requestTask: Task<Void, Never>?
	private var refreshTask: Task<Void, Never>?
	private var needsRefresh = false
	private var isInvalidated = false

	init(
		service: any CodexService,
		projectPath: String?
	)
	{
		self.service = service
		self.projectPath = projectPath
	}

	func select(_ agent: CodexSubagentActivity)
	{
		guard !isInvalidated, agent.conversationThreadID != nil
		else
		{
			return
		}
		send(.select(
			agent,
			requestID: requestID()
		))
	}

	func back()
	{
		send(.back)
	}

	func retry()
	{
		guard !isInvalidated
		else
		{
			return
		}
		send(.retry(requestID: requestID()))
	}

	func loadEarlierTurns()
	{
		guard !isInvalidated
		else
		{
			return
		}
		send(.loadEarlier(requestID: requestID()))
	}

	func invalidate()
	{
		isInvalidated = true
		back()
	}

	func receive(_ event: AppServerEvent)
	{
		guard !isInvalidated, let threadID = state.selectedThreadID,
				event.turnContentIdentity?.threadID == threadID
		else
		{
			return
		}
		needsRefresh = true
		scheduleRefresh()
	}

	private func requestID() -> Int
	{
		nextRequestID += 1
		return nextRequestID
	}

	private func send(_ action: SubagentConversationReducer.Action)
	{
		let effects = SubagentConversationReducer.reduce(
			&state,
			action
		)
		for effect in effects
		{
			run(effect)
		}
		onChange?(state)
	}

	private func run(_ effect: SubagentConversationReducer.Effect)
	{
		switch effect
		{
		case .cancel:
			requestTask?.cancel()
			requestTask = nil
			refreshTask?.cancel()
			refreshTask = nil
			needsRefresh = false
		case .read(
			let threadID,
			let requestID
		):
			requestTask = Task
			{
				[weak self] in
				guard let self
				else
				{
					return
				}
				do
				{
					let detail = try await self.service.readThread(id: threadID)
					try Task.checkCancellation()
					try self.validate(
						detail,
						threadID: threadID
					)
					guard self.state.requestID == requestID
					else
					{
						return
					}
					self.requestTask = nil
					self.send(.loaded(
						requestID: requestID,
						detail: detail
					))
					self.scheduleRefresh()
				}
				catch
				{
					self.fail(
						error,
						requestID: requestID,
						cursor: nil
					)
				}
			}
		case .earlier(
			let threadID,
			let cursor,
			let requestID
		):
			requestTask = Task
			{
				[weak self] in
				guard let self
				else
				{
					return
				}
				do
				{
					let page = try await self.service.loadEarlierTurns(
						threadId: threadID,
						cursor: cursor
					)
					try Task.checkCancellation()
					guard self.state.requestID == requestID
					else
					{
						return
					}
					self.requestTask = nil
					self.send(.earlierLoaded(
						requestID: requestID,
						turns: page.turns,
						nextCursor: page.nextCursor
					))
					self.scheduleRefresh()
				}
				catch
				{
					self.fail(
						error,
						requestID: requestID,
						cursor: cursor
					)
				}
			}
		}
	}

	private func validate(
		_ detail: ThreadDetail,
		threadID: String
	) throws
	{
		guard detail.summary.id == threadID
		else
		{
			throw AppServerError.protocolError("History returned another conversation.")
		}
		if let projectPath
		{
			try CheckoutIdentity.validate(
				cwd: detail.summary.cwd,
				expectedDirectory: URL(fileURLWithPath: projectPath)
			)
		}
	}

	private func fail(
		_ error: Error,
		requestID: Int,
		cursor: String?
	)
	{
		guard !Task.isCancelled, state.requestID == requestID
		else
		{
			return
		}
		requestTask = nil
		send(.failed(
			requestID: requestID,
			message: error.localizedDescription,
			paginationCursor: cursor
		))
		scheduleRefresh()
	}

	private func scheduleRefresh()
	{
		guard needsRefresh, requestTask == nil, refreshTask == nil,
				state.selectedThreadID != nil, !isInvalidated
		else
		{
			return
		}
		refreshTask = Task
		{
			[weak self] in
			do
			{
				try await Task.sleep(for: .milliseconds(100))
			}
			catch
			{
				return
			}
			guard let self, !Task.isCancelled, !self.isInvalidated
			else
			{
				return
			}
			self.refreshTask = nil
			guard self.needsRefresh, self.requestTask == nil
			else
			{
				return
			}
			self.needsRefresh = false
			self.send(.refresh(requestID: self.requestID()))
		}
	}
}
