import AppKit

@MainActor
private final class FileDocumentRootView: NSView
{
	override var isOpaque: Bool
	{
		true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		NSColor.textBackgroundColor.setFill()
		// AppKit may request drawing beyond bounds; never cover sibling toolbar controls.
		NSBezierPath(rect: bounds.intersection(dirtyRect)).fill()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}
}

/// A flipped document keeps short Markdown at the scroll view's top edge.
@MainActor
private final class FileMarkdownPreviewView: RichFilePreviewView
{
	override var isFlipped: Bool
	{
		true
	}
}

/// The scroll document exposes an extent without making metadata height a viewport minimum.
@MainActor
private final class FileMarkdownMetadataDocumentView: NSView
{
	override var isFlipped: Bool
	{
		true
	}
}

@MainActor
final class FileDocumentViewController: NSViewController
{
	var onEdit: ((UUID, String) -> Void)?
	var onRetry: ((UUID) -> Void)?
	var onSave: ((UUID) -> Void)?
	var onUseDisk: ((UUID) -> Void)?
	var onKeepLocal: ((UUID) -> Void)?
	var onContinueEditing: ((UUID) -> Void)?
	var onOpenLocation: ((FileLocation, Int?) -> Void)?
	var onAcknowledgeLineRequest: ((UUID, Int) -> Void)?
	var captureAttachmentReceiver: (() -> ((ComposerContextItem) -> Void)?)?
	var markdownImageLoader: (@Sendable (
		FileLocation,
		String,
		Int
	) async
		-> SourceThumbnailLoader.Thumbnail?)?
	var openingDestinations: @MainActor () -> [FileOpeningDestination] =
		FileOpeningDestinations.installed
	var openDestination: ((FileLocation, FileOpeningDestination) async throws -> Void)?
	var openDefaultApplication: ((FileLocation) throws -> Void)?
	var openGitHubURL: ((URL) -> Bool)?
	var openFolder: ((FileLocation) -> Void)?

	private var sourceViews: [UUID: FileSourceView] = [:]
	private let header = NSStackView()
	private let copyBar = NSView()
	private let copyMarkdownButton = DesktopHoverButton()
	private let titleLabel = NSTextField(labelWithString: "")
	private let modeButton = NSButton(
		title: "View source",
		target: nil,
		action: nil
	)
	private let wrapButton = NSButton(
		title: "Wrap lines",
		target: nil,
		action: nil
	)
	private let actionsButton = NSButton(
		title: "Actions",
		target: nil,
		action: nil
	)
	private let messageLabel = ViewerStatusView(message: "")
	private let emptyState = FileViewerEmptyStateView()
	private let statusLabel = NSTextField(wrappingLabelWithString: "")
	private let contentHolder = NSView()
	private var headerCollapsedHeight: NSLayoutConstraint?
	private var contentTrailing: NSLayoutConstraint?
	private var headerTrailing: NSLayoutConstraint?
	private var statusCollapsedHeight: NSLayoutConstraint?
	private let previewScroll = NSScrollView()
	private let previewContainer = NSStackView()
	private let metadataHolder = NSView()
	private let metadataScroll = NSScrollView()
	private let metadataDocument = FileMarkdownMetadataDocumentView()
	private var metadataView: MarkdownFileMetadataView?
	private var metadataHeight: NSLayoutConstraint?
	private var isUpdatingMetadataGeometry = false
	private var metadataLayoutTask: Task<Void, Never>?
	private var previewGeneration = UUID()
	private var copyBarTop: NSLayoutConstraint?
	private var current: FileViewerDocument?
	private var preview: RichFilePreviewView?
	private var showingSource = false
	private var wrapsLines = true
	private var previewBytes: Data?
	private var previewDocumentID: UUID?
	private var lastLineGeneration: [UUID: Int] = [:]

	private struct ActionSnapshot
	{
		let id: UUID
		let location: FileLocation
		let content: FileViewerContent?
	}

	private final class ActionContext: NSObject
	{
		let snapshot: ActionSnapshot
		let receiver: ((ComposerContextItem) -> Void)?

		init(
			snapshot: ActionSnapshot,
			receiver: ((ComposerContextItem) -> Void)?
		)
		{
			self.snapshot = snapshot
			self.receiver = receiver
		}
	}

