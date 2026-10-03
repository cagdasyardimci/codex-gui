import Foundation

/// Owns project-file enumeration for the currently displayed conversation owner.
@MainActor
final class ProjectFileIndexRuntime
{
	private let service: any ProjectFileIndexService
	private var owner: FeaturePresentationOwner?
	private var requestGeneration = 0
	private var job: Task<Void, Never>?
	private var isShutDown = false
	private(set) var index: ProjectFileIndex?
	var onChange: (() -> Void)?

	init(service: any ProjectFileIndexService = FileSystemProjectFileIndexService())
	{
		self.service = service
	}

	deinit
	{
		job?.cancel()
	}

	func select(_ owner: FeaturePresentationOwner)
	{
		guard !isShutDown, self.owner != owner
		else
		{
			return
		}
		job?.cancel()
		job = nil
		requestGeneration += 1
		self.owner = owner
		index = nil
		if let projectPath = owner.projectPath
		{
			let generation = requestGeneration
			let service = service
			job = Task
			{
				[weak self] in
				guard !Task.isCancelled
				else
				{
					return
				}
				let loadedIndex = await service.load(projectPath: projectPath)
				guard let self, !Task.isCancelled, let loadedIndex,
						self.requestGeneration == generation, self.owner == owner
				else
				{
					return
				}
				self.job = nil
				self.index = loadedIndex
				self.onChange?()
			}
		}
		onChange?()
	}

	func shutdown()
	{
		guard !isShutDown
		else
		{
			return
		}
		isShutDown = true
		job?.cancel()
		job = nil
		requestGeneration += 1
		owner = nil
		index = nil
		onChange = nil
	}
}
