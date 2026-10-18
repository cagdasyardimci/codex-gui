import AppKit
import Testing

@testable import CodexGUI

@Suite(.timeLimit(.minutes(2))) @MainActor
struct FilesWindowIntegrationTests
{
	@Test func openingFilesReusesLandingWithoutReplacingChanges() throws
	{
		_ = NSApplication.shared
		let suite = "FilesWindowIntegration.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let fixture = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults))
		let window = MainWindowController(
			store: fixture.store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			}
		)
		window.openFilesToolTab()
		let tabs = window.inspector.toolsTabs
		let landing = try #require(tabs.filesLandingTabID)
		#expect(tabs.isFilesSelected)
		#expect(window.files.parent === tabs)
		window.openFilesToolTab()
		#expect(tabs.filesLandingTabID == landing)

		let changes = window.inspector.gitChanges
		tabs.showChanges(changes)
		let changesTab = try #require(tabs.changesTabID)
		window.openFilesToolTab()
		#expect(tabs.filesLandingTabID == landing)
		#expect(tabs.changesTabID == changesTab)
		#expect(tabs.isFilesSelected)
		let selectChanges = try #require(findButton(
			"Changes 2",
			in: tabs.tabBarView
		))
		#expect(selectChanges.dispatchConfiguredAction())
		#expect(tabs.isChangesSelected)
		#expect(changes.parent === tabs)
	}

	@Test func dirtyCloseTargetsCapturedTabAndKeepsItOnCancel() async throws
	{
		_ = NSApplication.shared
		let defaults = try IsolatedUserDefaultsFixture(prefix: "FilesCloseWindow")
		defer
		{
			defaults.cleanup()
		}
		let service = WindowFileService()
		let runtime = FileViewerRuntime(
			service: service,
			autosaveDelay: .seconds(60)
		)
		do
		{
			let fixture = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults.defaults))
			let window = MainWindowController(
				store: fixture.store,
				onOpenProject:
				{
				},
				onInsertPath:
				{
				},
				filesRuntime: runtime
			)
			let root = "/tmp/files-close-\(UUID().uuidString)"
			runtime.switchRoot(root)
			let first = FileLocation(
				root: root,
				relativePath: "first.txt"
			)
			let second = FileLocation(
				root: root,
				relativePath: "second.txt"
			)
			runtime.open(
				first,
				retained: true
			)
			let firstID = try #require(runtime.state.selectedDocumentID)
			await runtime.readTask(for: firstID)?.value
			runtime.open(
				second,
				retained: true
			)
			let secondID = try #require(runtime.state.selectedDocumentID)
			await runtime.readTask(for: secondID)?.value
			window.openFilesToolTab()
			await service.setFailure(.conflict)
			runtime.edit(
				firstID,
				text: "local first"
			)
			var decisions: [[UUID]] = []
			window.onFileDiscardDecision =
			{
				ids, _ in
				decisions.append(ids)
				return false
			}
			let close = try #require(findButton(
				"Close tab 1",
				in: window.inspector.toolsTabs.tabBarView
			))
			#expect(close.dispatchConfiguredAction())
			await window.fileClosePumpTask?.value
			#expect(decisions == [[firstID]])
			#expect(runtime.state.documents.map(\.id) == [firstID, secondID])
			#expect(runtime.state.documents[0].currentText == "local first")
			#expect(window.inspector.toolsTabs.tabCount == 2)
			#expect(await service.text(at: first) == "disk")
			let nativeWindow = try #require(window.window)
			#expect(!window.windowShouldClose(nativeWindow))
			while window.filesCloseInProgress
			{
				await Task.yield()
			}
			#expect(!window.filesCloseApproved)
			#expect(window.inspector.toolsTabs.tabCount == 2)

			window.onFileDiscardDecision =
			{
				ids, _ in
				decisions.append(ids)
				return true
			}
			let closeAgain = try #require(findButton(
				"Close tab 1",
				in: window.inspector.toolsTabs.tabBarView
			))
			#expect(closeAgain.dispatchConfiguredAction())
			await window.fileClosePumpTask?.value
			#expect(decisions.last == [firstID])
			#expect(runtime.state.documents.map(\.id) == [secondID])
			#expect(runtime.state.selectedDocumentID == secondID)
			#expect(await service.text(at: first) == "disk")
		}
		catch
		{
			_ = await runtime.shutdown()
			throw error
		}
		_ = await runtime.shutdown()
	}

	@Test func closingFlushesPendingSaveAndLaterEditsNeedAnotherDrain() async throws
	{
		_ = NSApplication.shared
		let defaults = try IsolatedUserDefaultsFixture(prefix: "FilesPendingWindow")
		defer
		{
			defaults.cleanup()
		}
		let service = WindowFileService()
		let runtime = FileViewerRuntime(
			service: service,
			autosaveDelay: .seconds(60)
		)
		do
		{
			let fixture = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults.defaults))
			let window = MainWindowController(
				store: fixture.store,
				onOpenProject:
				{
				},
				onInsertPath:
				{
				},
				filesRuntime: runtime
			)
			let location = FileLocation(
				root: "/tmp/files-pending-\(UUID().uuidString)",
				relativePath: "notes.txt"
			)
			runtime.switchRoot(location.root)
			runtime.open(
				location,
				retained: true
			)
			let id = try #require(runtime.state.selectedDocumentID)
			await runtime.readTask(for: id)?.value
			await service.blockNextSave()
			runtime.edit(
				id,
				text: "first"
			)
			let firstDrain = Task
			{
				await window.settleFileWritesForClosing()
			}
			await service.waitForSaveCount(1)
			#expect(runtime.state.documents.first?.isSaving == true)
			runtime.edit(
				id,
				text: "second"
			)
			await service.releaseSave()
			#expect(await firstDrain.value)
			#expect(await service.text(at: location) == "second")
			#expect(runtime.state.documents.first?.isDirty == false)

			runtime.edit(
				id,
				text: "newer during quit confirmation"
			)
			#expect(await window.settleFileWritesForClosing())
			#expect(await service.text(at: location) == "newer during quit confirmation")
			#expect(runtime.state.documents.first?.isDirty == false)
		}
		catch
		{
			_ = await runtime.shutdown()
			throw error
		}
		_ = await runtime.shutdown()
	}

	@Test func firstQuickOpenAfterClosedPanePresentsFocusedSheet() async throws
	{
		let fixture = try await CapturedIntentStoreFixture.makeStore()
		defer
		{
			fixture.cleanup()
		}
		let project = URL(fileURLWithPath: try #require(
			fixture.store.model.identity.canonicalCheckoutPath
		))
		try "file body".write(
			to: project.appendingPathComponent("note.txt"),
			atomically: true,
			encoding: .utf8
		)
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let controller = MainWindowController(
				store: fixture.store,
				onOpenProject:
				{
				},
				onInsertPath:
				{
				}
			)
			do
			{
				controller.showWindow(nil)
				#expect(!controller.inspector.isShowingTools)
				await withCheckedContinuation
				{
					continuation in
					controller.onFileSearchPresented =
					{
						_ in continuation.resume()
					}
					controller.showFileQuickOpen()
				}
				let sheet = try #require(controller.window?.attachedSheet)
				#expect(sheet.title == "Quick Open")
				let search = try #require(findSearchField(in: sheet.contentView))
				#expect(sheet.firstResponder === search ||
					sheet.firstResponder === search.currentEditor())
				#expect(controller.pendingFileSearch == nil)
				#expect(controller.isActiveFilesSurface)
				controller.files.quickOpen.dismiss()
				controller.files.open(
					FileLocation(
						root: project.path,
						relativePath: "note.txt"
					),
					retained: true
				)
				let fileID = try #require(controller.files.runtime.state.selectedDocumentID)
				await controller.files.runtime.readTask(for: fileID)?.value
				let source = try #require(findTextView(in: controller.files.document.view))
				#expect(controller.window?.makeFirstResponder(source) == true)
				#expect(controller.shouldRouteFindToFiles)
				let composer = try #require(findTextView(in: controller.conversation.view))
				#expect(controller.window?.makeFirstResponder(composer) == true)
				#expect(!controller.shouldRouteFindToFiles)
				controller.inspector.closeToolsPane()
				#expect(!controller.isActiveFilesSurface)
				#expect(!controller.shouldRouteFindToFiles)
			}
			catch
			{
				controller.files.quickOpen.dismiss()
				_ = await controller.files.runtime.shutdown()
				controller.window?.close()
				throw error
			}
			_ = await controller.files.runtime.shutdown()
			controller.window?.close()
		}
	}

	private func findButton(
		_ label: String,
		in view: NSView
	) -> NSButton?
	{
		if let button = view as? NSButton, button.accessibilityLabel() == label
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			findButton(
				label,
				in: $0
			)
		}.first
	}

	private func findSearchField(in view: NSView?) -> NSTextField?
	{
		guard let view
		else
		{
			return nil
		}
		if let field = view as? NSTextField,
			field.accessibilityLabel() == "Open file by name"
		{
			return field
		}
		return view.subviews.lazy.compactMap
		{
			findSearchField(in: $0)
		}.first
	}

	private func findTextView(in view: NSView) -> NSTextView?
	{
		if let text = view as? NSTextView
		{
			return text
		}
		return view.subviews.lazy.compactMap
		{
			findTextView(in: $0)
		}.first
	}
}

