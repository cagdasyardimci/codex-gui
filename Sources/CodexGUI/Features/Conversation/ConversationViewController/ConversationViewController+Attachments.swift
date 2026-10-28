import AppKit
import UniformTypeIdentifiers

// Project-file completion and attachment sheets, scoped to the captured draft lifetime.
@MainActor
extension ConversationViewController
{
	func controlTextDidChange(_ notification: Notification)
	{
		guard notification.object as? NSSearchField === fileSearchField
		else
		{
			return
		}
		updateFileResults(query: fileSearchField?.stringValue ?? "")
	}

	func textView(
		_ textView: NSTextView,
		doCommandBy commandSelector: Selector
	) -> Bool
	{
		if textView === composer,
			handleMentionMenuKey(commandSelector) || handleSlashCommandKey(commandSelector)
		{
			return true
		}
		if textView === composer, !composer.hasMarkedText(),
			fileSearchPopover?.isShown != true,
			commandSelector == #selector(NSResponder.insertNewline(_:)),
			composer.string.rangeOfCharacter(from: .newlines) == nil
		{
			if imageImportTasks.isEmpty
			{
				onSend?()
			}
			return true
		}
		guard textView === composer, !composer.hasMarkedText(), fileSearchPopover?.isShown == true
		else
		{
			return false
		}
		if commandSelector == #selector(NSResponder.insertNewline(_:)),
			let completionRange,
			NSMaxRange(completionRange) <= (composer.string as NSString).length,
			let first = fileResultsStack?.arrangedSubviews.compactMap(
			{
				$0 as? NSButton
			}
			).first
		{
			chooseFileResult(first)
			return true
		}
		if commandSelector == #selector(NSResponder.cancelOperation(_:))
		{
			fileSearchPopover?.close()
			fileSelectionReceiver = nil
			completionRange = nil
			return true
		}
		return false
	}

	func control(
		_ control: NSControl,
		textView: NSTextView,
		doCommandBy commandSelector: Selector
	) -> Bool
	{
		guard control === fileSearchField, fileSearchPopover?.isShown == true
		else
		{
			return false
		}
		if commandSelector == #selector(NSResponder.insertNewline(_:)),
			let first = fileResultsStack?.arrangedSubviews.compactMap(
			{
				$0 as? NSButton
			}
			).first
		{
			chooseFileResult(first)
			return true
		}
		return false
	}

	func showAtFileCompletionIfNeeded()
	{
		let text = composer.string as NSString
		let cursor = composer.selectedRange().location
		guard cursor != NSNotFound, cursor <= text.length
		else
		{
			return
		}
		let prefix = text.substring(to: cursor) as NSString
		let marker = prefix.range(
			of: "@",
			options: .backwards
		)
		guard marker.location != NSNotFound
		else
		{
			if fileSearchWasCompletion
			{
				fileSearchPopover?.close()
				mentionPopover?.close()
			}
			completionRange = nil
			return
		}
		let characterBeforeMarker =
			marker.location == 0
				? " "
				: prefix.substring(
					with: NSRange(
						location: marker.location - 1,
						length: 1
					)
				)
		let query = prefix.substring(from: marker.location + 1)
		let markerStartsToken =
			characterBeforeMarker
				.rangeOfCharacter(from: .whitespacesAndNewlines) != nil || characterBeforeMarker ==
				"\u{FFFC}"
		let queryContainsTokenSeparator = query.contains(where:
			{
				$0.isWhitespace || $0 == "@"
			})
		guard markerStartsToken, !queryContainsTokenSeparator
		else
		{
			if fileSearchWasCompletion
			{
				fileSearchPopover?.close()
				mentionPopover?.close()
			}
			completionRange = nil
			return
		}
		completionRange = NSRange(
			location: marker.location,
			length: cursor - marker.location
		)
		fileSearchWasCompletion = true
		fileSelectionReceiver = nil
		presentMentionMenu(query: query)
	}

	@objc func openFileSearch()
	{
		fileSelectionReceiver = nil
		completionRange = nil
		fileSearchWasCompletion = false
		presentFileSearch(
			query: "",
			focusField: true
		)
	}

	private func presentFileSearch(
		query: String,
		focusField: Bool
	)
	{
		guard projectPath != nil
		else
		{
			return
		}
		if fileSearchPopover == nil
		{
			configureFileSearchPopover()
		}
		fileSearchField?.stringValue = query
		updateFileResults(query: query)
		if fileSearchPopover?.isShown != true
		{
			let anchor = focusField ? addContextButton : composerScrollView
			fileSearchPopover?.show(
				relativeTo: anchor.bounds,
				of: anchor,
				preferredEdge: .maxY
			)
		}
		if focusField, let field = fileSearchField
		{
			view.window?.makeFirstResponder(field)
		}
	}

