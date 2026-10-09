import Foundation

/// Rebuilds totals only when this task's attributed turn reports change.
@MainActor
final class ConversationTurnChangeSummaryLoader
{
	private let service: any GitComparisonService
	private var request: GitComparisonRequest?
	private var readTask: Task<Void, Never>?
	private var published: ConversationTurnChangeSummary?
	var onChange: ((ConversationTurnChangeSummary?) -> Void)?

	init(service: any GitComparisonService = LocalGitComparisonService())
	{
		self.service = service
	}

	deinit
	{
		readTask?.cancel()
	}

	func render(_ composer: ConversationPresentation.Composer)
	{
		let nextRequest = composer.turnChangeRequest
		guard request != nextRequest
		else
		{
			return
		}
		stop()
		request = nextRequest
		guard let nextRequest
		else
		{
			publish(nil)
			return
		}
		// Never leave another task's totals visible while awaiting this task's result.
		publish(nextRequest.reportedChanges == nil
			? ConversationTurnChangeSummary(unavailable: .lastTurnUnavailable) : .loading)
		let usesPreviousTurn = nextRequest.lastTurnID != composer.activeTurnID
		let service = self.service
		readTask = Task
		{
			[weak self] in
			let result = await service.compare(nextRequest)
			let summary = await Task.detached(priority: .userInitiated)
			{
				ConversationTurnChangeSummary(
					result: result,
					usesPreviousTurn: usesPreviousTurn,
					request: nextRequest
				)
			}.value
			guard !Task.isCancelled, self?.request == nextRequest
			else
			{
				return
			}
			self?.readTask = nil
			self?.publish(summary)
		}
	}

	func stop()
	{
		readTask?.cancel()
		readTask = nil
		request = nil
		publish(nil)
	}

	private func publish(_ value: ConversationTurnChangeSummary?)
	{
		guard published != value
		else
		{
			return
		}
		published = value
		onChange?(value)
	}
}