private actor WindowFileService: FileViewerService
{
	private var saved: [FileLocation: String] = [:]
	private var revision = 0
	private var failure: FileViewerFailure?
	private var blockSave = false
	private var saveGate: CheckedContinuation<Void, Never>?
	private var saveCount = 0
	private var saveObservers: [(Int, CheckedContinuation<Void, Never>)] = []

	func listDirectory(at location: FileLocation) async throws -> [FileViewerDirectoryEntry]
	{
		[]
	}
	func read(at location: FileLocation) async throws -> FileViewerRead
	{
		let text = saved[location] ?? "disk"
		return FileViewerRead(
			content: .text(text),
			revision: FileDiskRevision(
				digest: "revision-\(revision)",
				byteCount: text.utf8.count
			),
			isReadOnly: false
		)
	}
	func save(
		at location: FileLocation,
		text: String,
		expectedRevision: FileDiskRevision
	) async throws -> FileDiskRevision
	{
		saveCount += 1
		let ready = saveObservers.filter
		{
			$0.0 <= saveCount
		}
		saveObservers.removeAll
		{
			$0.0 <= saveCount
		}
		ready.forEach
		{
			$0.1.resume()
		}
		if blockSave
		{
			blockSave = false
			await withCheckedContinuation
			{
				saveGate = $0
			}
		}
		if let failure
		{
			throw failure
		}
		revision += 1
		saved[location] = text
		return FileDiskRevision(
			digest: "revision-\(revision)",
			byteCount: text.utf8.count
		)
	}
	func filenameSearch(
		root: String,
		query: String,
		limit: Int
	) async throws -> FileViewerSearchPage<FileLocation>
	{
		FileViewerSearchPage(
			results: [],
			isTruncated: false
		)
	}
	func contentSearch(
		root: String,
		query: String,
		mask: String?,
		limit: Int
	) async throws -> FileViewerSearchPage<FileViewerSearchResult>
	{
		FileViewerSearchPage(
			results: [],
			isTruncated: false
		)
	}
	func setFailure(_ failure: FileViewerFailure?)
	{
		self.failure = failure
	}
	func blockNextSave()
	{
		blockSave = true
	}
	func releaseSave()
	{
		saveGate?.resume(); saveGate = nil
	}
	func text(at location: FileLocation) -> String
	{
		saved[location] ?? "disk"
	}
	func waitForSaveCount(_ count: Int) async
	{
		if saveCount >= count
		{
			return
		}
		await withCheckedContinuation
		{
			saveObservers.append((count, $0))
		}
	}
}
