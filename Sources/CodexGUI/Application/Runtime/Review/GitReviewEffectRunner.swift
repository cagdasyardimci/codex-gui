import Foundation

/// Owns review jobs and timers; their captured requests return through typed actions.
@MainActor
final class GitReviewEffectRunner
{
	private let service: any GitComparisonService
	private var readJob: Task<Void, Never>?
	private var pollJob: Task<Void, Never>?

	init(service: any GitComparisonService)
	{
		self.service = service
	}

	deinit
	{
		readJob?.cancel()
		pollJob?.cancel()
	}

	func run(
		_ effect: GitReviewEffect,
		onResult: @escaping @MainActor (
			GitComparisonResult,
			GitComparisonRequest
		) -> Void,
		onPoll: @escaping @MainActor (FeaturePresentationOwner) -> Void
	)
	{
		switch effect
		{
		case .cancelRead:
			readJob?.cancel()
			readJob = nil
		case .read(let request):
			let service = service
			readJob = Task
			{
				guard !Task.isCancelled
				else
				{
					return
				}
				let result = await service.compare(request)
				guard !Task.isCancelled
				else
				{
					return
				}
				onResult(
					result,
					request
				)
			}
		case .stopPolling:
			pollJob?.cancel()
			pollJob = nil
		case .startPolling(let owner):
			pollJob = Task
			{
				while !Task.isCancelled
				{
					do
					{
						try await Task.sleep(for: .seconds(5))
					}
					catch
					{
						return
					}
					onPoll(owner)
				}
			}
		}
	}
}
