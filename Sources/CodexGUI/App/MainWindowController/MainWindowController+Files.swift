import AppKit

extension MainWindowController
{
	func configureFilesIntegration()
	{
		conversation.transcript.onOpenFileReference =
		{
			[weak self] reference in
			guard let self, let root = self.currentFileProjectPath
			else
			{
				return
			}
			let path = URL(fileURLWithPath: reference.path).standardizedFileURL.path
			let prefix = root.hasSuffix("/") ? root : root + "/"
			guard path.hasPrefix(prefix)
			else
			{
				return
			}
			self.openFilesToolTab()
			self.files.open(
				FileLocation(
					root: root,
					relativePath: String(path.dropFirst(prefix.count))
				),
				line: reference.line
			)
		}
		configureChatFileActions(activeChatTools)
	}

	func configureChatFileActions(_ session: ChatToolsSession)
	{
		let files = session.files
		let tabs = session.tabs
		let runtime = files.runtime
		files.captureAttachmentReceiver =
		{
			[weak self, weak files] in
			guard let self, self.files === files
			else
			{
				return nil
			}
			return self.conversation.makeContextAttachmentReceiver()
		}
		files.onStateChange =
		{
			[weak files, weak tabs] state in
			guard let files, let tabs
			else
			{
				return
			}
			Self.publishFileTabs(
				state,
				files: files,
				tabs: tabs
			)
		}
		tabs.onFilesPresentationVisible =
		{
			[weak files] visible in files?.setPresentationVisible(visible)
		}
		tabs.onOpenFiles =
		{
			[weak self] in self?.openFilesToolTab()
		}
		tabs.onFileSelected =
		{
			[weak runtime] id in
			guard let runtime, runtime.state.selectedDocumentID != id
			else
			{
				return
			}
			runtime.select(id)
		}
		tabs.onFileRetainRequested =
		{
			[weak runtime] in runtime?.retain($0)
		}
		tabs.onFileCloseRequested =
		{
			[weak self, weak runtime] id in
			if let runtime
			{
				self?.enqueueFileClose(
					id,
					in: runtime
				)
			}
		}
	}

	func openImageInToolTab(
		data: Data,
		name: String,
		sourceURL: URL?
	)
	{
		configureToolsPaneClosing()
		if !inspector.isShowingTools || paneController.isReviewCollapsed
		{
			paneController.openToolsPane
			{
				self.inspector.showImageInToolTab(
					data: data,
					name: name,
					sourceURL: sourceURL
				)
			}
		}
		else
		{
			inspector.showImageInToolTab(
				data: data,
				name: name,
				sourceURL: sourceURL
			)
		}
		updateToolsToolbarControls()
	}

	func openFilesToolTab()
	{
		configureToolsPaneClosing()
		let path = currentFileProjectPath
		if activeChatTools.filesProjectPath != path
		{
			activeChatTools.filesProjectPath = path
			files.runtime.switchRoot(path)
		}
		if !inspector.isShowingTools || paneController.isReviewCollapsed
		{
			paneController.openToolsPane
			{
				self.inspector.showFilesInToolTab(self.files)
			}
		}
		else
		{
			inspector.showFilesInToolTab(files)
		}
		updateToolsToolbarControls()
	}

	func showFileQuickOpen()
	{
		guard currentFileProjectPath != nil
		else
		{
			return
		}
		pendingFileSearch = .filename
		openFilesToolTab()
		presentPendingFileSearch()
	}

	func showFileContentSearch()
	{
		guard currentFileProjectPath != nil
		else
		{
			return
		}
		pendingFileSearch = .content
		openFilesToolTab()
		presentPendingFileSearch()
	}

	func presentPendingFileSearch()
	{
		guard let pendingFileSearch, !paneController.isAnimatingToolsExpansion
		else
		{
			return
		}
		if !inspector.isShowingTools || !inspector.toolsTabs.isFilesSelected
		{
			openFilesToolTab()
		}
		guard inspector.isShowingTools, inspector.toolsTabs.isFilesSelected,
				files.view.window != nil
		else
		{
			return
		}
		self.pendingFileSearch = nil
		switch pendingFileSearch
		{
		case .filename: files.presentQuickOpen()
		case .content: files.presentContentSearch()
		}
		onFileSearchPresented?(pendingFileSearch)
	}

	func findInCurrentFile()
	{
		files.focusFind()
	}

	var isActiveFilesSurface: Bool
	{
		inspector.isShowingTools && !paneController.isReviewCollapsed &&
			inspector.toolsTabs.isFilesSelected
	}

	var shouldRouteFindToFiles: Bool
	{
		guard isActiveFilesSurface, let responder = window?.firstResponder as? NSView
		else
		{
			return false
		}
		if responder.isDescendant(of: files.view)
		{
			return true
		}
		if let editor = responder as? NSTextView,
			let owner = editor.delegate as? NSView
		{
			return owner.isDescendant(of: files.view)
		}
		return false
	}

