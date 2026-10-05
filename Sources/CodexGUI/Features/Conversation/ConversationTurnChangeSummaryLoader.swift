import Foundation

/// Reads the captured turn baseline while work is running, including edits made by commands.
@MainActor
final class ConversationTurnChangeSummaryLoader
{
	private struct Key: Equatable
	{
		let owner: FeaturePresentationOwner
		let root: String
		let turnID: String
	}

	private let service: any GitTurnBaselineService
	private var key: Key?
	private var pollTask: Task<Void, Never>?
	private var readTask: Task<Void, Never>?
	private var fallback: ConversationTurnChangeSummary?
	private var comparison: ConversationTurnChangeSummary?
	private var published: ConversationTurnChangeSummary?
	var onChange: ((ConversationTurnChangeSummary?) -> Void)?

	init(service: any GitTurnBaselineService = LocalGitTurnBaselineService.shared)
	{
		self.service = service
	}

	deinit
	{
		pollTask?.cancel()
		readTask?.cancel()
	}

	func render(_ composer: ConversationPresentation.Composer)
	{
		fallback = composer.turnChangeSummary
		let nextKey: Key?
		if composer.activeExecutionState?.isBusy == true,
			let activeThreadID = composer.activeThreadID,
			activeThreadID == composer.selectedThreadID,
			let turnID = composer.activeTurnID,
			let root = composer.owner.runtimeOwner?.workspace.canonicalCheckoutPath
		{
			nextKey = Key(
				owner: composer.owner,
				root: root,
				turnID: turnID
			)
		}
		else
		{
			nextKey = nil
		}
		if key != nextKey
		{
			stop()
			key = nextKey
			comparison = nil
			if nextKey != nil
			{
				refresh()
				pollTask = Task
				{
					[weak self] in
					while !Task.isCancelled
					{
						try? await Task.sleep(for: .seconds(3))
						guard !Task.isCancelled
						else
						{
							return
						}
						self?.refresh()
					}
				}
			}
		}
		publish()
	}

	func stop()
	{
		readTask?.cancel()
		readTask = nil
		pollTask?.cancel()
		pollTask = nil
		key = nil
	}

	private func refresh()
	{
		guard let key, readTask == nil
		else
		{
			return
		}
		let request = GitComparisonRequest(
			owner: key.owner,
			repositoryRoot: key.root,
			scope: .lastTurn,
			generation: 0,
			lastTurnID: key.turnID
		)
		let service = self.service
		readTask = Task
		{
			[weak self] in
			let result = await service.compare(request)
			guard !Task.isCancelled
			else
			{
				return
			}
			self?.receive(
				result,
				for: key
			)
		}
	}

	private func receive(
		_ result: GitComparisonResult,
		for requestKey: Key
	)
	{
		guard key == requestKey
		else
		{
			return
		}
		readTask = nil
		switch result
		{
		case .snapshot(let snapshot):
			comparison = ConversationTurnChangeSummary(comparison: snapshot)
		case .unavailable:
			comparison = nil
		}
		publish()
	}

	private func publish()
	{
		let value = comparison ?? fallback
		guard published != value
		else
		{
			return
		}
		published = value
		onChange?(value)
	}
}
