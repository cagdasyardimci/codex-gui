import AppKit

extension MainWindowController
{
	func configureFilesIntegration()
	{
		files.captureAttachmentReceiver =
		{
			[weak conversation = self.conversation] in
			conversation?.makeContextAttachmentReceiver()
		}
		files.onStateChange =
		{
			[weak self] state in self?.publishFileTabs(state)
		}
		inspector.toolsTabs.onFilesPresentationVisible =
		{
			[weak self] visible in self?.files.setPresentationVisible(visible)
		}
		inspector.toolsTabs.onOpenFiles =
		{
			[weak self] in self?.openFilesToolTab()
		}
		inspector.toolsTabs.onFileSelected =
		{
			[weak self] id in
			guard let self, self.files.runtime.state.selectedDocumentID != id
			else
			{
				return
			}
			self.files.runtime.select(id)
		}
		inspector.toolsTabs.onFileRetainRequested =
		{
			[weak self] in self?.files.runtime.retain($0)
		}
		inspector.toolsTabs.onFileCloseRequested =
		{
			[weak self] id in self?.enqueueFileClose(id)
		}
	}

	func updateFilesProject(target: WorkspaceIntentTarget)
	{
		guard filesWereOpened
		else
		{
			return
		}
		let path = target.reference.workspace.canonicalCheckoutPath
		guard path != filesProjectPath
		else
		{
			return
		}
		filesProjectPath = path
		if let path
		{
			files.runtime.switchRoot(path)
		}
		else
		{
			files.runtime.clearRoot()
		}
	}

	func openFilesToolTab()
	{
		configureToolsPaneClosing()
		filesWereOpened = true
		let snapshot = coordinator?.currentSnapshot ?? currentStore.currentSnapshot
		let target = WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		)
		updateFilesProject(target: target)
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

	private func publishFileTabs(_ state: FileViewerState)
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
		inspector.toolsTabs.updateFileTabs(
			presentations: presentations,
			selectedID: state.selectedDocumentID,
			controller: files
		)
	}

	private func enqueueFileClose(_ id: UUID)
	{
		guard !fileCloseRequests.contains(id), !fileCloseQueue.contains(id)
		else
		{
			return
		}
		fileCloseQueue.append(id)
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
				await closeFileTab(next)
			}
			fileClosePumpRunning = false
			fileClosePumpTask = nil
		}
	}

	private func closeFileTab(_ id: UUID) async
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
		let result = await files.runtime.close(
			id,
			choice: .save
		)
		guard case .decisionRequired(let failure) = result,
				let captured = files.runtime.state.documents.first(where:
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
		), files.runtime.state.documents.contains(where:
			{
				$0.id == id && $0.editRevision == captured.editRevision && $0.isDirty
			})
		{
			_ = await files.runtime.close(
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

	private func performFileSettlement() async -> Bool
	{
		if let fileClosePumpTask
		{
			await fileClosePumpTask.value
		}
		let failures = await files.runtime.flushAll()
		guard !failures.isEmpty
		else
		{
			return true
		}
		let captured = files.runtime.state.documents.filter
		{
			failures[$0.id] != nil && $0.isDirty
		}.map
		{
			($0.id, $0.editRevision)
		}
		guard shouldDiscardFiles(
			ids: captured.map(\.0),
			failure: failures.values.first,
			isWindowClosing: true
		)
		else
		{
			return false
		}
		let currentDocuments = files.runtime.state.documents
		guard captured.allSatisfy(
			{
				item in
				currentDocuments.contains(where:
					{
						$0.id == item.0 && $0.editRevision == item.1
					})
			}
		)
		else
		{
			return false
		}
		for (id, _) in captured
		{
			guard let current = files.runtime.state.documents.first(where:
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
			_ = await files.runtime.close(
				id,
				choice: .discard
			)
		}
		return true
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