	private var currentFileProjectPath: String?
	{
		let snapshot = coordinator?.currentSnapshot ?? currentStore.currentSnapshot
		return WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		).reference.workspace.canonicalCheckoutPath
	}

	private static func publishFileTabs(
		_ state: FileViewerState,
		files: FilesViewController,
		tabs: ToolsTabViewController
	)
	{
		let presentations = state.documents.map
		{
			document in
			FileToolTabPresentation(
				id: document.id,
				title: document.location.fileURL.lastPathComponent,
				path: document.location.fileURL.path,
				isPreview: !document.isRetained,
				isDirty: document.isDirty
			)
		}
		tabs.updateFileTabs(
			presentations: presentations,
			selectedID: state.selectedDocumentID,
			controller: files
		)
	}

	private func enqueueFileClose(
		_ id: UUID,
		in runtime: FileViewerRuntime
	)
	{
		guard !fileCloseRequests.contains(id), !fileCloseQueue.contains(where:
			{
				$0.id == id
			})
		else
		{
			return
		}
		fileCloseQueue.append((runtime, id))
		guard !fileClosePumpRunning
		else
		{
			return
		}
		fileClosePumpRunning = true
		fileClosePumpTask = Task
		{
			while !fileCloseQueue.isEmpty
			{
				let next = fileCloseQueue.removeFirst()
				await closeFileTab(
					next.id,
					in: next.runtime
				)
			}
			fileClosePumpRunning = false
			fileClosePumpTask = nil
		}
	}

	private func closeFileTab(
		_ id: UUID,
		in runtime: FileViewerRuntime
	) async
	{
		guard fileCloseRequests.insert(id).inserted
		else
		{
			return
		}
		defer
		{
			fileCloseRequests.remove(id)
		}
		let result = await runtime.close(
			id,
			choice: .save
		)
		guard case .decisionRequired(let failure) = result,
				let captured = runtime.state.documents.first(where:
				{
					$0.id == id
				})
		else
		{
			return
		}
		if shouldDiscardFiles(
			ids: [id],
			failure: failure,
			isWindowClosing: false
		), runtime.state.documents.contains(where:
			{
				$0.id == id && $0.editRevision == captured.editRevision && $0.isDirty
			})
		{
			_ = await runtime.close(
				id,
				choice: .discard
			)
		}
	}

	func settleFileWritesForClosing() async -> Bool
	{
		if let fileSettlementTask
		{
			return await fileSettlementTask.value
		}
		let task = Task
		{
			await performFileSettlement()
		}
		fileSettlementTask = task
		let result = await task.value
		fileSettlementTask = nil
		return result
	}

	var hasPendingFileWrites: Bool
	{
		chatFileRuntimes.contains
		{
			$0.state.documents.contains
			{
				$0.isDirty || $0.isSaving
			}
		}
	}

	private func performFileSettlement() async -> Bool
	{
		if let fileClosePumpTask
		{
			await fileClosePumpTask.value
		}
		var failure: FileViewerFailure?
		var captured: [(runtime: FileViewerRuntime, id: UUID, revision: Int)] = []
		for runtime in chatFileRuntimes
		{
			let failures = await runtime.flushAll()
			failure = failure ?? failures.values.first
			captured += runtime.state.documents.compactMap
			{
				document in
				guard document.isDirty, failures[document.id] != nil
				else
				{
					return nil
				}
				return (runtime, document.id, document.editRevision)
			}
		}
		guard let failure
		else
		{
			return !hasPendingFileWrites
		}
		guard shouldDiscardFiles(
			ids: captured.map(\.id),
			failure: failure,
			isWindowClosing: true
		)
		else
		{
			return false
		}
		guard captured.allSatisfy(
			{
				item in
				item.runtime.state.documents.contains(where:
					{
						$0.id == item.id && $0.editRevision == item.revision
					})
			}
		)
		else
		{
			return false
		}
		for (runtime, id, revision) in captured
		{
			guard let current = runtime.state.documents.first(where:
				{
					$0.id == id
				})
			else
			{
				continue
			}
			if !current.isDirty
			{
				continue
			}
			guard current.editRevision == revision
			else
			{
				return false
			}
			_ = await runtime.close(
				id,
				choice: .discard
			)
		}
		return !hasPendingFileWrites
	}

	private func shouldDiscardFiles(
		ids: [UUID],
		failure: FileViewerFailure?,
		isWindowClosing: Bool
	) -> Bool
	{
		if let onFileDiscardDecision
		{
			return onFileDiscardDecision(
				ids,
				failure
			)
		}
		let confirmation = DesktopNativeConfirmation(
			title: isWindowClosing
				? "Some file edits could not be saved" : "Could not save file",
			message: isWindowClosing
				? "Keep this window open to resolve the edits, or discard the local edits."
				: failure == .conflict
				? "The file changed on disk. Keep viewing it or discard the local edits."
				: "Keep viewing the file or discard the local edits.",
			confirmTitle: "Discard Local Edits",
			cancelTitle: "Keep Viewing"
		)
		return confirmation.runModal()
	}
}
