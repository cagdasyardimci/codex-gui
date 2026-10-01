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
		if textView === composer, handleSlashCommandKey(commandSelector)
		{
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

	func loadFileIndex(for path: String?)
	{
		indexTask?.cancel()
		indexProjectPath = path
		fileIndex = nil
		guard let path
		else
		{
			return
		}
		indexTask = Task
		{
			[weak self] in
			let index = await Task.detached(priority: .userInitiated)
			{
				ProjectFileIndex.load(projectPath: path)
			}.value
			guard let self, !Task.isCancelled, self.indexProjectPath == path
			else
			{
				return
			}
			self.fileIndex = index
			self.updateFileResults(query: self.fileSearchField?.stringValue ?? "")
		}
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
			characterBeforeMarker.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
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
		presentFileSearch(
			query: query,
			focusField: false
		)
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
		let searchField = NSSearchField()
		searchField.placeholderString = "Search project files"
		searchField.delegate = self
		searchField.setAccessibilityLabel("Search project files")

		let resultsStack = NSStackView()
		resultsStack.orientation = .vertical
		resultsStack.alignment = .leading
		resultsStack.spacing = 2
		resultsStack.translatesAutoresizingMaskIntoConstraints = false

		let resultsScrollView = NSScrollView()
		resultsScrollView.documentView = resultsStack
		resultsScrollView.hasVerticalScroller = true
		resultsStack.widthAnchor.constraint(
			equalTo: resultsScrollView.contentView.widthAnchor
		).isActive = true

		let container = NSView()
		searchField.translatesAutoresizingMaskIntoConstraints = false
		resultsScrollView.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(searchField)
		container.addSubview(resultsScrollView)
		NSLayoutConstraint.activate([
			searchField.topAnchor.constraint(
				equalTo: container.topAnchor,
				constant: 8
			),
			searchField.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: 8
			),
			searchField.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -8
			),
			resultsScrollView.topAnchor.constraint(
				equalTo: searchField.bottomAnchor,
				constant: 6
			),
			resultsScrollView.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: 8
			),
			resultsScrollView.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -8
			),
			resultsScrollView.bottomAnchor.constraint(
				equalTo: container.bottomAnchor,
				constant: -8
			),
		])

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

	private func updateFileResults(query: String)
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
		guard let fileIndex
		else
		{
			stack.addArrangedSubview(NSTextField(labelWithString: "Searching project files…"))
			return
		}
		let results = fileIndex.search(query)
		if results.isEmpty
		{
			stack.addArrangedSubview(NSTextField(labelWithString: "No matching files"))
		}
		for path in results
		{
			let button = NSButton(
				title: path,
				target: self,
				action: #selector(chooseFileResult(_:))
			)
			button.identifier = NSUserInterfaceItemIdentifier(path)
			button.bezelStyle = .inline
			button.alignment = .left
			button.setAccessibilityLabel("Attach project file \(path)")
			stack.addArrangedSubview(button)
		}
	}

	@objc private func chooseFileResult(_ sender: NSButton)
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
			onDraftChange?(composer.string)
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
		let receiveAttachment: (ComposerContextItem) -> Void =
		{
			[weak self] item in
			guard let self, self.selectionGeneration == generation
			else
			{
				return
			}
			self.onAddContext?(item)
		}

		return receiveAttachment
	}

	func attachImage(
		_ image: NSImage,
		title: String,
		receiver: ((ComposerContextItem) -> Void)? = nil
	)
	{
		do
		{
			let item = try DraftImageStore().importImage(
				image,
				title: title
			)
			if let receiver
			{
				receiver(item)
			}
			else
			{
				onAddContext?(item)
			}
		}
		catch
		{
			showContextError(error.localizedDescription)
		}
	}

	@objc private func chooseImage()
	{
		guard let window = view.window
		else
		{
			return
		}
		let generation = selectionGeneration
		let receiveAttachment = makeContextAttachmentReceiver()
		let panel = NSOpenPanel()
		panel.prompt = "Attach Image"
		panel.canChooseFiles = true
		panel.canChooseDirectories = false
		panel.allowsMultipleSelection = false
		panel.allowedContentTypes = [.png, .jpeg, .heic, .webP, .gif, .tiff]
		panel.beginSheetModal(for: window)
		{
			[weak self] response in
			guard response == .OK, self?.selectionGeneration == generation, let url = panel.url,
					let image = NSImage(contentsOf: url)
			else
			{
				return
			}
			self?.attachImage(
				image,
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

	@objc private func chooseCodeRange()
	{
		guard let window = view.window, let projectPath
		else
		{
			return
		}
		let generation = selectionGeneration
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
			let project = URL(fileURLWithPath: projectPath).standardizedFileURL
				.resolvingSymlinksInPath()
			let file = url.standardizedFileURL.resolvingSymlinksInPath()
			guard file.path.hasPrefix(project.path + "/")
			else
			{
				self.showContextError("Choose a file inside the current project.")
				return
			}
			do
			{
				let data = try Data(contentsOf: file)
				guard data.count <= 500_000, let contents = String(
					data: data,
					encoding: .utf8
				)
				else
				{
					self.showContextError("Choose a UTF-8 text file under 500 KB.")
					return
				}
				let relative = String(file.path.dropFirst(project.path.count + 1))
				self.presentCodeSelection(
					path: relative,
					contents: contents
				)
			}
			catch
			{
				self.showContextError(error.localizedDescription)
			}
		}
	}

	private func presentCodeSelection(
		path: String,
		contents: String
	)
	{
		guard let window = view.window
		else
		{
			return
		}
		let generation = selectionGeneration
		let receiveAttachment = makeContextAttachmentReceiver()
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
					self.selectionGeneration == generation
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
