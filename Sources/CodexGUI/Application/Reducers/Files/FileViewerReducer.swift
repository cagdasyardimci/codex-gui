import Foundation

enum FileViewerAction
{
	case switchRoot(String?)
	case open(
		UUID,
		FileLocation,
		retained: Bool,
		line: Int?
	)
	case select(UUID)
	case retain(UUID)
	case acknowledgeLine(
		UUID,
		Int
	)
	case edit(
		UUID,
		String
	)
	case load(
		UUID,
		Int,
		Result<FileViewerRead, FileViewerFailure>
	)
	case saveStarted(
		UUID,
		Int
	)
	case saveFinished(
		UUID,
		Int,
		Int,
		Result<FileDiskRevision, FileViewerFailure>
	)
	case refresh(UUID)
	case useDisk(UUID)
	case keepLocal(
		UUID,
		FileDiskRevision
	)
	case directoryStarted(
		FileLocation,
		UUID
	)
	case directoryFinished(
		FileLocation,
		UUID,
		Result<[FileViewerDirectoryEntry], FileViewerFailure>
	)
	case searchStarted(UUID)
	case cancelSearch
	case filenameSearchFinished(
		UUID,
		Result<FileViewerSearchPage<FileLocation>, FileViewerFailure>
	)
	case contentSearchFinished(
		UUID,
		Result<FileViewerSearchPage<FileViewerSearchResult>, FileViewerFailure>
	)
	case remove(UUID)
}

enum FileViewerEffect
{
	case read(
		UUID,
		FileLocation,
		Int
	)
	case cancelRead(UUID)
}

struct FileViewerTransition
{
	var effects: [FileViewerEffect] = []
	var changed = false
}