	var showsHeader = true
	{
		didSet
		{
			if isViewLoaded
			{
				header.isHidden = !showsHeader
				headerTrailing?.isActive = showsHeader
				headerCollapsedHeight?.isActive = !showsHeader
			}
		}
	}

	private var sourceIsVisible: Bool
	{
		current.map
		{
			let capabilities = FileContentCapabilities(path: $0.location.relativePath)
			return capabilities.hasSource && (showingSource || !capabilities.hasRichPreview)
		} ?? true
	}

	deinit
	{
		NotificationCenter.default.removeObserver(self)
	}

	var isShowingSource: Bool
	{
		showingSource
	}

	override func loadView()
	{
		let root = FileDocumentRootView()
		root.wantsLayer = true
		view = root
		header.orientation = .horizontal
		header.spacing = 8
		header.edgeInsets = NSEdgeInsets(
			top: 8,
			left: 12,
			bottom: 8,
			right: 12
		)
		header.addArrangedSubview(titleLabel)
		header.addArrangedSubview(NSView())
		for button in [modeButton, wrapButton, actionsButton]
		{
			button.bezelStyle = .rounded
			header.addArrangedSubview(button)
		}
		modeButton.target = self
		modeButton.action = #selector(toggleMode)
		wrapButton.target = self
		wrapButton.action = #selector(toggleWrap)
		actionsButton.target = self
		actionsButton.action = #selector(showActions)
		copyMarkdownButton.bezelStyle = .texturedRounded
		copyMarkdownButton.isBordered = false
		copyMarkdownButton.imagePosition = .imageOnly
		copyMarkdownButton.contentTintColor = AppKitColorTokens.secondaryText
		copyMarkdownButton.image = DesktopIcons.image(
			.copy,
			size: 16,
			accessibilityDescription: "Copy Markdown"
		)
		copyMarkdownButton.toolTip = "Copy Markdown"
		copyMarkdownButton.setAccessibilityLabel("Copy Markdown")
		copyMarkdownButton.target = self
		copyMarkdownButton.action = #selector(copyCurrentMarkdown)
		copyBar.addSubview(copyMarkdownButton)
		copyMarkdownButton.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			copyMarkdownButton.trailingAnchor.constraint(
				equalTo: copyBar.trailingAnchor,
				constant: -8
			),
			copyMarkdownButton.centerYAnchor.constraint(equalTo: copyBar.centerYAnchor),
			copyMarkdownButton.widthAnchor.constraint(equalToConstant: 28),
			copyMarkdownButton.heightAnchor.constraint(equalToConstant: 28)
		])
		statusLabel.textColor = .secondaryLabelColor
		statusLabel.lineBreakMode = .byWordWrapping
		statusLabel.isHidden = true
		previewScroll.hasVerticalScroller = true
		previewScroll.autohidesScrollers = true
		previewScroll.drawsBackground = false
		previewContainer.orientation = .vertical
		previewContainer.alignment = .width
		previewContainer.spacing = LayoutTokens.FileMarkdown.metadataBottomSpacing
		previewContainer.edgeInsets = NSEdgeInsets(
			top: LayoutTokens.FileMarkdown.contentInset,
			left: 0,
			bottom: 0,
			right: 0
		)
		let metadataInset = LayoutTokens.FileMarkdown.contentInset
		metadataHolder.frame = NSRect(
			x: 0,
			y: 0,
			width: metadataInset * 2,
			height: 0
		)
		metadataScroll.frame = NSRect(
			x: metadataInset,
			y: 0,
			width: 0,
			height: 0
		)
		metadataScroll.autoresizingMask = [.width, .height]
		metadataHolder.addSubview(metadataScroll)
		previewContainer.addArrangedSubview(metadataHolder)
		previewContainer.addArrangedSubview(previewScroll)
		metadataHolder.isHidden = true
		metadataScroll.hasVerticalScroller = true
		metadataScroll.autohidesScrollers = true
		metadataScroll.drawsBackground = false
		metadataScroll.documentView = metadataDocument
		metadataScroll.contentView.postsFrameChangedNotifications = true
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(metadataViewportDidResize),
			name: NSView.frameDidChangeNotification,
			object: metadataScroll.contentView
		)
		metadataHeight = metadataHolder.heightAnchor.constraint(equalToConstant: 0)
		metadataHeight?.isActive = true
		root.addSubview(header)
		root.addSubview(statusLabel)
		root.addSubview(contentHolder)
		root.addSubview(copyBar)
		for child in [header, copyBar, statusLabel, contentHolder]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
		}
		headerTrailing = header.trailingAnchor.constraint(equalTo: root.trailingAnchor)
		headerTrailing?.isActive = showsHeader
		NSLayoutConstraint.activate([
			header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
			header.topAnchor.constraint(equalTo: root.topAnchor),
			copyBar.widthAnchor.constraint(equalToConstant: 44),
			copyBar.heightAnchor.constraint(equalToConstant: 36),
			copyBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
			statusLabel.leadingAnchor.constraint(
				equalTo: root.leadingAnchor,
				constant: 12
			),
			statusLabel.trailingAnchor.constraint(
				equalTo: root.trailingAnchor,
				constant: -12
			),
			statusLabel.topAnchor.constraint(equalTo: header.bottomAnchor),
			contentHolder.leadingAnchor.constraint(equalTo: root.leadingAnchor),
			contentHolder.topAnchor.constraint(equalTo: statusLabel.bottomAnchor),
			contentHolder.bottomAnchor.constraint(equalTo: root.bottomAnchor)
		])
		copyBarTop = copyBar.topAnchor.constraint(equalTo: contentHolder.topAnchor)
		copyBarTop?.isActive = true
		contentTrailing = contentHolder.trailingAnchor.constraint(equalTo: root.trailingAnchor)
		contentTrailing?.isActive = true
		headerCollapsedHeight = header.heightAnchor.constraint(equalToConstant: 0)
		copyBar.isHidden = true
		statusCollapsedHeight = statusLabel.heightAnchor.constraint(equalToConstant: 0)
		statusCollapsedHeight?.isActive = true
		header.isHidden = !showsHeader
		headerCollapsedHeight?.isActive = !showsHeader
		show(emptyState)
	}

	private func source(for document: FileViewerDocument) -> FileSourceView
	{
		if let existing = sourceViews[document.id]
		{
			return existing
		}
		let source = FileSourceView()
		source.setWrapsLines(wrapsLines)
		let id = document.id
		source.onEdit =
		{
			[weak self] text in
			guard let self
			else
			{
				return
			}
			if self.current?.id == id
			{
				self.previewBytes = nil
			}
			self.onEdit?(id, text)
		}
		sourceViews[id] = source
		return source
	}

	func pruneSourceViews(openIDs: Set<UUID>)
	{
		for id in Array(sourceViews.keys) where !openIDs.contains(id)
		{
			sourceViews.removeValue(forKey: id)
			lastLineGeneration.removeValue(forKey: id)
		}
	}

	func render(_ document: FileViewerDocument?)
	{
		loadViewIfNeeded()
		if current?.id != document?.id
		{
			preview?.cancelLoading()
			preview = nil
			previewBytes = nil
			previewDocumentID = nil
			showingSource = false
		}
		current = document
		guard let document
		else
		{
			setCopyMarkdownVisible(false)
			setStatusMessage(nil)
			titleLabel.stringValue = "No file selected"
			show(emptyState)
			return
		}
		if document.requestedLine != nil,
			lastLineGeneration[document.id] != document.lineRequestGeneration
		{
			showingSource = true
		}
		titleLabel.stringValue = URL(fileURLWithPath: document.location.relativePath)
			.lastPathComponent
		if document.isReadOnly, document.currentText != nil
		{
			titleLabel.stringValue += " · Read-only"
		}
		if case .failed = document.status, document.content != nil
		{
			titleLabel.stringValue += " · Save failed — use Open to retry"
		}
		if document.status == .conflict
		{
			titleLabel.stringValue += " · Changed on disk — resolve from Open"
		}
		let statusMessage: String?
		if document.status == .conflict
		{
			statusMessage = "File changed on disk. Use Open to choose a version."
		}
		else if case .failed(let failure) = document.status, document.content != nil
		{
			statusMessage = "Save failed: \(Self.message(for: failure)) Use Open to retry."
		}
		else if document.isReadOnly, document.currentText != nil
		{
			statusMessage = "Read-only source. Save as is available in Open."
		}
		else
		{
			statusMessage = nil
		}
		setStatusMessage(statusMessage)
		let kind = RichFilePreviewKind(path: document.location.relativePath)
		setCopyMarkdownVisible(kind == .markdown && !(document.currentText ?? "").isEmpty)
		let capabilities = FileContentCapabilities(path: document.location.relativePath)
		modeButton.isHidden = !capabilities.supportsSourceAndPreview || document.currentText == nil
		modeButton.title = showingSource ? "Preview" : "View source"
		wrapButton.isHidden = !capabilities.hasSource || document
			.currentText == nil || !sourceIsVisible
		wrapButton.state = wrapsLines ? .on : .off

		switch document.status
		{
		case .loading:
			showMessage("Loading file…")
		case .failed(let failure) where document.content == nil:
			showMessage(Self.message(for: failure))
		case .conflict:
			if document.currentText == nil
			{
				showMessage("The file changed on disk. Choose a version from Open.")
			}
			else
			{
				showContent(document)
			}
		case .ready, .failed:
			showContent(document)
		}
	}

	func setSourceVisible(_ visible: Bool)
	{
		showingSource = visible
		render(current)
	}

	func setWrapsLines(_ wraps: Bool)
	{
		wrapsLines = wraps
		for source in sourceViews.values
		{
			source.setWrapsLines(wraps)
		}
		wrapButton.state = wraps ? .on : .off
	}

	func captureReadingState() -> FileSourceReadingState
	{
		current.flatMap
		{
			sourceViews[$0.id]
		}?.captureReadingState()
		?? FileSourceReadingState(
			selection: NSRange(
				location: 0,
				length: 0
			),
			scrollOrigin: .zero
		)
	}

	func restoreReadingState(_ state: FileSourceReadingState)
	{
		if let current
		{
			source(for: current).restoreReadingState(state)
		}
	}

	func reveal(line: Int)
	{
		showingSource = true
		render(current)
		if let current
		{
			source(for: current).reveal(line: line)
		}
	}

	func focusFind()
	{
		guard current?.currentText != nil
		else
		{
			return
		}
		setSourceVisible(true)
		guard let current
		else
		{
			return
		}
		let source = source(for: current)
		view.window?.makeFirstResponder(source.textView)
		let command = NSMenuItem()
		command.tag = NSTextFinder.Action.showFindInterface.rawValue
		source.textView.performFindPanelAction(command)
	}

	private func showContent(_ document: FileViewerDocument)
	{
		switch document.content
		{
		case .text(let text):
			if FileContentCapabilities(path: document.location.relativePath).hasRichPreview,
				!showingSource
			{
				showPreview(
					document: document,
					content: Data(text.utf8)
				)
			}
			else
			{
				showSource(
					document: document,
					text: text
				)
			}
		case .empty:
			showSource(
				document: document,
				text: ""
			)
		case .image(let bytes), .pdf(let bytes):
			showPreview(
				document: document,
				content: bytes
			)
		case .unsupported, .none:
			showMessage("This file cannot be previewed. Use Open to open it externally.")
		}
	}

	private func showSource(
		document: FileViewerDocument,
		text: String
	)
	{
		let source = source(for: document)
		source.render(
			text: text,
			path: document.location.relativePath,
			editable: document.canEdit
		)
		show(source)
		if let line = document.requestedLine,
			lastLineGeneration[document.id] != document.lineRequestGeneration
		{
			source.reveal(line: line)
			lastLineGeneration[document.id] = document.lineRequestGeneration
			onAcknowledgeLineRequest?(document.id, document.lineRequestGeneration)
		}
	}

	private func showPreview(
		document: FileViewerDocument,
		content: Data
	)
	{
		guard let kind = RichFilePreviewKind(path: document.location.relativePath)
		else
		{
			showMessage("Preview unavailable. Use Open to open the file externally.")
			return
		}
		if previewDocumentID == document.id,
			previewBytes == content,
			preview != nil
		{
			show(previewContainer)
			return
		}
		preview?.cancelLoading()
		previewGeneration = UUID()
		let generation = previewGeneration
		setMetadata([])
		let location = document.location
		let imageLoader: RichFileMarkdownImageLoader?
		if let loader = markdownImageLoader
		{
			imageLoader =
			{
				path, maximumPixelSize in
				await loader(
					location,
					path,
					maximumPixelSize
				)
			}
		}
		else
		{
			imageLoader = nil
		}
		let openLink: (URL) -> Bool =
		{
			[weak self] url in
			guard url.isFileURL
			else
			{
				return false
			}
			let root = URL(fileURLWithPath: location.root)
				.standardizedFileURL.resolvingSymlinksInPath().path
			let path = url.standardizedFileURL.resolvingSymlinksInPath().path
			let prefix = root.hasSuffix("/") ? root : root + "/"
			guard path.hasPrefix(prefix)
			else
			{
				return true
			}
			let relativePath = String(path.dropFirst(prefix.count))
			self?.onOpenLocation?(
				FileLocation(
					root: location.root,
					relativePath: relativePath
				),
				nil
			)
			return true
		}
		let loadContent: @Sendable () async throws -> Data =
		{
			content
		}
		let preview: RichFilePreviewView
		if kind == .markdown
		{
			preview = FileMarkdownPreviewView(
				kind: kind,
				imageBaseDirectory: location.fileURL.deletingLastPathComponent(),
				markdownImageLoader: imageLoader,
				onOpenLink: openLink,
				onMetadata:
				{
					[weak self] entries in
					guard let self, self.previewGeneration == generation,
							self.current?.id == document.id
					else
					{
						return
					}
					self.setMetadata(entries)
				},
				matchesFileMarkdownStyling: true,
				loadContent: loadContent
			)
		}
		else
		{
			preview = RichFilePreviewView(
				kind: kind,
				imageBaseDirectory: location.fileURL.deletingLastPathComponent(),
				markdownImageLoader: imageLoader,
				onOpenLink: openLink,
				loadContent: loadContent
			)
		}
		self.preview = preview
		previewBytes = content
		previewDocumentID = document.id
		previewScroll.documentView = preview
		preview.translatesAutoresizingMaskIntoConstraints = false
		preview.widthAnchor.constraint(equalTo: previewScroll.contentView.widthAnchor)
			.isActive = true
		show(previewContainer)
	}

	private func setMetadata(_ entries: [MarkdownFileMetadata.Entry])
	{
		metadataView?.removeFromSuperview()
		metadataView = nil
		metadataHolder.isHidden = entries.isEmpty
		guard !entries.isEmpty
		else
		{
			return
		}
		let metadata = MarkdownFileMetadataView(entries: entries)
		metadataView = metadata
		metadataDocument.addSubview(metadata)
		updateMetadataGeometry()
		metadataScroll.contentView.scroll(to: .zero)
		metadataScroll.reflectScrolledClipView(metadataScroll.contentView)
	}

	private func updateMetadataGeometry()
	{
		guard let metadataView, !isUpdatingMetadataGeometry
		else
		{
			return
		}
		isUpdatingMetadataGeometry = true
		defer
		{
			isUpdatingMetadataGeometry = false
		}
		let width = max(
			1,
			metadataScroll.contentView.bounds.width
		)
		let height = metadataView.height(forWidth: width)
		metadataView.frame = NSRect(
			x: 0,
			y: 0,
			width: width,
			height: height
		)
		metadataView.needsLayout = true
		metadataDocument.frame = metadataView.frame
		let viewportHeight = min(
			height,
			contentHolder.bounds.height * LayoutTokens.FileMarkdown.maximumMetadataHeightFraction
		)
		if metadataHeight?.constant != viewportHeight
		{
			metadataHeight?.constant = viewportHeight
			scheduleMetadataLayout()
		}
	}

	func waitForMetadataLayout() async
	{
		while let task = metadataLayoutTask
		{
			await task.value
		}
	}

	private func scheduleMetadataLayout()
	{
		metadataScroll.needsLayout = true
		metadataHolder.needsLayout = true
		previewContainer.needsUpdateConstraints = true
		view.needsUpdateConstraints = true
		previewContainer.needsLayout = true
		contentHolder.needsLayout = true
		view.needsLayout = true
		guard metadataLayoutTask == nil
		else
		{
			return
		}
		// Clip notifications can arrive during ancestor layout. Apply the new height afterwards.
		metadataLayoutTask = Task
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			self.metadataLayoutTask = nil
			guard self.previewContainer.superview === self.contentHolder
			else
			{
				return
			}
			self.view.updateConstraintsForSubtreeIfNeeded()
			self.view.layoutSubtreeIfNeeded()
		}
	}

	@objc private func metadataViewportDidResize()
	{
		// The clip finishes resizing after the controller's layout callback during pane changes.
		updateMetadataGeometry()
		scheduleMetadataLayout()
	}

	override func viewDidLayout()
	{
		super.viewDidLayout()
		guard previewContainer.superview === contentHolder
		else
		{
			copyBarTop?.constant = 0
			return
		}
		updateMetadataGeometry()
		let viewport = previewScroll.convert(
			previewScroll.bounds,
			to: contentHolder
		)
		copyBarTop?.constant = max(
			0,
			contentHolder.bounds.maxY - viewport.maxY
		)
	}

	private func showMessage(_ message: String)
	{
		messageLabel.setMessage(message)
		show(messageLabel)
	}

	private func setStatusMessage(_ message: String?)
	{
		statusLabel.stringValue = message ?? ""
		statusLabel.isHidden = message == nil
		statusCollapsedHeight?.isActive = message == nil
	}

	private func setCopyMarkdownVisible(_ visible: Bool)
	{
		copyBar.isHidden = !visible
		contentTrailing?.constant = visible && sourceIsVisible ? -44 : 0
	}

	private func show(_ child: NSView)
	{
		if child.superview === contentHolder
		{
			return
		}
		contentHolder.subviews.forEach
		{
			$0.removeFromSuperview()
		}
		contentHolder.addSubview(child)
		child.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			child.leadingAnchor.constraint(equalTo: contentHolder.leadingAnchor),
			child.trailingAnchor.constraint(equalTo: contentHolder.trailingAnchor),
			child.topAnchor.constraint(equalTo: contentHolder.topAnchor),
			child.bottomAnchor.constraint(equalTo: contentHolder.bottomAnchor)
		])
	}

	@objc private func toggleMode()
	{
		setSourceVisible(!showingSource)
	}

	@objc private func toggleWrap()
	{
		setWrapsLines(!wrapsLines)
	}

	func makeActionsMenu() -> NSMenu
	{
		loadViewIfNeeded()
		guard let document = current
		else
		{
			return NSMenu(title: "File actions")
		}
		return makeActionsMenu(for: document)
	}

	func makeOpenMenu() -> NSMenu
	{
		loadViewIfNeeded()
		let menu = NSMenu(title: "Open")
		guard let document = current
		else
		{
			return menu
		}
		let snapshot = actionSnapshot(for: document)
		let actions = sharedActions(for: snapshot)
		let destinations = openingDestinations()
		for destination in destinations where isLeadingDestination(destination)
		{
			actions.addDestination(
				destination,
				to: menu
			)
		}
		actions.addDefault(
			"Default app",
			to: menu
		)
		for destination in destinations where !isLeadingDestination(destination)
		{
			actions.addDestination(
				destination,
				to: menu
			)
		}
		menu.addItem(.separator())
		actions.addReveal(
			"Open in folder",
			to: menu
		)
		actions.addGitHub(
			"Open in GitHub",
			to: menu
		)
		if snapshot.content != nil, snapshot.content != .unsupported
		{
			actions.addExport(
				"Save as…",
				to: menu,
				in: view.window
			)
		}
		if document.status == .conflict || isFailed(document.status)
		{
			menu.addItem(.separator())
			addRecoveryActions(
				for: document,
				to: menu,
				context: ActionContext(
					snapshot: snapshot,
					receiver: nil
				)
			)
		}
		return menu
	}

	private func isLeadingDestination(_ destination: FileOpeningDestination) -> Bool
	{
		["VS Code", "Zed"].contains(destination.title)
	}

	private func sharedActions(for snapshot: ActionSnapshot) -> ViewerFileActions
	{
		let bytes: Data?
		let text: String?
		switch snapshot.content
		{
		case .text(let value):
			text = value
			bytes = Data(value.utf8)
		case .empty:
			text = ""
			bytes = Data()
		case .image(let value), .pdf(let value):
			text = nil
			bytes = value
		default:
			text = nil
			bytes = nil
		}
		let textProvider: (@MainActor @Sendable () async throws -> String)?
		if let text
		{
			textProvider =
			{
				text
			}
		}
		else
		{
			textProvider = nil
		}
		let bytesProvider: (@MainActor @Sendable () async throws -> Data)?
		if let bytes
		{
			bytesProvider =
			{
				bytes
			}
		}
		else
		{
			bytesProvider = nil
		}
		let actions = ViewerFileActions(
			location: snapshot.location,
			content: ViewerFileActions.Content(
				text: textProvider,
				bytes: bytesProvider,
				immediateText: text
			),
			onError:
			{
				[weak self] message in self?.presentActionError(message)
			}
		)
		let location = snapshot.location
		let destinationCallback = openDestination
		let defaultCallback = openDefaultApplication
		let folderCallback = openFolder
		let gitHubCallback = openGitHubURL

		if let destinationCallback
		{
			actions.onOpenDestination =
			{
				destination in try await destinationCallback(
					location,
					destination
				)
			}
		}
		if let defaultCallback
		{
			actions.onOpenDefault =
			{
				try defaultCallback(location)
			}
		}
		if let folderCallback
		{
			actions.onReveal =
			{
				folderCallback(location)
			}
		}
		actions.onOpenGitHub =
		{
			let result = await Task.detached(priority: .userInitiated)
			{
				Result
				{
					try FileGitHubURL.resolve(location: location)
				}
			}.value
			let url = try result.get()
			guard gitHubCallback?(url) ?? NSWorkspace.shared.open(url)
			else
			{
				throw NSError(
					domain: "FileGitHubURL",
					code: 1,
					userInfo: [NSLocalizedDescriptionKey: "GitHub could not be opened."]
				)
			}
		}
		return actions
	}

	private func isFailed(_ status: FileViewerDocumentStatus) -> Bool
	{
		if case .failed = status
		{
			return true
		}
		return false
	}

	func makeActionsMenu(
		for document: FileViewerDocument,
		captureAttachmentReceiver receiverFactory: (() -> ((ComposerContextItem) -> Void)?)? = nil
	) -> NSMenu
	{
		let menu = NSMenu(title: "File actions")
		let snapshot = actionSnapshot(for: document)
		let actions = sharedActions(for: snapshot)
		let receiver = (receiverFactory ?? captureAttachmentReceiver)?()
		let context = ActionContext(
			snapshot: snapshot,
			receiver: receiver
		)
		let copyContentsTitle: String?
		if document.currentText != nil
		{
			copyContentsTitle = document.location.relativePath.lowercased().hasSuffix(".md")
				? "Copy Markdown" : "Copy contents"
		}
		else
		{
			copyContentsTitle = nil
		}
		let exportTitle = snapshot.content != nil && snapshot.content != .unsupported
			? "Save As…" : nil
		actions.addContentActions(
			to: menu,
			copyContentsTitle: copyContentsTitle,
			exportTitle: exportTitle,
			in: view.window
		)
		actions.addExternalOpenActions(
			to: menu,
			preferredTitle: "Open in preferred editor",
			openWithTitle: "Open with…",
			revealTitle: "Reveal in Finder",
			in: view.window
		)
		if receiver != nil
		{
			addAction(
				"Add to chat",
				action: #selector(addToChat),
				to: menu,
				context: context
			)
		}
		menu.addItem(.separator())
		if document.isDirty
		{
			addAction(
				"Save",
				action: #selector(save),
				to: menu,
				context: context
			)
		}
		addRecoveryActions(
			for: document,
			to: menu,
			context: context
		)
		return menu
	}

	private func actionSnapshot(for document: FileViewerDocument) -> ActionSnapshot
	{
		let content: FileViewerContent?
		if document.currentText != nil
		{
			let visibleSource = sourceViews[document.id].flatMap
			{
				$0.superview == nil ? nil : $0.textView.string
			}
			content = .text(visibleSource ?? document.currentText ?? "")
		}
		else
		{
			content = document.content
		}
		return ActionSnapshot(
			id: document.id,
			location: document.location,
			content: content
		)
	}

	private func addRecoveryActions(
		for document: FileViewerDocument,
		to menu: NSMenu,
		context: ActionContext
	)
	{
		if document.status == .conflict
		{
			addAction(
				"Continue editing",
				action: #selector(continueEditing),
				to: menu,
				context: context
			)
			addAction(
				"Use disk version",
				action: #selector(useDisk),
				to: menu,
				context: context
			)
			addAction(
				"Keep local version",
				action: #selector(keepLocal),
				to: menu,
				context: context
			)
		}
		if case .failed = document.status
		{
			addAction(
				"Retry",
				action: #selector(retry),
				to: menu,
				context: context
			)
			if document.currentText != nil
			{
				addAction(
					"Continue editing",
					action: #selector(continueEditing),
					to: menu,
					context: context
				)
			}
		}
	}

	@discardableResult
	private func addAction(
		_ title: String,
		action: Selector,
		to menu: NSMenu,
		context: ActionContext
	) -> NSMenuItem
	{
		let item = NSMenuItem(
			title: title,
			action: action,
			keyEquivalent: ""
		)
		item.target = self
		item.representedObject = context
		menu.addItem(item)
		return item
	}

	@objc private func showActions()
	{
		let menu = makeActionsMenu()
		menu.popUp(
			positioning: nil,
			at: NSPoint(
				x: 0,
				y: actionsButton.bounds.maxY
			),
			in: actionsButton
		)
	}

	private func actionContext(_ sender: NSMenuItem) -> ActionContext?
	{
		sender.representedObject as? ActionContext
	}

	@objc private func copyCurrentMarkdown()
	{
		guard let document = current,
				RichFilePreviewKind(path: document.location.relativePath) == .markdown,
				case .text(let text)? = actionSnapshot(for: document).content
		else
		{
			return
		}
		ViewerFileActions.copyText(text)
	}

	@objc private func addToChat(_ sender: NSMenuItem)
	{
		guard let snapshot = actionContext(sender)?.snapshot
		else
		{
			return
		}
		actionContext(sender)?.receiver?(ComposerContextItem(
			kind: .fileReference,
			title: snapshot.location.fileURL.lastPathComponent,
			path: snapshot.location.fileURL.path
		))
	}

	@objc private func save(_ sender: NSMenuItem)
	{
		if let id = actionContext(sender)?.snapshot.id
		{
			onSave?(id)
		}
	}

	@objc private func retry(_ sender: NSMenuItem)
	{
		if let id = actionContext(sender)?.snapshot.id
		{
			onRetry?(id)
		}
	}

	@objc private func useDisk(_ sender: NSMenuItem)
	{
		if let id = actionContext(sender)?.snapshot.id
		{
			onUseDisk?(id)
		}
	}

	@objc private func keepLocal(_ sender: NSMenuItem)
	{
		if let id = actionContext(sender)?.snapshot.id
		{
			onKeepLocal?(id)
		}
	}

	@objc private func continueEditing(_ sender: NSMenuItem)
	{
		if let id = actionContext(sender)?.snapshot.id
		{
			onContinueEditing?(id)
		}
	}

	private func presentActionError(_ message: String)
	{
		ViewerFileActions.presentError(
			message,
			in: view.window
		)
	}

	private static func message(for failure: FileViewerFailure) -> String
	{
		switch failure
		{
		case .invalidPath: "The file path is outside this workspace."
		case .unavailable: "The file is unavailable. Retry or open it externally."
		case .unsupportedEncoding: "This text encoding is unsupported. Open it externally."
		case .binary: "This binary file has no source preview. Open it externally."
		case .tooLarge: "This file is too large to preview. Open it externally."
		case .readOnly: "This file is read-only."
		case .conflict: "The file changed on disk. Choose a conflict action."
		case .cancelled: "The file load was cancelled. Retry."
		case .io(let message): "Could not load the file: \(message)"
		}
	}
}
