import Foundation

/// Reuses a watched checkout's completed index while keeping enumeration results owner scoped.
@MainActor
final class ProjectFileIndexRuntime
{
	private let service: any ProjectFileIndexService
	private let monitor: any ProjectFileIndexMonitoring
	private let waitForFileChanges: @MainActor () async -> Void
	private var owner: FeaturePresentationOwner?
	private var requestGeneration = 0
	private var observationGeneration = 0
	private var observation: (any ProjectFileIndexObservation)?
	private var job: Task<Void, Never>?
	private var isShutDown = false
	private(set) var index: ProjectFileIndex?
	var onChange: (() -> Void)?

	init(
		service: any ProjectFileIndexService = FileSystemProjectFileIndexService(),
		monitor: any ProjectFileIndexMonitoring = FileSystemProjectFileIndexMonitor(),
		waitForFileChanges: @escaping @MainActor () async -> Void =
		{
			try? await Task.sleep(for: .milliseconds(150))
		}
	)
	{
		self.service = service
		self.monitor = monitor
		self.waitForFileChanges = waitForFileChanges
	}

	deinit
	{
		job?.cancel()
		observation?.cancel()
	}

	func select(_ owner: FeaturePresentationOwner)
	{
		guard !isShutDown, self.owner != owner
		else
		{
			return
		}
		let sameCheckout = self.owner?.projectIdentity == owner.projectIdentity
		cancelRequest()
		self.owner = owner
		let shouldReplaceObservation = !sameCheckout || observation?.isCurrent != true
		if shouldReplaceObservation
		{
			index = nil
			replaceObservation(for: owner)
		}
		let requiresFreshEnumeration = observation == nil
			|| index?.isReusableWithProjectObservation == false
		if requiresFreshEnumeration
		{
			// Owner changes revalidate dependencies that the checkout watcher cannot observe.
			index = nil
		}
		guard !isShutDown, self.owner == owner
		else
		{
			return
		}
		if index == nil, job == nil
		{
			startRequest(
				owner: owner,
				debounce: false
			)
		}
		onChange?()
	}

	private func replaceObservation(for owner: FeaturePresentationOwner)
	{
		observation?.cancel()
		observation = nil
		observationGeneration += 1
		guard let projectPath = owner.projectPath
		else
		{
			return
		}
		let generation = observationGeneration
		let startedObservation = monitor.watch(projectPath: projectPath)
		{
			[weak self] in
			self?.projectFilesChanged(
				projectIdentity: owner.projectIdentity,
				generation: generation
			)
		}
		guard !isShutDown, observationGeneration == generation,
				self.owner?.projectIdentity == owner.projectIdentity
		else
		{
			startedObservation?.cancel()
			return
		}
		observation = startedObservation
	}

	private func projectFilesChanged(
		projectIdentity: String,
		generation: Int
	)
	{
		guard !isShutDown, observationGeneration == generation,
				let owner, owner.projectIdentity == projectIdentity
		else
		{
			return
		}
		cancelRequest()
		index = nil
		let pendingRequestGeneration = requestGeneration
		if let observation, !observation.isCurrent
		{
			replaceObservation(for: owner)
		}
		guard !isShutDown, self.owner == owner,
				requestGeneration == pendingRequestGeneration
		else
		{
			return
		}
		startRequest(
			owner: owner,
			debounce: true
		)
		onChange?()
	}

	private func cancelRequest()
	{
		job?.cancel()
		job = nil
		requestGeneration += 1
	}

	private func startRequest(
		owner: FeaturePresentationOwner,
		debounce: Bool
	)
	{
		guard let projectPath = owner.projectPath
		else
		{
			return
		}
		let generation = requestGeneration
		let service = service
		let waitForFileChanges = waitForFileChanges
		job = Task
		{
			[weak self] in
			if debounce
			{
				await waitForFileChanges()
			}
			guard !Task.isCancelled,
					self?.requestGeneration == generation, self?.owner == owner
			else
			{
				return
			}
			let loadedIndex = await service.load(projectPath: projectPath)
			guard let self, !Task.isCancelled,
					self.requestGeneration == generation, self.owner == owner
			else
			{
				return
			}
			self.job = nil
			guard let loadedIndex
			else
			{
				return
			}
			if let observation = self.observation, !observation.isCurrent
			{
				self.projectFilesChanged(
					projectIdentity: owner.projectIdentity,
					generation: self.observationGeneration
				)
				return
			}
			self.index = loadedIndex
			self.onChange?()
		}
	}

	func shutdown()
	{
		guard !isShutDown
		else
		{
			return
		}
		isShutDown = true
		cancelRequest()
		observation?.cancel()
		observation = nil
		observationGeneration += 1
		owner = nil
		index = nil
		onChange = nil
	}
}