	private func configureFileSearchPopover()
	{
		let searchField = DesktopSearchField()
		searchField.configureSearch(
			placeholder: "Search project files",
			accessibilityLabel: "Search project files",
			delegate: self
		)

		let resultsStack = NSStackView()
		let container = DesktopSearchOverlayView(
			presentation: .attachments,
			search: searchField,
			results: resultsStack
		)

		let controller = NSViewController()
		controller.view = container
		let popover = NSPopover()
		popover.contentViewController = controller
		popover.contentSize = NSSize(
			width: 390,
			height: 290
		)
		popover.behavior = .transient

		fileSearchField = searchField
		fileResultsStack = resultsStack
		fileSearchPopover = popover
	}

	func updateFileResults(query: String)
	{
		guard let stack = fileResultsStack
		else
		{
			return
		}
		for view in stack.arrangedSubviews
		{
			stack.removeArrangedSubview(view)
			view.removeFromSuperview()
		}
		guard let fileIndex = fileIndexRuntime.index
		else
		{
			return
		}
		let results = fileIndex.search(query)
		for path in results
		{
			let button = DesktopSearchResultButton.attachment(
				path: path,
				target: self,
				action: #selector(chooseFileResult(_:))
			)
			stack.addArrangedSubview(button)
		}
	}

	@objc func chooseFileResult(_ sender: NSButton)
	{
		guard let path = sender.identifier?.rawValue
		else
		{
			return
		}
		if let completionRange, NSMaxRange(completionRange) <= (composer.string as NSString).length
		{
			composer.textStorage?.replaceCharacters(
				in: completionRange,
				with: ""
			)
			onDraftChange?(composer.draftText)
			updateComposerHeight()
		}
		self.completionRange = nil
		fileSearchPopover?.close()
		let receiver = fileSelectionReceiver ?? onAddContext
		fileSelectionReceiver = nil
		receiver?(
			ComposerContextItem(
				kind: .fileReference,
				title: URL(fileURLWithPath: path).lastPathComponent,
				path: path
			)
		)
		view.window?.makeFirstResponder(composer)
	}

	/// A picker or code sheet may finish after the user opens another task.
	/// Its receiver expires on every project or conversation selection change.
	func makeContextAttachmentReceiver() -> (ComposerContextItem) -> Void
	{
		let generation = selectionGeneration
		let receiver = onAddContext
		let receiveAttachment: (ComposerContextItem) -> Void =
		{
			[weak self] item in
			guard let self, self.selectionGeneration == generation
			else
			{
				return
			}
			receiver?(item)
		}

		return receiveAttachment
	}

	func attachImage(
		_ image: NSImage,
		title: String,
		receiver: ((ComposerContextItem) -> Bool)? = nil
	)
	{
		guard let source = DraftImageSource(image: image)
		else
		{
			showContextError(DraftImageStoreError.unsupported.localizedDescription)
			return
		}
		attachImage(
			source,
			title: title,
			receiver: receiver
		)
	}

	func attachImage(
		_ source: DraftImageSource,
		title: String,
		receiver: ((ComposerContextItem) -> Bool)? = nil
	)
	{
		let generation = selectionGeneration
		let receiveAttachment = receiver ?? makeImageAttachmentReceiver()
		let store = draftImageStore
		let requestID = UUID()
		let previousImport = lastImageImportID.flatMap
		{
			imageImportTasks[$0]
		}
		let task = Task
		{
			[weak self] in
			defer
			{
				self?.finishImageImport(requestID)
			}
			// Serialize preparation and delivery to retain repeated paste/drop order.
			await previousImport?.value
			do
			{
				try Task.checkCancellation()
				let imageURL = try await store.importImage(source)
				guard !Task.isCancelled, let self, self.selectionGeneration == generation
				else
				{
					await store.discardImportedCopy(imageURL)
					return
				}
				let item = ComposerContextItem(
					kind: .image,
					title: title,
					path: imageURL.path
				)
				if !receiveAttachment(item)
				{
					await store.discardImportedCopy(imageURL)
				}
			}
			catch
			{
				guard !(error is CancellationError), !Task.isCancelled,
						let self, self.selectionGeneration == generation
				else
				{
					return
				}
				self.showContextError(error.localizedDescription)
			}
		}
		imageImportTasks[requestID] = task
		lastImageImportID = requestID
		updateSendState()
	}

	private func makeImageAttachmentReceiver() -> (ComposerContextItem) -> Bool
	{
		let generation = selectionGeneration
		let receiveAttachment = onImportImageContext
		let receiveImage: (ComposerContextItem) -> Bool =
		{
			[weak self] item in
			guard let self, self.selectionGeneration == generation
			else
			{
				return false
			}
			return receiveAttachment?(item) ?? false
		}
		return receiveImage
	}

	func cancelImageImports()
	{
		for task in imageImportTasks.values
		{
			task.cancel()
		}
		imageImportTasks.removeAll()
		lastImageImportID = nil
		updateSendState()
	}

	private func finishImageImport(_ requestID: UUID)
	{
		imageImportTasks[requestID] = nil
		if lastImageImportID == requestID
		{
			lastImageImportID = nil
		}
		updateSendState()
	}

