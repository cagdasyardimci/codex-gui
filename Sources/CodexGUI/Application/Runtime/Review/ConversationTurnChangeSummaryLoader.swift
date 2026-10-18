import Foundation

/// Rebuilds totals only when this task's attributed turn reports change.
@MainActor
final class ConversationTurnChangeSummaryLoader
{
	private let service: any GitComparisonService
	private var request: GitComparisonRequest?
	private var activeTurnID: String?
	private(set) var readTask: Task<Void, Never>?
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

	func render(
		request nextRequest: GitComparisonRequest?,
		activeTurnID: String?
	)
	{
		guard request != nextRequest || self.activeTurnID != activeTurnID
		else
		{
			return
		}
		stop()
		request = nextRequest
		self.activeTurnID = activeTurnID
		guard let nextRequest
		else
		{
			publish(nil)
			return
		}
		// Never leave another task's totals visible while awaiting this task's result.
		publish(nextRequest.reportedChanges == nil
			? ConversationTurnChangeSummary(unavailable: .lastTurnUnavailable) : .loading)
		let usesPreviousTurn = nextRequest.lastTurnID != activeTurnID
		let service = self.service
		readTask = Task
		{
			[weak self] in
			let result = await service.compare(nextRequest)
			guard !Task.isCancelled
			else
			{
				return
			}
			let summary = await Task.detached(priority: .userInitiated)
			{
				ConversationTurnChangeSummary(
					result: result,
					usesPreviousTurn: usesPreviousTurn,
					request: nextRequest
				)
			}.value
			guard !Task.isCancelled, self?.request == nextRequest,
					self?.activeTurnID == activeTurnID
			else
			{
				return
			}
			self?.readTask = nil
			self?.publish(summary)
		}
	}

	/// Waits for this request's publication, without guessing its worker scheduling delay.
	func waitForLoading() async
	{
		await readTask?.value
	}

	func stop()
	{
		readTask?.cancel()
		readTask = nil
		request = nil
		activeTurnID = nil
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
