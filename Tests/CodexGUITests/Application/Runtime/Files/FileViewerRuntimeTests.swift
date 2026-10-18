import Foundation
import Testing

@testable import CodexGUI

@Suite(.timeLimit(.minutes(1)))
struct FileViewerRuntimeTests
{
	@Test @MainActor
	func closingAfterFileBecomesPipeSettlesAndKeepsUnsavedText() async throws
	{
		let fixture = try await BackgroundTestWork.perform
		{
			let fixture = try FileReadSafetyFixture()
			try Data("disk".utf8).write(to: fixture.root.appendingPathComponent("document.txt"))
			return fixture
		}
		let runtime = FileViewerRuntime(autosaveDelay: .seconds(60))
		do
		{
			let location = FileLocation(
				root: fixture.root.path,
				relativePath: "document.txt"
			)
			runtime.switchRoot(location.root)
			runtime.open(location)
			let id = try #require(runtime.state.selectedDocumentID)
			await runtime.readTask(for: id)?.value
			#expect(runtime.state.selectedDocument?.currentText == "disk")
			runtime.edit(
				id,
				text: "local edit"
			)
			let pipe = try await BackgroundTestWork.perform
			{
				try FileManager.default.removeItem(at: location.fileURL)
				return try fixture.makePipe(named: "document.txt")
			}
			let rescue = FileReadSafetyFixture.rescueBlockedOpen(at: pipe)
			let result = await runtime.close(
				id,
				choice: .save
			)
			rescue.cancel()
			#expect(await rescue.value == false)
			#expect(result == .decisionRequired(.invalidPath))
			#expect(runtime.state.selectedDocument?.currentText == "local edit")
			#expect(runtime.state.selectedDocument?.isDirty == true)
			let discarded = await runtime.close(
				id,
				choice: .discard
			)
			#expect(discarded == .closed)
			#expect(runtime.state.documents.isEmpty)
		}
		catch
		{
			_ = await runtime.shutdown()
			try? FileManager.default.removeItem(at: fixture.root)
			throw error
		}
		_ = await runtime.shutdown()
		try? FileManager.default.removeItem(at: fixture.root)
	}

	@Test @MainActor
	func repeatedSearchDismissalDoesNotPublishUnchangedState() async throws
	{
		try await withRuntimeFixture
		{
			runtime, _ in
			runtime.switchRoot("/tmp/workspace")
			var publications = 0
			runtime.onChange =
			{
				_ in publications += 1
			}
			runtime.cancelSearch()
			#expect(publications == 0)
			runtime.filenameSearch(query: "pending")
			let pending = runtime.currentSearchTask()
			runtime.cancelSearch()
			#expect(publications == 2)
			#expect(runtime.state.searchRequest == nil)
			runtime.cancelSearch()
			#expect(publications == 2)
			await pending?.value
		}
	}

	@Test @MainActor
	func previewReplacementProtectsEditedDocumentAndReusesLocation() async throws
	{
		try await withRuntimeFixture
		{
			runtime, service in
			runtime.switchRoot("/tmp/workspace")
			let first = FileLocation(
				root: "/tmp/workspace",
				relativePath: "a.txt"
			)
			let second = FileLocation(
				root: "/tmp/workspace",
				relativePath: "b.txt"
			)
			runtime.open(first)
			let firstID = try #require(runtime.state.selectedDocumentID)
			await service.waitForRead(first)
			await service.finishRead(
				first,
				text: "before"
			)
			await runtime.readTask(for: firstID)?.value
			runtime.edit(
				firstID,
				text: "edited"
			)
			runtime.open(second)
			#expect(runtime.state.documents.map(\.location) == [first, second])
			runtime.open(
				first,
				retained: true
			)
			#expect(runtime.state.selectedDocumentID == firstID)
			#expect(runtime.state.documents.count == 2)
			#expect(runtime.state.selectedDocument?.currentText == "edited")
		}
	}

