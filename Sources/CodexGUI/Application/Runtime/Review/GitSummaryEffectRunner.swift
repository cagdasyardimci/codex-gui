import Foundation

@MainActor
final class GitSummaryEffectRunner
{
	private let service: any GitComparisonService
	private var job: Task<Void, Never>?
	var readTask: Task<Void, Never>?
	{
		job
	}

	init(service: any GitComparisonService)
	{
		self.service = service
	}

	deinit
	{
		job?.cancel()
	}

	func run(
		_ effect: GitSummaryEffect,
		onResult: @escaping @MainActor (
			GitComparisonResult,
			GitComparisonRequest
		) -> Void
	)
	{
		switch effect
		{
		case .cancelRead:
			job?.cancel()
			job = nil
		case .read(let request):
			let service = service
			job = Task
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
		}
	}
}
