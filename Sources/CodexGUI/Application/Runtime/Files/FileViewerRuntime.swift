import Foundation

enum FileViewerCloseChoice: Equatable
{
	case save
	case discard
	case cancel
}

enum FileViewerCloseResult: Equatable
{
	case closed
	case decisionRequired(FileViewerFailure?)
	case cancelled
}

@MainActor
final class FileViewerRuntime
{
	private(set) var state = FileViewerState()
	var onChange: ((FileViewerState) -> Void)?
	private let service: any FileViewerService
	private let autosaveDelay: Duration
	private var readTasks: [UUID: Task<Void, Never>] = [:]
	private var saveTasks: [UUID: Task<Void, Never>] = [:]
	private var autosaveTasks: [UUID: Task<Void, Never>] = [:]
	private var directoryTasks: [FileLocation: Task<Void, Never>] = [:]
	private var searchTask: Task<Void, Never>?
	private var retiredTasks: [UUID: Task<Void, Never>] = [:]
	var scheduledAutosaveCount: Int
	{
		autosaveTasks.count
	}

	func currentSearchTask() -> Task<Void, Never>?
	{
		searchTask
	}

	func readTask(for id: UUID) -> Task<Void, Never>?
	{
		readTasks[id]
	}

	init(
		service: any FileViewerService = FileSystemFileViewerService(),
		autosaveDelay: Duration = .milliseconds(500)
	)
	{
		self.service = service
		self.autosaveDelay = autosaveDelay
	}

	func switchRoot(_ root: String?)
	{
		dispatch(.switchRoot(root))
		for task in directoryTasks.values
		{
			cancelAndRetire(task)
		}
		directoryTasks.removeAll()
		cancelAndRetire(searchTask)
		searchTask = nil
	}

	func clearRoot()
	{
		switchRoot(nil)
	}

	func open(
		_ location: FileLocation,
		retained: Bool = false,
		line: Int? = nil
	)
	{
		dispatch(.open(
			UUID(),
			location,
			retained: retained,
			line: line
		))
	}

	func select(_ id: UUID)
	{
		dispatch(.select(id))
	}
	func retain(_ id: UUID)
	{
		dispatch(.retain(id))
	}
	func acknowledgeLineRequest(
		_ id: UUID,
		generation: Int
	)
	{
		dispatch(.acknowledgeLine(
			id,
			generation
		))
	}
	func refresh(_ id: UUID)
	{
		dispatch(.refresh(id))
	}

	func refreshSelectedIfClean()
	{
		guard let selected = state.selectedDocument,
				!selected.isDirty,
				selected.status != .loading
		else
		{
			return
		}
		dispatch(.refresh(selected.id))
	}

	func edit(
		_ id: UUID,
		text: String
	)
	{
		dispatch(.edit(
			id,
			text
		))
		guard let document = state.documents.first(where:
			{
				$0.id == id
			}), document.isDirty
		else
		{
			return
		}
		cancelAndRetire(autosaveTasks.removeValue(forKey: id))
		let delay = autosaveDelay
		autosaveTasks[id] = Task
		{
			[weak self] in
			try? await Task.sleep(for: delay)
			if !Task.isCancelled, let self
			{
				self.retire(self.autosaveTasks.removeValue(forKey: id))
				_ = await self.save(id)
			}
		}
	}