	@objc func chooseImage()
	{
		guard let window = view.window
		else
		{
			return
		}
		let generation = selectionGeneration
		let receiveAttachment = makeImageAttachmentReceiver()
		let panel = NSOpenPanel()
		panel.prompt = "Attach Image"
		panel.canChooseFiles = true
		panel.canChooseDirectories = false
		panel.allowsMultipleSelection = false
		panel.allowedContentTypes = [.png, .jpeg, .heic, .webP, .gif, .tiff]
		panel.beginSheetModal(for: window)
		{
			[weak self] response in
			guard response == .OK, self?.selectionGeneration == generation, let url = panel.url
			else
			{
				return
			}
			self?.attachImage(
				.file(url),
				title: url.lastPathComponent,
				receiver: receiveAttachment
			)
		}
	}

	@objc func chooseContextAction()
	{
		let selected = addContextButton.indexOfSelectedItem
		addContextButton.selectItem(at: 0)
		switch selected
		{
		case 1: openFileSearch()
		case 2: chooseImage()
		case 3: chooseCodeRange()
		case 4: choosePath()
		case 5: inspectRequestContext()
		default: break
		}
	}

	@objc func chooseCodeRange()
	{
		guard let window = view.window, let projectPath
		else
		{
			return
		}
		let generation = selectionGeneration
		let receiveAttachment = makeContextAttachmentReceiver()
		let panel = NSOpenPanel()
		panel.prompt = "Select Code"
		panel.directoryURL = URL(fileURLWithPath: projectPath)
		panel.canChooseFiles = true
		panel.canChooseDirectories = false
		panel.beginSheetModal(for: window)
		{
			[weak self] response in
			guard response == .OK, let url = panel.url, let self,
					self.selectionGeneration == generation
			else
			{
				return
			}
			Task
			{
				[weak self] in
				await self?.loadCodeSelection(
					file: url,
					project: URL(fileURLWithPath: projectPath),
					generation: generation,
					window: window,
					receiveAttachment: receiveAttachment
				)
			}
		}
	}

	func loadCodeSelection(
		file: URL,
		project: URL,
		generation: Int,
		window: NSWindow,
		receiveAttachment: @escaping (ComposerContextItem) -> Void,
		readFile: @Sendable (
			URL,
			URL
		) async throws -> ComposerCodeFile =
			ComposerCodeFileReader.read
	) async
	{
		do
		{
			let selected = try await readFile(
				file,
				project
			)
			guard selectionGeneration == generation, view.window === window, window.isVisible
			else
			{
				return
			}
			presentCodeSelection(
				path: selected.relativePath,
				contents: selected.contents,
				window: window,
				generation: generation,
				receiveAttachment: receiveAttachment
			)
		}
		catch
		{
			guard selectionGeneration == generation, view.window === window, window.isVisible
			else
			{
				return
			}
			if let failure = error as? FileViewerFailure
			{
				switch failure
				{
				case .invalidPath:
					showContextError("Choose a regular file inside the current project.")
				case .tooLarge, .unsupportedEncoding, .binary:
					showContextError("Choose a UTF-8 text file under 500 KB.")
				default:
					showContextError("This file could not be read. Choose another file.")
				}
			}
			else if !(error is CancellationError)
			{
				showContextError(error.localizedDescription)
			}
		}
	}

	private func presentCodeSelection(
		path: String,
		contents: String,
		window: NSWindow,
		generation: Int,
		receiveAttachment: @escaping (ComposerContextItem) -> Void
	)
	{
		let selection = ScrollableTextPreview.make(
			text: contents,
			size: NSSize(
				width: 540,
				height: 300
			),
			font: .monospacedSystemFont(
				ofSize: 12,
				weight: .regular
			),
			accessibilityLabel: "Select code lines from \(path)"
		)
		let alert = NSAlert()
		alert.messageText = "Select code in \(path)"
		alert.informativeText =
			"Select a code range in the preview, then attach it with its path and line numbers."
		alert.accessoryView = selection.scrollView
		alert.addButton(withTitle: "Attach Selection")
		alert.addButton(withTitle: "Cancel")
		alert.beginSheetModal(for: window)
		{
			[weak self] response in
			guard response == .alertFirstButtonReturn, let self,
					self.selectionGeneration == generation, self.view.window === window,
					window.isVisible
			else
			{
				return
			}
			guard
				let item = CodeRangeSelection.item(
					path: path,
					contents: contents,
					selectedRange: selection.textView.selectedRange()
				)
			else
			{
				self.showContextError("Select up to 30 KB of code before attaching.")
				return
			}
			receiveAttachment(item)
		}
	}

	private func showContextError(_ message: String)
	{
		guard let window = view.window
		else
		{
			return
		}
		let alert = NSAlert()
		alert.messageText = "Could not attach context"
		alert.informativeText = message
		alert.addButton(withTitle: "OK")
		alert.beginSheetModal(for: window)
	}

}
