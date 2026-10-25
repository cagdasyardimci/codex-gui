import Foundation
import Testing

@testable import CodexGUI

@Suite(.timeLimit(.minutes(1)))
struct FileViewerRuntimeTests
{

	@Test @MainActor
	func conflictChoicesPreserveCorrectBufferAndDiscardCannotSaveLater() async throws
	{
		try await withRuntimeFixture
		{
			runtime, service in
			let location = FileLocation(
				root: "/tmp/workspace",
				relativePath: "file.txt"
			)
			runtime.switchRoot(location.root)
			runtime.open(location)
			let id = try #require(runtime.state.selectedDocumentID)
			await service.waitForRead(location)
			await service.finishRead(
				location,
				text: "disk"
			)
			await runtime.readTask(for: id)?.value

			runtime.edit(
				id,
				text: "local one"
			)
			await service.setSaveFailure(.conflict)
			#expect(await runtime.save(id) == .conflict)
			runtime.edit(
				id,
				text: "Blocked until the conflict is resolved"
			)
			#expect(runtime.state.selectedDocument?.currentText == "local one")
			await service.setSaveFailure(nil)
			await runtime.useDisk(id)
			await service.waitForRead(location)
			await service.finishRead(
				location,
				text: "external"
			)
			await runtime.readTask(for: id)?.value
			#expect(runtime.state.selectedDocument?.currentText == "external")
			#expect(runtime.state.selectedDocument?.isDirty == false)

			runtime.edit(
				id,
				text: "local two"
			)
			await service.setSaveFailure(.conflict)
			#expect(await runtime.save(id) == .conflict)
			await service.setSaveFailure(nil)
			let continueTask = Task
			{
				await runtime.continueEditing(id)
			}
			await service.waitForRead(location)
			await service.finishRead(
				location,
				text: "another external"
			)
			#expect(await continueTask.value == nil)
			#expect(runtime.state.selectedDocument?.currentText == "local two")
			#expect(runtime.state.selectedDocument?.isDirty == true)
			#expect(await runtime.save(id) == nil)
			#expect(await service.savedTexts() == ["local two"])

			runtime.edit(
				id,
				text: "local three"
			)
			await service.setSaveFailure(.conflict)
			#expect(await runtime.save(id) == .conflict)
			await service.setSaveFailure(nil)
			let acceptTask = Task
			{
				await runtime.keepLocal(id)
			}
			await service.waitForRead(location)
			await service.finishRead(
				location,
				text: "external before accept"
			)
			#expect(await acceptTask.value == nil)
			#expect(await service.savedTexts() == ["local two", "local three"])

			runtime.edit(
				id,
				text: "Retain this failed save"
			)
			let writeFailure = FileViewerFailure.io("Write failed")
			await service.setSaveFailure(writeFailure)
			#expect(await runtime.save(id) == writeFailure)
			#expect(runtime.state.selectedDocument?.currentText == "Retain this failed save")
			#expect(runtime.state.selectedDocument?.isDirty == true)
			runtime.edit(
				id,
				text: "discard me"
			)
			#expect(runtime.state.selectedDocument?.currentText == "discard me")
			await service.setSaveFailure(.conflict)
			#expect(await runtime.save(id) == .conflict)
			let savedBeforeDiscard = await service.savedTexts()
			#expect(await runtime.close(
				id,
				choice: .discard
			) == .closed)
			#expect(await service.savedTexts() == savedBeforeDiscard)
		}
	}

	@Test @MainActor
	func staleDirectoryAndSearchResultsCannotReplaceNewRootOrQuery() async throws
	{
		try await withRuntimeFixture
		{
			runtime, service in
			let oldRoot = FileLocation(
				root: "/tmp/old",
				relativePath: ""
			)
			let newRoot = FileLocation(
				root: "/tmp/new",
				relativePath: ""
			)
			await service.blockDirectory(oldRoot)
			runtime.switchRoot(oldRoot.root)
			runtime.listDirectory(oldRoot)
			await service.waitForDirectory(oldRoot)
			runtime.switchRoot(newRoot.root)
			await service.finishDirectory(
				oldRoot,
				entries: [FileViewerDirectoryEntry(
					location: FileLocation(
						root: oldRoot.root,
						relativePath: "stale.txt"
					),
					isDirectory: false,
					isSymbolicLink: false
				)]
			)
			#expect(runtime.state.directoryEntries[oldRoot] == nil)

			await service.blockFilename("old")
			runtime.filenameSearch(query: "old")
			await service.waitForFilename("old")
			await service.blockFilename("new")
			runtime.filenameSearch(query: "new")
			let newSearch = runtime.currentSearchTask()
			await service.waitForFilename("new")
			await service.finishFilename(
				"new",
				root: newRoot.root
			)
			await service.finishFilename(
				"old",
				root: newRoot.root
			)
			await newSearch?.value
			#expect(runtime.state.filenameResults?.results.map(\.relativePath) == ["new.txt"])
		}
	}

	@Test @MainActor
	func shutdownAwaitsCancelledReadDirectoryAndSearchWork() async throws
	{
		try await withRuntimeFixture
		{
			runtime, service in
			let root = FileLocation(
				root: "/tmp/workspace",
				relativePath: ""
			)
			let file = FileLocation(
				root: root.root,
				relativePath: "file.txt"
			)
			await service.blockDirectory(root)
			await service.blockFilename("pending")
			runtime.switchRoot(root.root)
			runtime.open(file)
			runtime.listDirectory(root)
			runtime.filenameSearch(query: "pending")
			await service.waitForRead(file)
			await service.waitForDirectory(root)
			await service.waitForFilename("pending")
			let failures = await runtime.shutdown()
			#expect(failures.isEmpty)
			#expect(await service.pendingOperationCount() == 0)
		}
	}
}

