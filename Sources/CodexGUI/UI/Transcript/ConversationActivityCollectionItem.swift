import AppKit

@MainActor
final class ConversationActivityCollectionItem: NSCollectionViewItem
{
	typealias OutputReadingPosition = ConversationTerminalCard.ReadingPosition

	var activityID: String?
	{
		row?.id
	}
	private static let rowHeight = DesktopDisclosureButton.Presentation.hoverReveal.rowHeight
	private static let detailSpacing: CGFloat = 6
	private static let imageHeight: CGFloat = 116
	private let stack = NSStackView()
	private var arrangedWidthConstraints: [NSLayoutConstraint] = []
	private let header = NSStackView()
	private var isHeaderHovered = false
	private var hoverSynchronizationTask: Task<Void, Never>?
	private let icon = NSImageView()
	private let titleLabel = NSTextField(labelWithString: "")
	private let outcomeLabel = NSTextField(labelWithString: "")
	private let titleClick = NSClickGestureRecognizer()
	private let subagentsButton = DesktopAttributedTitleButton(
		title: "",
		target: nil,
		action: nil
	)
	private let fileButton = DesktopAttributedTitleButton(
		title: "",
		target: nil,
		action: nil
	)
	private let disclosure = DesktopDisclosureButton(presentation: .hoverReveal)
	private let terminalCard = ConversationTerminalCard()
	private let imageButton = NSButton(
		title: "",
		target: nil,
		action: nil
	)
	private let imageState = NSTextField(labelWithString: "")
	private let imageContainer = NSView()
	private var row: ConversationActivityRow?
	private var onToggle: (() -> Void)?
	private var onOpenFile: ((String) -> Void)?
	private var canOpenImage: (() -> Bool)?
	private var onOpenSubagents: (() -> Void)?
	private var onSelectSubagentThread: ((String) -> Void)?
	private var subagentNavigationGeneration = 0
	private var imageTask: Task<Void, Never>?
	private let expandedImagePreview = ExpandedImagePreview()

	override func loadView()
	{
		let host = ActivityImagePreviewHostView()
		host.onDetach =
		{
			[weak self] in
			self?.expandedImagePreview.dismiss()
		}
		view = host
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = Self.detailSpacing
		AppKitLayout.pin(
			stack,
			to: view,
			inset: 0
		)
		configureHeader()
		configureActivityButtons()
		configureImagePreview()
	}

