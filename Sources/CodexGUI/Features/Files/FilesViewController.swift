import AppKit

@MainActor
final class FilesViewController: NSViewController
{
	let runtime: FileViewerRuntime
	let navigator = FileNavigatorViewController()
	let document = FileDocumentViewController()
	let breadcrumb = FileBreadcrumbView()
	let quickOpen = FileQuickOpenController()
	let contentSearch = FileSearchController()
	var onStateChange: ((FileViewerState) -> Void)?
	var captureAttachmentReceiver: (() -> ((ComposerContextItem) -> Void)?)?

	private let documentColumn = DesktopSurface(AppKitColorTokens.toolsCanvas)
	private var split: ViewerNavigatorSplitView?
	private let toolbar = NSView()
	private let toolbarActions = NSStackView()
	private let navigatorButton = ViewerToolbarButton(
		title: "",
		target: nil,
		action: nil
	)
	private let searchButton = ViewerToolbarButton(
		title: "",
		target: nil,
		action: nil
	)

	private let sourceButton = ViewerToolbarButton(
		title: "View source",
		target: nil,
		action: nil
	)

	private let actionsButton = ViewerToolbarButton(
		title: "Open",
		target: nil,
		action: nil
	)
	private var readingStates: [UUID: FileSourceReadingState] = [:]
	private var readingDocumentID: UUID?
	private var pendingReadingRestore: UUID?
	private var activeSearch: SearchSurface?
	private var presentationVisible = false

	private enum SearchSurface
	{
		case quickOpen, content
	}

	init(runtime: FileViewerRuntime = FileViewerRuntime())
	{
		self.runtime = runtime
		super.init(
			nibName: nil,
			bundle: nil
		)
		bindCallbacks()
		document.showsHeader = false
		document.markdownImageLoader =
		{
			location, path, maximumPixelSize in
			let root = URL(fileURLWithPath: location.root).standardizedFileURL
			let imageURL: URL
			if let explicit = LocalAttachmentURL.resolve(path)
			{
				imageURL = explicit
			}
			else
			{
				guard !NSString(string: path).isAbsolutePath,
						!path.hasPrefix("//"), URL(string: path)?.scheme == nil
				else
				{
					return nil
				}
				imageURL = location.fileURL.deletingLastPathComponent()
					.appendingPathComponent(path).standardizedFileURL
			}
			let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
			guard imageURL.path.hasPrefix(prefix)
			else
			{
				return nil
			}
			let relativePath = String(imageURL.path.dropFirst(prefix.count))
			let imageLocation = FileLocation(
				root: location.root,
				relativePath: relativePath
			)
			guard let read = try? await FileSystemFileViewerService().read(at: imageLocation),
					case .image(let data) = read.content
			else
			{
				return nil
			}
			return await SourceThumbnailLoader.image(
				data: data,
				maximumPixelSize: maximumPixelSize
			)
		}
		runtime.onChange =
		{
			[weak self] state in self?.render(state)
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func loadView()
	{
		let root = DesktopSurface(AppKitColorTokens.canvas)
		view = root
		addChild(navigator)
		addChild(document)

		breadcrumb.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		breadcrumb.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		navigatorButton.image = FileViewerIcons.image(.navigator)
		navigatorButton.setButtonType(.toggle)
		navigatorButton.imagePosition = .imageOnly
		navigatorButton.alternateImage = navigatorButton.image
		navigatorButton.showsSelection = true
		navigatorButton.state = .on
		navigatorButton.setAccessibilityLabel("Toggle file navigator")
		navigatorButton.target = self
		navigatorButton.action = #selector(toggleNavigator)
		searchButton.target = self
		searchButton.action = #selector(showContentSearch)
		searchButton.image = FileViewerIcons.image(.fileSearch)
		searchButton.imagePosition = .imageOnly
		searchButton.setAccessibilityLabel("Search files")
		for button in [searchButton, navigatorButton]
		{
			NSLayoutConstraint.activate([
				button.widthAnchor.constraint(equalToConstant: 34),
				button.heightAnchor.constraint(equalTo: button.widthAnchor),
			])
		}
		sourceButton.target = self
		sourceButton.action = #selector(toggleSource)
		actionsButton.imagePosition = .imageLeading
		actionsButton.trailingImage = FileViewerIcons.image(
			.chevronDown,
			size: 12
		)
		actionsButton.target = self
		actionsButton.action = #selector(showFileActions)
		actionsButton.setAccessibilityLabel("Open file actions")
		searchButton.menu = makeSearchMenu()
		toolbarActions.orientation = .horizontal
		toolbarActions.distribution = .fill
		toolbarActions.alignment = .centerY
		toolbarActions.spacing = 6
		for button in [searchButton, sourceButton, navigatorButton, actionsButton]
		{
			toolbarActions.addArrangedSubview(button)
		}
		for child in [breadcrumb, toolbarActions]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			toolbar.addSubview(child)
		}
		NSLayoutConstraint.activate([
			breadcrumb.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
			breadcrumb.trailingAnchor.constraint(
				lessThanOrEqualTo: toolbarActions.leadingAnchor,
				constant: -8
			),
			breadcrumb.topAnchor.constraint(equalTo: toolbar.topAnchor),
			breadcrumb.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
			breadcrumb.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
			toolbarActions.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
			toolbarActions.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
		])

		root.addSubview(toolbar)
		documentColumn.addSubview(document.view)
		toolbar.translatesAutoresizingMaskIntoConstraints = false
		document.view.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			toolbar.leadingAnchor.constraint(
				equalTo: root.leadingAnchor,
				constant: 8
			),
			toolbar.trailingAnchor.constraint(
				equalTo: root.trailingAnchor,
				constant: -8
			),
			toolbar.topAnchor.constraint(
				equalTo: root.topAnchor,
				constant: 8
			),
			toolbar.heightAnchor.constraint(equalToConstant: 34),
			document.view.leadingAnchor.constraint(equalTo: documentColumn.leadingAnchor),
			document.view.trailingAnchor.constraint(equalTo: documentColumn.trailingAnchor),
			document.view.topAnchor.constraint(equalTo: documentColumn.topAnchor),
			document.view.bottomAnchor.constraint(equalTo: documentColumn.bottomAnchor),
		])