@MainActor
private func withRuntimeFixture(
	_ body: (FileViewerRuntime, ControlledFileViewerService) async throws -> Void
) async throws
{
	let service = ControlledFileViewerService()
	let runtime = FileViewerRuntime(
		service: service,
		autosaveDelay: .seconds(60)
	)
	do
	{
		try await body(
			runtime,
			service
		)
	}
	catch
	{
		await service.releaseSave()
		await service.releasePendingReads()
		await service.releasePendingDirectoriesAndSearches()
		_ = await runtime.shutdown()
		throw error
	}
	await service.releaseSave()
	await service.releasePendingReads()
	await service.releasePendingDirectoriesAndSearches()
	_ = await runtime.shutdown()
}

private actor ControlledFileViewerService: FileViewerService
{
	private var readContinuations: [FileLocation: CheckedContinuation<FileViewerRead, Error>] = [:]
	private var readWaiters: [FileLocation: CheckedContinuation<Void, Never>] = [:]
	private var saveFailure: FileViewerFailure?
	private var saveTexts: [String] = []
	private var saveWaiter: CheckedContinuation<Void, Never>?
	private var saveGate: CheckedContinuation<Void, Never>?
	private var blocksFirstSave = false
	private var blockedDirectories: Set<FileLocation> = []
	private var directoryContinuations:
		[FileLocation: CheckedContinuation<[FileViewerDirectoryEntry], Error>] = [:]
	private var directoryWaiters: [FileLocation: CheckedContinuation<Void, Never>] = [:]
	private var blockedFilenames: Set<String> = []
	private var filenameContinuations:
		[String: CheckedContinuation<FileViewerSearchPage<FileLocation>, Error>] = [:]
	private var filenameWaiters: [String: CheckedContinuation<Void, Never>] = [:]

	func listDirectory(at location: FileLocation) async throws -> [FileViewerDirectoryEntry]
	{
		guard blockedDirectories.contains(location)
		else
		{
			return []
		}
		return try await withTaskCancellationHandler
		{
			try await withCheckedThrowingContinuation
			{
				directoryContinuations[location] = $0
				directoryWaiters.removeValue(forKey: location)?.resume()
			}
		} onCancel:
		{
			Task
			{
				await self.cancelDirectory(location)
			}
		}
	}
	func filenameSearch(
		root: String,
		query: String,
		limit: Int
	) async throws
		-> FileViewerSearchPage<FileLocation>
	{
		guard blockedFilenames.contains(query)
		else
		{
			return FileViewerSearchPage(
				results: [],
				isTruncated: false
			)
		}
		return try await withTaskCancellationHandler
		{
			try await withCheckedThrowingContinuation
			{
				filenameContinuations[query] = $0
				filenameWaiters.removeValue(forKey: query)?.resume()
			}
		} onCancel:
		{
			Task
			{
				await self.cancelFilename(query)
			}
		}
	}

	func blockDirectory(_ location: FileLocation)
	{
		blockedDirectories.insert(location)
	}
	func blockFilename(_ query: String)
	{
		blockedFilenames.insert(query)
	}
	func waitForDirectory(_ location: FileLocation) async
	{
		if directoryContinuations[location] != nil
		{
			return
		}
		await withCheckedContinuation
		{
			directoryWaiters[location] = $0
		}
	}
	func waitForFilename(_ query: String) async
	{
		if filenameContinuations[query] != nil
		{
			return
		}
		await withCheckedContinuation
		{
			filenameWaiters[query] = $0
		}
	}
	func finishDirectory(
		_ location: FileLocation,
		entries: [FileViewerDirectoryEntry]
	)
	{
		directoryContinuations.removeValue(forKey: location)?.resume(returning: entries)
	}
	func finishFilename(
		_ query: String,
		root: String
	)
	{
		filenameContinuations.removeValue(forKey: query)?.resume(returning: FileViewerSearchPage(
			results: [FileLocation(
				root: root,
				relativePath: "\(query).txt"
			)],
			isTruncated: false
		))
	}
	private func cancelDirectory(_ location: FileLocation)
	{
		directoryContinuations.removeValue(forKey: location)?.resume(throwing: CancellationError())
	}
	private func cancelFilename(_ query: String)
	{
		filenameContinuations.removeValue(forKey: query)?.resume(throwing: CancellationError())
	}
	func releasePendingDirectoriesAndSearches()
	{
		for value in directoryContinuations.values
		{
			value.resume(throwing: CancellationError())
		}
		for value in filenameContinuations.values
		{
			value.resume(throwing: CancellationError())
		}
		directoryContinuations.removeAll()
		filenameContinuations.removeAll()
	}
	func pendingOperationCount() -> Int
	{
		readContinuations.count + directoryContinuations.count + filenameContinuations.count
	}
	func contentSearch(
		root: String,
		query: String,
		mask: String?,
		limit: Int
	) async throws
		-> FileViewerSearchPage<FileViewerSearchResult>
	{
		FileViewerSearchPage(
			results: [],
			isTruncated: false
		)
	}

	func read(at location: FileLocation) async throws -> FileViewerRead
	{
		try await withTaskCancellationHandler
		{
			try await withCheckedThrowingContinuation
			{
				continuation in
				readContinuations[location] = continuation
				readWaiters.removeValue(forKey: location)?.resume()
			}
		} onCancel:
		{
			Task
			{
				await self.cancelRead(location)
			}
		}
	}

	private func cancelRead(_ location: FileLocation)
	{
		readContinuations.removeValue(forKey: location)?.resume(throwing: CancellationError())
	}

	func releasePendingReads()
	{
		for continuation in readContinuations.values
		{
			continuation.resume(throwing: CancellationError())
		}
		readContinuations.removeAll()
	}

	func waitForRead(_ location: FileLocation) async
	{
		if readContinuations[location] != nil
		{
			return
		}
		await withCheckedContinuation
		{
			readWaiters[location] = $0
		}
	}

	func finishRead(
		_ location: FileLocation,
		text: String,
		isReadOnly: Bool = false,
		digest: String = "initial"
	)
	{
		readContinuations.removeValue(forKey: location)?.resume(returning: FileViewerRead(
			content: .text(text),
			revision: FileDiskRevision(
				digest: digest,
				byteCount: 4
			),
			isReadOnly: isReadOnly
		))
	}

	func failRead(
		_ location: FileLocation,
		_ error: FileViewerFailure
	)
	{
		readContinuations.removeValue(forKey: location)?.resume(throwing: error)
	}

	func setSaveFailure(_ error: FileViewerFailure?)
	{
		saveFailure = error
	}
	func blockNextSave()
	{
		blocksFirstSave = true
	}
	func savedTexts() -> [String]
	{
		saveTexts
	}
	func waitForSaveCount(_ count: Int) async
	{
		if saveTexts.count >= count
		{
			return
		}
		await withCheckedContinuation
		{
			saveWaiter = $0
		}
	}
	func releaseSave()
	{
		saveGate?.resume(); saveGate = nil
	}

	func save(
		at location: FileLocation,
		text: String,
		expectedRevision: FileDiskRevision
	) async throws -> FileDiskRevision
	{
		if let saveFailure
		{
			throw saveFailure
		}
		saveTexts.append(text)
		saveWaiter?.resume()
		saveWaiter = nil
		if blocksFirstSave
		{
			blocksFirstSave = false
			await withCheckedContinuation
			{
				saveGate = $0
			}
		}
		return FileDiskRevision(
			digest: "saved-\(saveTexts.count)",
			byteCount: text.utf8.count
		)
	}
}