	private func configureHeader()
	{
		header.orientation = .horizontal
		header.alignment = .centerY
		header.spacing = 7
		header.addTrackingArea(NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
			owner: self,
			userInfo: nil
		))
		header.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
		icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
		icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
		icon.contentTintColor = .secondaryLabelColor
		titleLabel.font = .systemFont(ofSize: 14)
		titleLabel.textColor = AppKitColorTokens.activityText
		titleLabel.lineBreakMode = .byTruncatingTail
		titleClick.target = self
		titleClick.action = #selector(toggle)
		titleClick.isEnabled = false
		titleLabel.addGestureRecognizer(titleClick)
		titleLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		outcomeLabel.font = .systemFont(ofSize: 12)
		outcomeLabel.textColor = .systemRed
		outcomeLabel.setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
	}

	private func configureActivityButtons()
	{
		for button in [fileButton, imageButton, subagentsButton]
		{
			button.isBordered = false
			button.target = self
			button.setButtonType(.momentaryPushIn)
		}
		fileButton.action = #selector(openFile)
		subagentsButton.action = #selector(openSubagents)
		subagentsButton.refusesFirstResponder = false
		subagentsButton.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		fileButton.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		disclosure.target = self
		disclosure.action = #selector(toggle)
		imageButton.action = #selector(openImage)
		imageButton.imageScaling = .scaleProportionallyUpOrDown
	}

	private func configureImagePreview()
	{
		imageContainer.heightAnchor.constraint(equalToConstant: Self.imageHeight).isActive = true
		for child in [imageButton, imageState]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			imageContainer.addSubview(child)
			child.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor).isActive = true
			child.topAnchor.constraint(equalTo: imageContainer.topAnchor).isActive = true
		}
		imageButton.widthAnchor.constraint(equalToConstant: 108).isActive = true
		imageButton.heightAnchor.constraint(equalToConstant: 108).isActive = true
		imageState.textColor = .secondaryLabelColor
		imageState.font = .systemFont(ofSize: 12)
	}

	override func prepareForReuse()
	{
		super.prepareForReuse()
		expandedImagePreview.dismiss()
		imageTask?.cancel()
		imageTask = nil
		row = nil
		disclosure.setSubject(nil)
		titleClick.isEnabled = false
		terminalCard.resetCopyInteraction()
		hoverSynchronizationTask?.cancel()
		hoverSynchronizationTask = nil
		isHeaderHovered = false
		updateHeaderHoverAppearance()
		terminalCard.reset()
		onToggle = nil
		onOpenFile = nil
		canOpenImage = nil
		onOpenSubagents = nil
		onSelectSubagentThread = nil
		subagentNavigationGeneration += 1
		imageButton.image = nil
		imageButton.isHidden = true
		NSLayoutConstraint.deactivate(arrangedWidthConstraints)
		arrangedWidthConstraints = []
		stack.setViews(
			[],
			in: .top
		)
	}

	func configure(
		_ row: ConversationActivityRow,
		onToggle: @escaping () -> Void,
		onOpenFile: @escaping (String) -> Void,
		canOpenImage: (() -> Bool)? = nil,
		onOpenSubagents: (() -> Void)? = nil,
		onSelectSubagentThread: ((String) -> Void)? = nil
	)
	{
		_ = view
		imageTask?.cancel()
		if self.row?.id != row.id || self.row?.imagePath != row.imagePath || !row.expanded
		{
			expandedImagePreview.dismiss()
		}
		let previousPosition = self.row?.id == row.id ? outputReadingPosition() : nil
		if self.row?.id != row.id || self.row?.expanded != row.expanded
		{
			terminalCard.resetCopyInteraction()
		}
		if self.row?.id != row.id
		{
			isHeaderHovered = false
		}
		self.row = row
		self.onToggle = onToggle
		self.onOpenFile = onOpenFile
		self.canOpenImage = canOpenImage
		self.onOpenSubagents = onOpenSubagents
		self.onSelectSubagentThread = onSelectSubagentThread
		subagentNavigationGeneration += 1
		renderHeader(row)
		let arrangedViews = renderExpandedDetails(
			row,
			previousPosition: previousPosition
		)
		arrangeActivityViews(arrangedViews)
		view.toolTip = row.subagents.isEmpty ? nil : titleLabel.toolTip
		view.setAccessibilityLabel(row.subagents.isEmpty ? row.title : titleLabel.toolTip)
		view.needsLayout = true
	}

	private func renderHeader(_ row: ConversationActivityRow)
	{
		titleClick.isEnabled = row.kind == .command && row.command != nil
		let hasLink = row.filePath != nil && row.linkTitle != nil
		titleLabel.stringValue = hasLink ? "Read" : row.title
		if row.kind == .read, !hasLink, let linkTitle = row.linkTitle, row.title == "Read"
		{
			titleLabel.stringValue = "Read \(linkTitle)"
		}
		titleLabel.toolTip = row.subagents.isEmpty ? row.command?.command ?? row.title
			: row.subagents.map
			{
				"\($0.name) \($0.action)"
			}.joined(separator: "\n")
		fileButton.attributedTitle = NSAttributedString(
			string: row.linkTitle ?? "",
			attributes: [.font: NSFont.systemFont(ofSize: 14),
							.foregroundColor: NSColor.secondaryLabelColor,
							.underlineStyle: 1]
		)
		fileButton.toolTip = row.filePath
		fileButton.setAccessibilityLabel("Open \(row.filePath ?? "file")")
		updateHeaderHoverAppearance()
		disclosure.setSubject(row.title)
		disclosure.setExpanded(row.expanded)
		icon.image = DesktopIcons.image(Self.icon(for: row))
		let spacer = NSView()
		spacer.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		var headerViews = activityHeaderViews(row)
		if hasLink
		{
			headerViews.append(fileButton)
		}
		if let command = row.command,
			let outcome = ConversationCommandOutcome(command).exceptionalTitle
		{
			outcomeLabel.stringValue = outcome
			headerViews.append(outcomeLabel)
		}
		let canExpand = row.kind == .group || row.kind == .image || row.command != nil
		if row.kind == .group
		{
			headerViews.append(disclosure)
			headerViews.append(spacer)
		}
		else
		{
			if canExpand
			{
				headerViews.append(disclosure)
			}
			if hasLink || canExpand
			{
				headerViews.append(spacer)
			}
		}
		header.setViews(
			headerViews,
			in: .leading
		)
	}

	private func activityHeaderViews(_ row: ConversationActivityRow) -> [NSView]
	{
		guard row.kind == .subagent
		else
		{
			return [icon, titleLabel]
		}
		subagentsButton.attributedTitle = NSAttributedString(
			string: row.title,
			attributes: [
				.font: NSFont.systemFont(ofSize: 14),
				.foregroundColor: NSColor.secondaryLabelColor
			]
		)
		subagentsButton.toolTip = titleLabel.toolTip
		subagentsButton.setAccessibilityLabel("Open Subagents: \(row.title)")
		let generation = subagentNavigationGeneration
		let avatars: NSView
		if onSelectSubagentThread != nil
		{
			avatars = ConversationSubagentAvatars.make(
				row.subagents,
				onSelectThread:
				{
					[weak self] threadID in
					guard let self, self.subagentNavigationGeneration == generation
					else
					{
						return
					}
					self.onSelectSubagentThread?(threadID)
				}
			)
		}
		else
		{
			avatars = ConversationSubagentAvatars.make(row.subagents)
			avatars.addGestureRecognizer(NSClickGestureRecognizer(
				target: self,
				action: #selector(openSubagents)
			))
		}
		return [avatars, onOpenSubagents != nil ? subagentsButton : titleLabel]
	}

	private func renderExpandedDetails(
		_ row: ConversationActivityRow,
		previousPosition: OutputReadingPosition?
	) -> [NSView]
	{
		var views: [NSView] = [header]
		imageButton.image = nil
		imageButton.isHidden = true
		imageState.stringValue = ""
		terminalCard.configure(
			row.command,
			expanded: row.expanded && row.kind != .group,
			preserving: previousPosition
		)
		if row.expanded, row.command != nil, row.kind != .group
		{
			views.append(terminalCard)
		}
		else if row.expanded, row.kind == .image
		{
			views.append(imageContainer)
			loadImage(path: row.imagePath)
		}
		return views
	}

	private func arrangeActivityViews(_ views: [NSView])
	{
		NSLayoutConstraint.deactivate(arrangedWidthConstraints)
		stack.setViews(
			views,
			in: .top
		)
		// These constraints require the arranged views to be attached to the stack.
		arrangedWidthConstraints = views.flatMap
		{
			[
				$0.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
				$0.widthAnchor.constraint(equalTo: stack.widthAnchor)
			]
		}
		NSLayoutConstraint.activate(arrangedWidthConstraints)
	}

	override func mouseEntered(with event: NSEvent)
	{
		if view.window != nil
		{
			synchronizeHeaderHover()
		}
		else
		{
			isHeaderHovered = true
			updateHeaderHoverAppearance()
		}
	}

	override func mouseExited(with event: NSEvent)
	{
		if view.window != nil
		{
			synchronizeHeaderHover()
		}
		else
		{
			isHeaderHovered = false
			updateHeaderHoverAppearance()
		}
	}

	override func mouseMoved(with event: NSEvent)
	{
		synchronizeHeaderHover()
	}

	override func viewDidAppear()
	{
		super.viewDidAppear()
		scheduleHeaderHoverSynchronization()
	}

	override func viewDidDisappear()
	{
		super.viewDidDisappear()
		terminalCard.resetCopyInteraction()
		hoverSynchronizationTask?.cancel()
		hoverSynchronizationTask = nil
		isHeaderHovered = false
		updateHeaderHoverAppearance()
	}

	private func scheduleHeaderHoverSynchronization()
	{
		guard view.window != nil, hoverSynchronizationTask == nil
		else
		{
			return
		}
		// Descendant stack geometry can still be unsettled in viewDidLayout.
		hoverSynchronizationTask = Task
		{
			[weak self] in
			await Task.yield()
			guard !Task.isCancelled, let self
			else
			{
				return
			}
			self.hoverSynchronizationTask = nil
			self.synchronizeHeaderHover()
		}
	}

	private func synchronizeHeaderHover()
	{
		guard let window = view.window
		else
		{
			return
		}
		// Query the owning window's pointer coordinates after asynchronous layout settles.
		let windowPoint = window.mouseLocationOutsideOfEventStream
		let headerBounds = header.convert(
			header.bounds,
			to: nil
		)
		let visibleBounds = header.convert(
			header.visibleRect.intersection(header.bounds),
			to: nil
		)
		isHeaderHovered = row != nil && window.isVisible && !header.isHiddenOrHasHiddenAncestor &&
			headerBounds.contains(windowPoint) && visibleBounds.contains(windowPoint)
		updateHeaderHoverAppearance()
	}

	private func updateHeaderHoverAppearance()
	{
		let textColor: NSColor = isHeaderHovered && row != nil
			? AppKitColorTokens.primaryText : AppKitColorTokens.activityText
		if titleLabel.textColor != textColor
		{
			titleLabel.textColor = textColor
		}
		let link = fileButton.attributedTitle
		if link.length > 0,
			(link.attribute(
			.foregroundColor,
			at: 0,
			effectiveRange: nil
			) as? NSColor) != textColor
		{
			let highlightedLink = NSMutableAttributedString(attributedString: link)
			highlightedLink.addAttribute(
				.foregroundColor,
				value: textColor,
				range: NSRange(
					location: 0,
					length: link.length
				)
			)
			fileButton.attributedTitle = highlightedLink
		}

		disclosure.setExpanded(row?.expanded == true)
		disclosure.setContextHovered(isHeaderHovered && row != nil)
	}

	static func itemSize(
		row: ConversationActivityRow,
		width: CGFloat
	) -> NSSize
	{
		let detail: CGFloat
		if row.expanded, row.kind != .group, let command = row.command
		{
			detail = ConversationTerminalCard.height(
				command: command,
				width: width
			) + detailSpacing
		}
		else if row.expanded, row.kind == .image
		{
			detail = imageHeight + detailSpacing
		}
		else
		{
			detail = 0
		}
		return NSSize(
			width: max(
				1,
				width
			),
			height: rowHeight + detail
		)
	}

	override func viewDidLayout()
	{
		super.viewDidLayout()

		terminalCard.layoutContent(width: view.bounds.width)
		scheduleHeaderHoverSynchronization()
	}

	func outputReadingPosition() -> OutputReadingPosition?
	{
		terminalCard.readingPosition()
	}

	func restoreOutputReadingPosition(_ position: OutputReadingPosition)
	{
		terminalCard.restoreReadingPosition(position)
		view.needsLayout = true
	}

	static func sampledShellLineCount(_ output: String) -> Int
	{
		ConversationTerminalCard.sampledShellLineCount(output)
	}

	func writeCommand(to pasteboard: NSPasteboard)
	{
		terminalCard.writeCommand(to: pasteboard)
	}

	func writeOutput(to pasteboard: NSPasteboard)
	{
		terminalCard.writeOutput(to: pasteboard)
	}

	private static func icon(for row: ConversationActivityRow) -> DesktopIcon
	{
		switch row.kind
		{
		case .read: return .bookOpen
		case .search, .listFiles: return .search
		case .image: return .images
		case .command: return .terminal
		case .subagent: return .agent
		case .group:
			return row.title.hasPrefix("Read") ? .bookOpen :
				(row.title.hasPrefix("Searched") ? .search : .terminal)
		}
	}

	private func loadImage(path: String?)
	{
		imageState.stringValue = "Loading image…"
		guard let path, !path.isEmpty
		else
		{
			imageState.stringValue = "Image unavailable"
			return
		}
		imageTask = Task
		{
			[weak self] in
			let thumbnail = await SourceThumbnailLoader.image(
				path: path,
				maximumPixelSize: 240
			)
			guard !Task.isCancelled, let self, self.row?.imagePath == path
			else
			{
				return
			}
			guard let thumbnail
			else
			{
				self.imageState.stringValue = "Image unavailable"
				self.imageState.toolTip = path
				return
			}
			let image = NSImage(
				cgImage: thumbnail.image,
				size: .zero
			)
			self.showImage(image)
		}
	}

	private func showImage(_ image: NSImage)
	{
		imageState.stringValue = ""
		imageButton.image = image
		imageButton.isHidden = false
		imageButton.toolTip = row?.imagePath
		imageButton.setAccessibilityLabel("Open viewed image")
	}

	@objc private func toggle()
	{
		onToggle?()
	}
	@objc private func openFile()
	{
		if let path = row?.filePath
		{
			onOpenFile?(path)
		}
	}
	@objc private func openSubagents()
	{
		guard row?.kind == .subagent
		else
		{
			return
		}
		onOpenSubagents?()
	}
	@objc private func openImage()
	{
		guard let row, row.kind == .image, row.expanded,
				!imageButton.isHidden, imageButton.image != nil,
				let path = row.imagePath, !path.isEmpty, let window = view.window,
				canOpenImage?() != false
		else
		{
			return
		}
		expandedImagePreview.present(
			path: path,
			name: URL(fileURLWithPath: path).lastPathComponent,
			in: window
		)
	}

	/// Await the automatic layout-triggered update already scheduled for this item.
	func waitForHeaderHoverSynchronization() async
	{
		await hoverSynchronizationTask?.value
	}

	func waitForImagePreview() async
	{
		await imageTask?.value
		await expandedImagePreview.waitForPresentation()
	}
}

@MainActor
private final class ActivityImagePreviewHostView: NSView
{
	var onDetach: (() -> Void)?

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		if window == nil
		{
			onDetach?()
		}
	}
}