	@discardableResult
	func save(_ id: UUID) async -> FileViewerFailure?
	{
		cancelAndRetire(autosaveTasks.removeValue(forKey: id))
		if let current = saveTasks[id]
		{
			await current.value
			return saveFailure(for: id)
		}
		let task = Task
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			await self.performSaveLoop(id)
		}
		saveTasks[id] = task
		await task.value
		saveTasks[id] = nil
		return saveFailure(for: id)
	}

	private func performSaveLoop(_ id: UUID) async
	{
		while let document = state.documents.first(where:
			{
				$0.id == id
			}),
			document.isDirty,
			document.status != .conflict,
			let text = document.currentText,
			let expected = document.diskRevision
		{
			let generation = document.saveGeneration + 1
			dispatch(.saveStarted(
				id,
				generation
			))
			let result: Result<FileDiskRevision, FileViewerFailure>
			do
			{
				result = .success(try await service.save(
					at: document.location,
					text: text,
					expectedRevision: expected
				))
			}
			catch
			{
				result = .failure(Self.failure(error))
			}
			dispatch(.saveFinished(
				id,
				generation,
				document.editRevision,
				result
			))
			if case .failure = result
			{
				break
			}
		}
	}

	private func saveFailure(for id: UUID) -> FileViewerFailure?
	{
		guard let document = state.documents.first(where:
			{
				$0.id == id
			})
		else
		{
			return nil
		}
		if document.status == .conflict
		{
			return .conflict
		}
		if case .failed(let error) = document.status
		{
			return error
		}
		return nil
	}

	func flushAll() async -> [UUID: FileViewerFailure]
	{
		var failures: [UUID: FileViewerFailure] = [:]
		for id in state.documents.map(\.id)
		{
			if let error = await save(id)
			{
				failures[id] = error
			}
		}
		return failures
	}

	func close(
		_ id: UUID,
		choice: FileViewerCloseChoice
	) async -> FileViewerCloseResult
	{
		guard state.documents.contains(where:
			{
				$0.id == id
			})
		else
		{
			return .closed
		}
		if choice == .cancel
		{
			return .cancelled
		}
		cancelAndRetire(autosaveTasks.removeValue(forKey: id))
		if let task = saveTasks[id]
		{
			await task.value
		}
		guard let document = state.documents.first(where:
			{
				$0.id == id
			})
		else
		{
			return .closed
		}
		if document.isDirty, choice == .save
		{
			if let error = await save(id)
			{
				return .decisionRequired(error)
			}
		}
		if document.isDirty, choice != .discard,
			state.documents.first(where:
			{
				$0.id == id
			})?.isDirty == true
		{
			return .decisionRequired(nil)
		}
		dispatch(.remove(id))
		return .closed
	}

	func useDisk(_ id: UUID) async
	{
		if let task = saveTasks[id]
		{
			await task.value
		}
		dispatch(.useDisk(id))
	}

	/// Explicit overwrite choice adopts only the current external revision.
	func keepLocal(_ id: UUID) async -> FileViewerFailure?
	{
		let error = await continueEditing(id)
		if error != nil
		{
			return error
		}
		return await save(id)
	}

	/// Keep the local buffer and adopt the current disk revision for a later explicit save.
	func continueEditing(_ id: UUID) async -> FileViewerFailure?
	{
		guard let document = state.documents.first(where:
			{
				$0.id == id
			}),
			document.status == .conflict
		else
		{
			return nil
		}
		do
		{
			let current = try await service.read(at: document.location)
			guard state.documents.first(where:
				{
					$0.id == id
				})?.status == .conflict
			else
			{
				return .cancelled
			}
			dispatch(.keepLocal(
				id,
				current.revision
			))
			return nil
		}
		catch
		{
			return Self.failure(error)
		}
	}

	/// Settle accepted writes before a window or application releases this runtime.
	func shutdown() async -> [UUID: FileViewerFailure]
	{
		let pendingAutosaves = Array(autosaveTasks.values)
		for task in pendingAutosaves
		{
			task.cancel()
		}
		autosaveTasks.removeAll()
		for task in pendingAutosaves
		{
			await task.value
		}
		let failures = await flushAll()
		let pendingReads = Array(readTasks.values)
		let pendingDirectories = Array(directoryTasks.values)
		let pendingSearch = searchTask
		let retired = Array(retiredTasks.values)
		for task in pendingReads + pendingDirectories + retired
		{
			task.cancel()
		}
		pendingSearch?.cancel()
		readTasks.removeAll()
		directoryTasks.removeAll()
		searchTask = nil
		for task in pendingReads + pendingDirectories + retired
		{
			await task.value
		}
		await pendingSearch?.value
		retiredTasks.removeAll()
		return failures
	}

	func listDirectory(_ location: FileLocation)
	{
		guard location.root == state.activeRoot
		else
		{
			return
		}
		cancelAndRetire(directoryTasks[location])
		let request = UUID()
		dispatch(.directoryStarted(
			location,
			request
		))
		let service = self.service
		directoryTasks[location] = Task
		{
			[weak self] in
			let result: Result<[FileViewerDirectoryEntry], FileViewerFailure>
			do
			{
				result = .success(try await service.listDirectory(at: location))
			}
			catch
			{
				result = .failure(Self.failure(error))
			}
			guard !Task.isCancelled
			else
			{
				return
			}
			self?.dispatch(.directoryFinished(
				location,
				request,
				result
			))
		}
	}

	func filenameSearch(
		query: String,
		limit: Int = 100
	)
	{
		guard let root = state.activeRoot
		else
		{
			return
		}
		cancelAndRetire(searchTask)
		let request = UUID()
		dispatch(.searchStarted(request))
		let service = self.service
		searchTask = Task
		{
			[weak self] in
			let result: Result<FileViewerSearchPage<FileLocation>, FileViewerFailure>
			do
			{
				result = .success(try await service.filenameSearch(
					root: root,
					query: query,
					limit: limit
				))
			}
			catch
			{
				result = .failure(Self.failure(error))
			}
			guard !Task.isCancelled
			else
			{
				return
			}
			self?.dispatch(.filenameSearchFinished(
				request,
				result
			))
		}
	}

	func contentSearch(
		query: String,
		mask: String? = nil,
		limit: Int = 100
	)
	{
		guard let root = state.activeRoot
		else
		{
			return
		}
		cancelAndRetire(searchTask)
		let request = UUID()
		dispatch(.searchStarted(request))
		let service = self.service
		searchTask = Task
		{
			[weak self] in
			let result: Result<FileViewerSearchPage<FileViewerSearchResult>, FileViewerFailure>
			do
			{
				result = .success(try await service.contentSearch(
					root: root,
					query: query,
					mask: mask,
					limit: limit
				))
			}
			catch
			{
				result = .failure(Self.failure(error))
			}
			guard !Task.isCancelled
			else
			{
				return
			}
			self?.dispatch(.contentSearchFinished(
				request,
				result
			))
		}
	}

	func cancelSearch()
	{
		cancelAndRetire(searchTask)
		searchTask = nil
		dispatch(.cancelSearch)
	}

	private func dispatch(_ action: FileViewerAction)
	{
		let transition = FileViewerReducer.reduce(
			state: &state,
			action: action
		)
		for effect in transition.effects
		{
			switch effect
			{
			case .cancelRead(let id):
				cancelAndRetire(readTasks[id])
				readTasks[id] = nil
			case let .read(
				id,
				location,
				generation
			):
				let service = self.service
				readTasks[id] = Task
				{
					[weak self] in
					let result: Result<FileViewerRead, FileViewerFailure>
					do
					{
						result = .success(try await service.read(at: location))
					}
					catch
					{
						result = .failure(Self.failure(error))
					}
					guard !Task.isCancelled
					else
					{
						return
					}
					self?.dispatch(.load(
						id,
						generation,
						result
					))
				}
			}
		}
		if transition.changed
		{
			onChange?(state)
		}
	}

	private func cancelAndRetire(_ task: Task<Void, Never>?)
	{
		guard let task
		else
		{
			return
		}
		task.cancel()
		retire(task)
	}

	private func retire(_ task: Task<Void, Never>?)
	{
		guard let task
		else
		{
			return
		}
		let id = UUID()
		retiredTasks[id] = task
		Task
		{
			[weak self] in
			await task.value
			self?.retiredTasks[id] = nil
		}
	}

	private static func failure(_ error: Error) -> FileViewerFailure
	{
		if let failure = error as? FileViewerFailure
		{
			return failure
		}
		if error is CancellationError
		{
			return .cancelled
		}
		return .io(error.localizedDescription)
	}
}
