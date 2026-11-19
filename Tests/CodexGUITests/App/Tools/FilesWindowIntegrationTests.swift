import AppKit
import Testing

@testable import CodexGUI

@Suite(.timeLimit(.minutes(2))) @MainActor
struct FilesWindowIntegrationTests
{
	enum TabGestureInterruption
	{
		case rebuild, resize, releaseOutside, reorderAfterRebuild
	}

	@Test(
		.appKitIsolation,
		arguments: [
			TabGestureInterruption.rebuild,
			.resize,
			.releaseOutside,
			.reorderAfterRebuild,
		]
	)
	func tabGesturesKeepThePressedTarget(interruption: TabGestureInterruption) async throws
	{
		let fixture = try await CapturedIntentStoreFixture.makeStore(threadID: "tabs")
		defer
		{
			fixture.cleanup()
		}
		let controller = MainWindowController(
			store: fixture.store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			}
		)
		let window = try #require(controller.window)
		window.prepareForTesting()
		defer
		{
			window.close()
		}
		controller.showWindow(nil)
		controller.paneController.openToolsPane()
		await controller.paneController.waitForToolsTransition()
		let tabs = controller.inspector.toolsTabs
		let firstID = try #require(tabs.selectedTabID)
		tabs.openNewTab()
		window.layoutIfNeeded()
		let bar = tabs.tabBarView
		let secondID = try #require(tabs.selectedTabID)
		let label = interruption == .reorderAfterRebuild ? "New tab 2" : "Close tab 2"
		let pressedButton = try #require(findButton(
			label,
			in: bar
		))
		let point = pressedButton.convert(
			NSPoint(
				x: pressedButton.bounds.midX,
				y: pressedButton.bounds.midY
			),
			to: nil
		)
		let windowContent = try #require(window.contentView)
		#expect(bar.isDescendant(of: windowContent))
		#expect(point.y > window.contentLayoutRect.maxY)

		func mouse(
			_ type: NSEvent.EventType,
			at location: NSPoint? = nil
		) throws -> NSEvent
		{
			try #require(NSEvent.mouseEvent(
				with: type,
				location: location ?? point,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 0
			))
		}

		try bar.mouseDown(with: mouse(.leftMouseDown))
		#expect(tabs.tabCount == 2)
		switch interruption
		{
		case .rebuild:
			let first = try #require(findButton(
				"New tab 1",
				in: bar
			))
			#expect(first.dispatchConfiguredAction())
			window.layoutIfNeeded()
			#expect(findButton(
				"Close tab 2",
				in: bar
			) !== pressedButton)
		case .resize:
			var frame = window.frame
			frame.size.width += 48
			window.setFrame(
				frame,
				display: true
			)
			window.layoutIfNeeded()
			try #require(!pressedButton.convert(
				pressedButton.bounds,
				to: nil
			).contains(point))
		case .releaseOutside:
			try bar.mouseUp(with: mouse(
				.leftMouseUp,
				at: .zero
			))
			#expect(tabs.tabCount == 2)
			return
		case .reorderAfterRebuild:
			let first = try #require(findButton(
				"New tab 1",
				in: bar
			))
			let destination = first.convert(
				NSPoint(
					x: first.bounds.midX - 10,
					y: first.bounds.midY
				),
				to: nil
			)
			let frame = window.frame
			try bar.mouseDragged(with: mouse(
				.leftMouseDragged,
				at: destination
			))
			#expect(first.dispatchConfiguredAction())
			window.layoutIfNeeded()
			try #require(findButton(
				label,
				in: bar
			) !== pressedButton)
			try bar.mouseUp(with: mouse(
				.leftMouseUp,
				at: destination
			))
			let reordered = findButton(
				"New tab 1",
				in: bar
			) as? ToolsTabSelectionButton
			#expect(reordered?.tabID == secondID)
			#expect(window.frame == frame)
			return
		}
		try bar.mouseUp(with: mouse(.leftMouseUp))
		#expect(tabs.tabCount == 1)
		#expect(tabs.selectedTabID == firstID)
	}

	@Test(.appKitIsolation)
	func chatsInTheSameCheckoutRestoreTheirOwnTabsAndSaveHiddenEdits() async throws
	{
		_ = NSApplication.shared
		let fixture = try await CapturedIntentStoreFixture.makeStore(threadID: "first")
		defer
		{
			fixture.cleanup()
		}
		let store = fixture.store
		let root = try #require(store.model.identity.canonicalCheckoutPath)
		fixture.service.additionalThreads["second"] = ThreadDetail(
			summary: try #require(ThreadSummary(json: ["id": "second", "cwd": root])),
			turns: [],
			nextTurnsCursor: nil
		)
		await store.inputs.connect()
		let firstRead = try #require(store.inputs.selectThread("first"))
		_ = await firstRead.wait()
		let service = WindowFileService()
		let runtime = FileViewerRuntime(
			service: service,
			autosaveDelay: .seconds(60)
		)
		let controller = MainWindowController(
			store: store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			},
			filesRuntime: runtime
		)
		defer
		{
			controller.window?.close()
		}
		controller.window?.prepareForTesting()
		controller.showWindow(nil)
		let owner = try #require(controller.inspector.summary.currentPresentation?.owner)
		#expect(controller.inspector.openSourcesInToolTab(ContextPanelRequest(
			owner: owner,
			destination: .sources
		)))
		let sourcesTab = try #require(controller.inspector.toolsTabs.sourcesTabID)
		controller.openFilesToolTab()
		await controller.paneController.waitForToolsTransition()
		let firstTabs = controller.inspector.toolsTabs
		let location = FileLocation(
			root: root,
			relativePath: "notes.txt"
		)
		controller.files.open(
			location,
			retained: true
		)
		let id = try #require(runtime.state.selectedDocumentID)
		await runtime.readTask(for: id)?.value
		runtime.edit(
			id,
			text: "edited in first chat"
		)
		controller.paneController.toggleToolsExpanded()
		await controller.paneController.waitForToolsTransition()
		try #require(controller.paneController.isToolsExpanded)

		let secondRead = try #require(store.inputs.selectThread("second"))
		_ = await secondRead.wait()
		#expect(!controller.inspector.isShowingTools)
		#expect(!controller.paneController.isToolsExpanded)
		#expect(controller.inspector.toolsTabs.tabCount == 0)
		#expect(controller.files.runtime.state.documents.isEmpty)
		#expect(controller.toolsToolbar.openButton.tag == 0)
		let window = try #require(controller.window)
		#expect(await controller.settleFileWritesForClosing())
		#expect(await service.text(at: location) == "edited in first chat")

		controller.paneController.openToolsPane()
		await controller.paneController.waitForToolsTransition()
		let secondTab = try #require(controller.inspector.toolsTabs.selectedTabID)
		controller.inspector.closeToolsPane()

		let restoredFirst = try #require(store.inputs.selectThread("first"))
		_ = await restoredFirst.wait()
		let windowContent = try #require(window.contentView)
		#expect(firstTabs.tabBarView.isDescendant(of: windowContent))
		#expect(controller.paneController.isToolsExpanded)
		#expect(controller.inspector.isShowingTools)
		#expect(controller.inspector.toolsTabs.selectedFileDocumentID == id)
		#expect(controller.inspector.toolsTabs.sourcesTabID == sourcesTab)
		#expect(controller.inspector.conversationSources?.parent === firstTabs)
		#expect(controller.files.runtime.state.documents.map(\.id) == [id])

		let restoredSecond = try #require(store.inputs.selectThread("second"))
		_ = await restoredSecond.wait()
		#expect(!controller.inspector.isShowingTools)
		#expect(controller.inspector.toolsTabs.selectedTabID == secondTab)
		#expect(controller.toolsToolbar.openButton.tag == 1)
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
			#expect(await window.settleFileWritesForClosing() == false)
			#expect(decisions == [[firstID], [firstID]])
			#expect(runtime.state.documents.map(\.id) == [firstID, secondID])
			#expect(runtime.state.documents[0].currentText == "local first")
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