enum FileViewerReducer
{
	static func reduce(
		state: inout FileViewerState,
		action: FileViewerAction
	) -> FileViewerTransition
	{
		switch action
		{
		case .switchRoot(let root):
			state.activeRoot = root.map
			{
				FileLocation(
					root: $0,
					relativePath: ""
				).root
			}
			state.generation += 1
			state.directoryEntries = [:]
			state.directoryFailures = [:]
			state.directoryRequests = [:]
			state.filenameResults = nil
			state.contentResults = nil
			state.searchFailure = nil
			state.searchRequest = nil
			return FileViewerTransition(changed: true)
		case let .open(
			id,
			location,
			retained,
			line
		):
			guard location.root == state.activeRoot
			else
			{
				return FileViewerTransition()
			}
			if let index = state.documents.firstIndex(where:
				{
					$0.location == location
				})
			{
				state.selectedDocumentID = state.documents[index].id
				state.documents[index].isRetained = state.documents[index].isRetained || retained
				if let line
				{
					state.documents[index].requestedLine = line
					state.documents[index].lineRequestGeneration += 1
				}
				if state.documents[index].isRetained,
					state.previewDocumentID == state.documents[index].id
				{
					state.previewDocumentID = nil
				}
				if !state.documents[index].isDirty,
					state.documents[index].status != .loading
				{
					return beginRefresh(
						state: &state,
						index: index
					)
				}
				return FileViewerTransition(changed: true)
			}
			var effects: [FileViewerEffect] = []
			if !retained, let preview = state.previewDocumentID,
				let index = state.documents.firstIndex(where:
				{
					$0.id == preview
				}),
				!state.documents[index].isDirty,
				state.documents[index].status != .conflict,
				!state.documents[index].isSaving
			{
				state.documents.remove(at: index)
				effects.append(.cancelRead(preview))
			}
			let document = FileViewerDocument(
				id: id,
				location: location,
				isRetained: retained,
				requestedLine: line,
				lineRequestGeneration: line == nil ? 0 : 1
			)
			state.documents.append(document)
			state.selectedDocumentID = document.id
			state.previewDocumentID = retained ? nil : document.id
			effects.append(.read(
				document.id,
				location,
				document.loadGeneration
			))
			return FileViewerTransition(
				effects: effects,
				changed: true
			)
		case .select(let id):
			guard let index = state.documents.firstIndex(where:
				{
					$0.id == id
				})
			else
			{
				return FileViewerTransition()
			}
			state.selectedDocumentID = id
			if !state.documents[index].isDirty,
				state.documents[index].status != .loading
			{
				return beginRefresh(
					state: &state,
					index: index
				)
			}
			return FileViewerTransition(changed: true)
		case .retain(let id):
			guard let index = state.documents.firstIndex(where:
				{
					$0.id == id
				})
			else
			{
				return FileViewerTransition()
			}
			state.documents[index].isRetained = true
			if state.previewDocumentID == id
			{
				state.previewDocumentID = nil
			}
			return FileViewerTransition(changed: true)
		case let .acknowledgeLine(
			id,
			generation
		):
			guard let index = state.documents.firstIndex(where:
				{
					$0.id == id
				}),
				state.documents[index].lineRequestGeneration == generation,
				state.documents[index].requestedLine != nil
			else
			{
				return FileViewerTransition()
			}
			state.documents[index].requestedLine = nil
			return FileViewerTransition(changed: true)
		case let .edit(
			id,
			text
		):
			guard let index = state.documents.firstIndex(where:
				{
					$0.id == id
				}),
				state.documents[index].canEdit
			else
			{
				return FileViewerTransition()
			}
			state.documents[index].content = text.isEmpty ? .empty : .text(text)
			state.documents[index].editRevision += 1
			state.documents[index].isRetained = true
			if state.previewDocumentID == id
			{
				state.previewDocumentID = nil
			}
			return FileViewerTransition(changed: true)
		case let .load(
			id,
			generation,
			result
		):
			guard let index = state.documents.firstIndex(where:
				{
					$0.id == id
				}),
				state.documents[index].loadGeneration == generation
			else
			{
				return FileViewerTransition()
			}
			if state.documents[index].isDirty
			{
				let previous = state.documents[index].diskRevision
				switch result
				{
				case .success(let read) where read.revision == previous:
					return FileViewerTransition()
				case .success, .failure:
					state.documents[index].status = .conflict
					return FileViewerTransition(changed: true)
				}
			}
			switch result
			{
			case .success(let read):
				state.documents[index].content = read.content
				state.documents[index].diskRevision = read.revision
				state.documents[index].isReadOnly = read.isReadOnly
				state.documents[index].status = .ready
			case .failure(let error):
				state.documents[index].status = .failed(error)
			}
			return FileViewerTransition(changed: true)
		case let .saveStarted(
			id,
			generation
		):
			guard let index = state.documents.firstIndex(where:
				{
					$0.id == id
				}),
				state.documents[index].saveGeneration + 1 == generation
			else
			{
				return FileViewerTransition()
			}
			state.documents[index].saveGeneration = generation
			state.documents[index].isSaving = true
			return FileViewerTransition(changed: true)
		case let .saveFinished(
			id,
			generation,
			editRevision,
			result
		):
			guard let index = state.documents.firstIndex(where:
				{
					$0.id == id
				}),
				state.documents[index].saveGeneration == generation
			else
			{
				return FileViewerTransition()
			}
			state.documents[index].isSaving = false
			switch result
			{
			case .success(let diskRevision):
				state.documents[index].diskRevision = diskRevision
				state.documents[index].savedEditRevision = editRevision
				state.documents[index].status = .ready
			case .failure(.conflict):
				state.documents[index].status = .conflict
			case .failure(let error):
				state.documents[index].status = .failed(error)
			}
			return FileViewerTransition(changed: true)
		case .refresh(let id):
			guard let index = state.documents.firstIndex(where:
				{
					$0.id == id
				}),
				!state.documents[index].isSaving
			else
			{
				return FileViewerTransition()
			}
			return beginRefresh(
				state: &state,
				index: index
			)
		case .useDisk(let id):
			guard let index = state.documents.firstIndex(where:
				{
					$0.id == id
				}),
				!state.documents[index].isSaving
			else
			{
				return FileViewerTransition()
			}
			state.documents[index].editRevision = 0
			state.documents[index].savedEditRevision = 0
			state.documents[index].loadGeneration += 1
			state.documents[index].status = .loading
			return FileViewerTransition(
				effects: [.cancelRead(id), .read(
					id,
					state.documents[index].location,
					state.documents[index].loadGeneration
				)],
				changed: true
			)
		case let .keepLocal(
			id,
			revision
		):
			guard let index = state.documents.firstIndex(where:
				{
					$0.id == id
				}),
				state.documents[index].status == .conflict
			else
			{
				return FileViewerTransition()
			}
			state.documents[index].diskRevision = revision
			state.documents[index].status = .ready
			return FileViewerTransition(changed: true)
		case let .directoryStarted(
			location,
			request
		):
			guard location.root == state.activeRoot
			else
			{
				return FileViewerTransition()
			}
			state.directoryRequests[location] = request
			state.directoryFailures[location] = nil
			return FileViewerTransition(changed: true)
		case let .directoryFinished(
			location,
			request,
			result
		):
			guard state.directoryRequests[location] == request,
					location.root == state.activeRoot
			else
			{
				return FileViewerTransition()
			}
			state.directoryRequests[location] = nil
			switch result
			{
			case .success(let entries):
				state.directoryEntries[location] = entries
				state.directoryFailures[location] = nil
			case .failure(let error):
				state.directoryFailures[location] = error
			}
			return FileViewerTransition(changed: true)
		case .searchStarted(let request):
			state.searchRequest = request
			state.searchFailure = nil
			state.filenameResults = nil
			state.contentResults = nil
			return FileViewerTransition(changed: true)
		case .cancelSearch:
			guard state.searchRequest != nil || state.searchFailure != nil
				|| state.filenameResults != nil || state.contentResults != nil
			else
			{
				return FileViewerTransition()
			}
			state.searchRequest = nil
			state.searchFailure = nil
			state.filenameResults = nil
			state.contentResults = nil
			return FileViewerTransition(changed: true)
		case let .filenameSearchFinished(
			request,
			result
		):
			guard state.searchRequest == request
			else
			{
				return FileViewerTransition()
			}
			state.searchRequest = nil
			switch result
			{
			case .success(let page): state.filenameResults = page
			case .failure(let error): state.searchFailure = error
			}
			return FileViewerTransition(changed: true)
		case let .contentSearchFinished(
			request,
			result
		):
			guard state.searchRequest == request
			else
			{
				return FileViewerTransition()
			}
			state.searchRequest = nil
			switch result
			{
			case .success(let page): state.contentResults = page
			case .failure(let error): state.searchFailure = error
			}
			return FileViewerTransition(changed: true)
		case .remove(let id):
			guard let index = state.documents.firstIndex(where:
				{
					$0.id == id
				})
			else
			{
				return FileViewerTransition()
			}
			state.documents.remove(at: index)
			if state.previewDocumentID == id
			{
				state.previewDocumentID = nil
			}
			if state.selectedDocumentID == id
			{
				state.selectedDocumentID = state.documents.indices.contains(index)
					? state.documents[index].id : state.documents.last?.id
			}
			return FileViewerTransition(
				effects: [.cancelRead(id)],
				changed: true
			)
		}
	}

	private static func beginRefresh(
		state: inout FileViewerState,
		index: Int
	) -> FileViewerTransition
	{
		guard !state.documents[index].isSaving
		else
		{
			return FileViewerTransition(changed: true)
		}
		state.documents[index].loadGeneration += 1
		if !state.documents[index].isDirty
		{
			state.documents[index].status = .loading
		}
		let document = state.documents[index]
		return FileViewerTransition(
			effects: [.cancelRead(document.id), .read(
				document.id,
				document.location,
				document.loadGeneration
			)],
			changed: true
		)
	}
}