		let split = ViewerNavigatorSplitView(
			document: documentColumn,
			navigator: navigator.view
		)
		self.split = split
		root.addSubview(split)
		split.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			split.leadingAnchor.constraint(equalTo: root.leadingAnchor),
			split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
			split.topAnchor.constraint(
				equalTo: toolbar.bottomAnchor,
				constant: 2
			),
			split.bottomAnchor.constraint(equalTo: root.bottomAnchor),
		])
		render(
			runtime.state,
			publish: false
		)
	}

	private var availableWidth: CGFloat
	{
		min(
			view.bounds.width,
			view.superview?.bounds.width ?? view.bounds.width
		)
	}

	override func viewDidLayout()
	{
		super.viewDidLayout()
		updateToolbarControls()
	}

	func open(
		_ location: FileLocation,
		retained: Bool = false,
		line: Int? = nil
	)
	{
		runtime.open(
			location,
			retained: retained,
			line: line
		)
	}

	func focusFind()
	{
		document.focusFind()
		updateToolbarControls()
	}

	func setNavigatorVisible(_ visible: Bool)
	{
		guard let split, split.isNavigatorVisible != visible
		else
		{
			return
		}
		split.setNavigatorVisible(visible)
		navigatorButton.state = visible ? .on : .off
	}

	func setPresentationVisible(_ visible: Bool)
	{
		let wasVisible = presentationVisible
		presentationVisible = visible
		if visible, !wasVisible
		{
			runtime.refreshSelectedIfClean()
		}
		guard !visible, activeSearch != nil
		else
		{
			return
		}
		quickOpen.dismiss()
		contentSearch.dismiss()
		activeSearch = nil
	}

	func presentQuickOpen()
	{
		guard let window = view.window, runtime.state.activeRoot != nil
		else
		{
			return
		}
		activeSearch = .quickOpen
		navigator.showsFilenameResults = false
		navigator.render(runtime.state)
		quickOpen.render(runtime.state)
		quickOpen.present(in: window)
		quickOpen.focusSearch()
	}

	func presentContentSearch()
	{
		guard let window = view.window, runtime.state.activeRoot != nil
		else
		{
			return
		}
		activeSearch = .content
		navigator.showsFilenameResults = false
		navigator.render(runtime.state)
		contentSearch.render(runtime.state)
		contentSearch.present(in: window)
		contentSearch.focusSearch()
	}

	private func render(
		_ state: FileViewerState,
		publish: Bool = true
	)
	{
		guard isViewLoaded
		else
		{
			if publish
			{
				onStateChange?(state)
			}
			return
		}
		let selectionChanged = readingDocumentID != state.selectedDocumentID
		if selectionChanged
		{
			if let old = readingDocumentID
			{
				readingStates[old] = document.captureReadingState()
			}
			readingDocumentID = state.selectedDocumentID
			pendingReadingRestore = state.selectedDocumentID
		}
		if state.selectedDocument?.requestedLine != nil
		{
			pendingReadingRestore = nil
		}
		navigator.render(state)
		document.render(state.selectedDocument)
		updateToolbarControls()
		actionsButton.isEnabled = state.selectedDocument != nil
		updateOpenIcon()
		document.pruneSourceViews(openIDs: Set(state.documents.map(\.id)))
		breadcrumb.render(
			location: state.selectedDocument?.location,
			state: state
		)
		if let selected = pendingReadingRestore,
			let current = state.selectedDocument, current.id == selected,
			current.currentText != nil
		{
			pendingReadingRestore = nil
			if let reading = readingStates[selected]
			{
				document.restoreReadingState(reading)
			}
		}
		switch activeSearch
		{
		case .quickOpen: quickOpen.render(state)
		case .content: contentSearch.render(state)
		case nil: break
		}
		if publish
		{
			onStateChange?(state)
		}
	}

	private func bindCallbacks()
	{
		navigator.onRequestDirectory =
		{
			[weak self] in self?.runtime.listDirectory($0)
		}
		navigator.onOpenFile =
		{
			[weak self] location, retained in self?.open(
				location,
				retained: retained
			)
		}
		navigator.onChooseRoot =
		{
			[weak self] in self?.chooseRoot()
		}
		navigator.onFilter =
		{
			[weak self] query in
			guard let self, self.activeSearch == nil
			else
			{
				return
			}
			if query.isEmpty
			{
				self.runtime.cancelSearch()
			}
			else
			{
				self.runtime.filenameSearch(query: query)
			}
		}
		navigator.onFileContextMenu =
		{
			[weak self] location in
			guard let self
			else
			{
				return nil
			}
			let item = self.runtime.state.documents.first(where:
				{
					$0.location == location
				}) ?? FileViewerDocument(
				id: UUID(),
				location: location,
				isRetained: false
			)
			return self.document.makeActionsMenu(
				for: item,
				captureAttachmentReceiver: self.captureAttachmentReceiver
			)
		}
		breadcrumb.onNavigate =
		{
			[weak self] location in self?.navigator.reveal(location)
		}
		breadcrumb.onOpenFile =
		{
			[weak self] location in self?.open(
				location,
				retained: true
			)
		}
		breadcrumb.onRequestDirectory =
		{
			[weak self] in self?.runtime.listDirectory($0)
		}
		quickOpen.onSearch =
		{
			[weak self] in self?.runtime.filenameSearch(query: $0)
		}
		quickOpen.onCancelSearch =
		{
			[weak self] in self?.runtime.cancelSearch()
		}
		quickOpen.onChoose =
		{
			[weak self] location in self?.open(
				location,
				retained: true
			)
		}
		quickOpen.onDismiss =
		{
			[weak self] in self?.resumeNavigatorSearch()
		}
		contentSearch.onSearch =
		{
			[weak self] query, mask in self?.runtime.contentSearch(
				query: query,
				mask: mask
			)
		}
		contentSearch.onCancelSearch =
		{
			[weak self] in self?.runtime.cancelSearch()
		}
		contentSearch.onChoose =
		{
			[weak self] result in
			self?.open(
				result.location,
				retained: true,
				line: result.lineNumber
			)
		}
		contentSearch.onDismiss =
		{
			[weak self] in self?.resumeNavigatorSearch()
		}
		document.onEdit =
		{
			[weak self] id, text in self?.runtime.edit(
				id,
				text: text
			)
		}
		document.onRetry =
		{
			[weak self] in self?.runtime.refresh($0)
		}
		document.onSave =
		{
			[weak self] id in Task
			{
				_ = await self?.runtime.save(id)
			}
		}
		document.onUseDisk =
		{
			[weak self] id in Task
			{
				await self?.runtime.useDisk(id)
			}
		}
		document.onKeepLocal =
		{
			[weak self] id in Task
			{
				_ = await self?.runtime.keepLocal(id)
			}
		}
		document.onContinueEditing =
		{
			[weak self] id in Task
			{
				_ = await self?.runtime.continueEditing(id)
			}
		}
		document.onOpenLocation =
		{
			[weak self] location, line in self?.open(
				location,
				retained: true,
				line: line
			)
		}
		document.onAcknowledgeLineRequest =
		{
			[weak self] id, generation in
			self?.runtime.acknowledgeLineRequest(
				id,
				generation: generation
			)
		}
		document.captureAttachmentReceiver =
		{
			[weak self] in self?.captureAttachmentReceiver?()
		}
	}

	private func chooseRoot()
	{
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.allowsMultipleSelection = false
		panel.prompt = "Open Folder"
		panel.directoryURL = runtime.state.activeRoot.map
		{
			URL(fileURLWithPath: $0)
		}
		if panel.runModal() == .OK, let url = panel.url
		{
			runtime.switchRoot(url.path)
		}
	}

	private func resumeNavigatorSearch()
	{
		activeSearch = nil
		navigator.showsFilenameResults = true
		runtime.cancelSearch()
		let query = navigator.currentFilterQuery
		if presentationVisible, !query.isEmpty
		{
			runtime.filenameSearch(query: query)
		}
		else if isViewLoaded
		{
			navigator.render(runtime.state)
		}
	}

	@objc private func toggleNavigator()
	{
		setNavigatorVisible(!(split?.isNavigatorVisible ?? true))
	}
	@objc private func showQuickOpen()
	{
		presentQuickOpen()
	}
	@objc private func showContentSearch()
	{
		presentContentSearch()
	}
	@objc private func toggleSource()
	{
		document.setSourceVisible(!document.isShowingSource)
		updateToolbarControls()
	}
	@objc private func showFileActions()
	{
		guard runtime.state.selectedDocument != nil
		else
		{
			return
		}
		let menu = makeFileActionsMenu()
		menu.popUp(
			positioning: nil,
			at: NSPoint(
				x: 0,
				y: actionsButton.bounds.height
			),
			in: actionsButton
		)
	}

	func makeFileActionsMenu() -> NSMenu
	{
		document.makeOpenMenu()
	}

	private func makeSearchMenu() -> NSMenu
	{
		let menu = NSMenu(title: "Search")
		for (title, action) in [("Search file contents", #selector(showContentSearch)),
								("Open file by name", #selector(showQuickOpen))]
		{
			let item = NSMenuItem(
				title: title,
				action: action,
				keyEquivalent: ""
			)
			item.target = self
			menu.addItem(item)
		}
		return menu
	}

	private func updateOpenIcon()
	{
		let application = EditorOpeningService().preferredApplication
			?? runtime.state.selectedDocument.flatMap
			{
				NSWorkspace.shared.urlForApplication(toOpen: $0.location.fileURL)
			}
		if let application
		{
			let icon = NSWorkspace.shared.icon(forFile: application.path)
			icon.size = NSSize(
				width: 16,
				height: 16
			)
			actionsButton.image = icon
		}
		else
		{
			actionsButton.image = FileViewerIcons.image(.externalOpen)
		}
	}

	private func updateToolbarControls()
	{
		let compact = availableWidth < 568
		let selected = runtime.state.selectedDocument
		actionsButton.isHidden = selected == nil
		let textReady = selected?.currentText != nil
		let supportsSourceAndPreview = selected.map
		{
			FileContentCapabilities(path: $0.location.relativePath).supportsSourceAndPreview
		} ?? false
		let modeTitle = document.isShowingSource ? "Preview" : "View source"
		sourceButton.title = compact ? "" : modeTitle
		sourceButton.image = compact
			? FileViewerIcons.image(document.isShowingSource ? .textFile : .configuration) : nil
		sourceButton.imagePosition = compact ? .imageOnly : .noImage
		sourceButton.setAccessibilityLabel(modeTitle)
		sourceButton.toolTip = modeTitle
		sourceButton.isHidden = !supportsSourceAndPreview || !textReady
	}
}