	@Test @MainActor
	func lateLoadAfterRootSwitchCannotReplaceAnotherDocument() async throws
	{
		try await withRuntimeFixture
		{
			runtime, service in
			let old = FileLocation(
				root: "/tmp/old",
				relativePath: "same.txt"
			)
			let new = FileLocation(
				root: "/tmp/new",
				relativePath: "same.txt"
			)
			runtime.switchRoot(old.root)
			runtime.open(old)
			await service.waitForRead(old)
			runtime.retain(try #require(runtime.state.selectedDocumentID))
			let oldID = try #require(runtime.state.selectedDocumentID)
			let oldTask = runtime.readTask(for: oldID)
			runtime.switchRoot(new.root)
			runtime.open(new)
			let newID = try #require(runtime.state.selectedDocumentID)
			let newTask = runtime.readTask(for: newID)
			await service.waitForRead(new)
			await service.finishRead(
				new,
				text: "new"
			)
			await service.finishRead(
				old,
				text: "old"
			)
			await newTask?.value
			await oldTask?.value
			#expect(runtime.state.selectedDocument?.location == new)
			#expect(runtime.state.selectedDocument?.currentText == "new")
			#expect(runtime.state.documents.first?.location == old)
		}
	}

	@Test @MainActor
	func failedSaveKeepsLocalTextAndCloseRequiresDecision() async throws
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
				text: "local"
			)
			await service.setSaveFailure(.readOnly)
			let failure = await runtime.save(id)
			#expect(failure == .readOnly)
			#expect(runtime.state.selectedDocument?.currentText == "local")
			#expect(runtime.state.selectedDocument?.isDirty == true)
			let deniedClose = await runtime.close(
				id,
				choice: .save
			)
			#expect(deniedClose == .decisionRequired(.readOnly))
			#expect(runtime.state.documents.count == 1)
			let discarded = await runtime.close(
				id,
				choice: .discard
			)
			#expect(discarded == .closed)
			#expect(runtime.state.documents.isEmpty)
		}
	}

	@Test @MainActor
	func newerEditDuringSaveIsFlushedAfterFirstRevision() async throws
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
				text: "first"
			)
			await service.blockNextSave()
			let firstSave = Task
			{
				await runtime.save(id)
			}
			await service.waitForSaveCount(1)
			runtime.edit(
				id,
				text: "second"
			)
			await service.releaseSave()
			let firstFailure = await firstSave.value
			#expect(firstFailure == nil)
			let saved = await service.savedTexts()
			#expect(saved == ["first", "second"])
			#expect(runtime.state.selectedDocument?.isDirty == false)
		}
	}

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
				text: "discard me"
			)
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
	func failedSaveCanBeEditedAndRetriedWhileReadOnlyDocumentRejectsEdit() async throws
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
				text: "first"
			)
			await service.setSaveFailure(.readOnly)
			#expect(await runtime.save(id) == .readOnly)
			runtime.edit(
				id,
				text: "recovered"
			)
			#expect(runtime.state.selectedDocument?.currentText == "recovered")
			await service.setSaveFailure(nil)
			#expect(await runtime.save(id) == nil)
			#expect(await service.savedTexts() == ["recovered"])

			let readonly = FileLocation(
				root: location.root,
				relativePath: "locked.txt"
			)
			runtime.open(
				readonly,
				retained: true
			)
			let readonlyID = try #require(runtime.state.selectedDocumentID)
			await service.waitForRead(readonly)
			await service.finishRead(
				readonly,
				text: "locked",
				isReadOnly: true
			)
			await runtime.readTask(for: readonlyID)?.value
			runtime.edit(
				readonlyID,
				text: "changed"
			)
			#expect(runtime.state.selectedDocument?.currentText == "locked")
			#expect(runtime.state.selectedDocument?.isDirty == false)
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
	func cleanSelectionRefreshesChangedDeletedAndRecreatedFileAtSameIdentity() async throws
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
				text: "first"
			)
			await runtime.readTask(for: id)?.value

			runtime.select(id)
			await service.waitForRead(location)
			await service.finishRead(
				location,
				text: "changed",
				digest: "changed"
			)
			await runtime.readTask(for: id)?.value
			#expect(runtime.state.selectedDocument?.id == id)
			#expect(runtime.state.selectedDocument?.currentText == "changed")

			runtime.refreshSelectedIfClean()
			await service.waitForRead(location)
			await service.failRead(
				location,
				.unavailable
			)
			await runtime.readTask(for: id)?.value
			#expect(runtime.state.selectedDocument?.status == .failed(.unavailable))

			runtime.open(location)
			await service.waitForRead(location)
			await service.finishRead(
				location,
				text: "recreated",
				digest: "recreated"
			)
			await runtime.readTask(for: id)?.value
			#expect(runtime.state.selectedDocument?.id == id)
			#expect(runtime.state.selectedDocument?.currentText == "recreated")
		}
	}

	@Test @MainActor
	func dirtyRefreshComparesDiskRevisionWithoutLosingLocalText() async throws
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
				text: "local"
			)
			runtime.select(id)
			#expect(runtime.state.selectedDocument?.status == .ready)
			runtime.refresh(id)
			await service.waitForRead(location)
			await service.finishRead(
				location,
				text: "disk"
			)
			await runtime.readTask(for: id)?.value
			#expect(runtime.state.selectedDocument?.status == .ready)
			#expect(runtime.state.selectedDocument?.currentText == "local")

			runtime.refresh(id)
			await service.waitForRead(location)
			await service.finishRead(
				location,
				text: "external",
				digest: "changed"
			)
			await runtime.readTask(for: id)?.value
			#expect(runtime.state.selectedDocument?.status == .conflict)
			#expect(runtime.state.selectedDocument?.currentText == "local")
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
