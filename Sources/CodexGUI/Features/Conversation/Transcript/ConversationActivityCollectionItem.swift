import AppKit
import ImageIO

@MainActor
final class ConversationActivityCollectionItem: NSCollectionViewItem
{
	struct OutputReadingPosition
	{
		let origin: NSPoint
		let selection: NSRange
	}

	var activityID: String?
	{
		row?.id
	}
	private var pendingOutputReadingPosition: OutputReadingPosition?
	private static let rowHeight: CGFloat = 30
	private static let detailSpacing: CGFloat = 6
	private static let minimumShellHeight: CGFloat = 100
	private static let maximumShellSampleLength = 8000
	private static let maximumShellHeight: CGFloat = 218
	private static let terminalFont = NSFont(
		name: "Menlo-Regular",
		size: 13
	)
		?? NSFont.monospacedSystemFont(
			ofSize: 13,
			weight: .regular
		)
	private static let terminalLineSpacing: CGFloat = 3
	private static let terminalLineHeight = NSLayoutManager().defaultLineHeight(for: terminalFont)
		+ terminalLineSpacing
	private var shellHeightConstraint: NSLayoutConstraint?
	private var commandHeightConstraint: NSLayoutConstraint?
	private static let imageHeight: CGFloat = 116
	private let stack = NSStackView()
	private var arrangedWidthConstraints: [NSLayoutConstraint] = []
	private let header = NSStackView()
	private var isHeaderHovered = false
	private var displayedDisclosureIcon: DesktopIcon?
	private var hoverSynchronizationTask: Task<Void, Never>?
	private let icon = NSImageView()
	private let titleLabel = NSTextField(labelWithString: "")
	private let titleClick = NSClickGestureRecognizer()
	private let subagentsButton = NSButton(
		title: "",
		target: nil,
		action: nil
	)
	private let fileButton = NSButton(
		title: "",
		target: nil,
		action: nil
	)
	private let disclosure = NSButton(
		title: "",
		target: nil,
		action: nil
	)
	private let shell = DesktopSurface(
		DesktopTheme.elevated,
		cornerRadius: 12,
		bordered: true
	)
	private let shellLabel = NSTextField(labelWithString: "Shell")
	private let commandLabel = NSTextField(labelWithString: "")
	private let commandLine = NSView()
	private let shellStatusLabel = NSTextField(labelWithString: "")
	private let output = NSTextView()
	private let scroll = ConversationTerminalScrollView()
	private let copyCommandButton = ConversationTerminalCopyButton()
	private let copyOutputButton = ConversationTerminalCopyButton()
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
	private var onOpenSubagents: (() -> Void)?
	private var onSelectSubagentThread: ((String) -> Void)?
	private var subagentNavigationGeneration = 0
	private var imageTask: Task<Void, Never>?
	private static let imageCache = NSCache<NSString, NSImage>()

	override func loadView()
	{
		view = NSView()
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
		configureShellOutput()
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
		titleLabel.textColor = .secondaryLabelColor
		titleLabel.lineBreakMode = .byTruncatingTail
		titleClick.target = self
		titleClick.action = #selector(toggle)
		titleClick.isEnabled = false
		titleLabel.addGestureRecognizer(titleClick)
		titleLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
	}

	private func configureActivityButtons()
	{
		for button in [fileButton, disclosure, imageButton, subagentsButton]
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
		disclosure.action = #selector(toggle)
		disclosure.widthAnchor.constraint(equalToConstant: 24).isActive = true
		disclosure.heightAnchor.constraint(equalToConstant: 24).isActive = true
		disclosure.refusesFirstResponder = false
		disclosure.setAccessibilityElement(true)
		disclosure.setAccessibilityRole(.button)
		imageButton.action = #selector(openImage)
		imageButton.imageScaling = .scaleProportionallyUpOrDown
	}

	private func configureShellOutput()
	{
		shellHeightConstraint = shell.heightAnchor
			.constraint(equalToConstant: Self.minimumShellHeight)
		shellHeightConstraint?.isActive = true
		shellLabel.font = .systemFont(ofSize: 13)
		shellLabel.textColor = DesktopTheme.terminalText
		shellStatusLabel.font = .systemFont(ofSize: 13)
		shellStatusLabel.textColor = DesktopTheme.terminalMutedText
		shellStatusLabel.alignment = .right
		shellStatusLabel.lineBreakMode = .byTruncatingTail
		output.isEditable = false
		output.isSelectable = true
		output.drawsBackground = false
		output.font = Self.terminalFont
		output.textColor = DesktopTheme.terminalText
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineSpacing = Self.terminalLineSpacing
		output.defaultParagraphStyle = paragraph
		output.textContainerInset = NSSize(
			width: 0,
			height: 3
		)
		output.textContainer?.lineFragmentPadding = 0
		output.isVerticallyResizable = true
		output.isHorizontallyResizable = true
		output.autoresizingMask = []
		output.maxSize = NSSize(
			width: CGFloat.greatestFiniteMagnitude,
			height: CGFloat.greatestFiniteMagnitude
		)
		output.textContainer?.widthTracksTextView = false
		output.textContainer?.containerSize = output.maxSize
		scroll.drawsBackground = false
		scroll.hasVerticalScroller = true
		scroll.hasHorizontalScroller = true
		scroll.autohidesScrollers = true
		scroll.scrollerStyle = .overlay
		scroll.documentView = output
		commandLabel.font = output.font
		commandLabel.textColor = DesktopTheme.terminalText
		commandLabel.isSelectable = true
		commandLabel.lineBreakMode = .byWordWrapping
		commandLabel.maximumNumberOfLines = 2
		commandLabel.cell?.truncatesLastVisibleLine = true
		commandLabel.clipsToBounds = true
		commandLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		commandLabel.setAccessibilityLabel("Shell command")
		commandLabel.translatesAutoresizingMaskIntoConstraints = false
		commandLine.addSubview(commandLabel)
		commandHeightConstraint = commandLine.heightAnchor.constraint(equalToConstant: 24)
		commandHeightConstraint?.isActive = true
		NSLayoutConstraint.activate([
			commandLabel.leadingAnchor.constraint(equalTo: commandLine.leadingAnchor),
			commandLabel.trailingAnchor.constraint(
				equalTo: commandLine.trailingAnchor,
				constant: -28
			),
			commandLabel.topAnchor.constraint(equalTo: commandLine.topAnchor),
			commandLabel.bottomAnchor.constraint(equalTo: commandLine.bottomAnchor)
		])
		let shellStack = NSStackView(views: [shellLabel, commandLine, scroll, shellStatusLabel])
		shellStack.orientation = .vertical
		shellStack.alignment = .leading
		shellStack.spacing = 8
		AppKitLayout.pin(
			shellStack,
			to: shell,
			inset: 10
		)
		commandLine.widthAnchor.constraint(equalTo: shellStack.widthAnchor).isActive = true
		scroll.widthAnchor.constraint(equalTo: shellStack.widthAnchor).isActive = true
		scroll.setContentHuggingPriority(
			.defaultLow,
			for: .vertical
		)
		shellStatusLabel.widthAnchor.constraint(equalTo: shellStack.widthAnchor).isActive = true
		configureShellCopyButton(
			copyCommandButton,
			label: "Copy command",
			action: #selector(copyCommand),
			anchor: commandLine
		)
		configureShellCopyButton(
			copyOutputButton,
			label: "Copy output",
			action: #selector(copyOutput),
			anchor: scroll
		)
	}

	private func configureShellCopyButton(
		_ button: ConversationTerminalCopyButton,
		label: String,
		action: Selector,
		anchor: NSView
	)
	{
		DesktopTheme.styleButton(button)
		button.setCopyImage(DesktopIcons.image(
			.copy,
			size: 14,
			accessibilityDescription: label
		))
		button.imagePosition = .imageOnly
		button.toolTip = label
		button.setAccessibilityLabel(label)
		button.target = self
		button.action = action
		button.translatesAutoresizingMaskIntoConstraints = false
		shell.addSubview(button)
		NSLayoutConstraint.activate([
			button.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
			button.topAnchor.constraint(equalTo: anchor.topAnchor),
			button.widthAnchor.constraint(equalToConstant: 24),
			button.heightAnchor.constraint(equalToConstant: 24)
		])
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
		imageTask?.cancel()
		imageTask = nil
		row = nil
		titleClick.isEnabled = false
		copyCommandButton.resetHover()
		copyOutputButton.resetHover()
		hoverSynchronizationTask?.cancel()
		hoverSynchronizationTask = nil
		isHeaderHovered = false
		updateHeaderHoverAppearance()
		pendingOutputReadingPosition = nil
		output.setSelectedRange(NSRange(
			location: 0,
			length: 0
		))
		onToggle = nil
		onOpenFile = nil
		onOpenSubagents = nil
		onSelectSubagentThread = nil
		subagentNavigationGeneration += 1
		output.string = ""
		commandLabel.stringValue = ""
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
		onOpenSubagents: (() -> Void)? = nil,
		onSelectSubagentThread: ((String) -> Void)? = nil
	)
	{
		_ = view
		imageTask?.cancel()
		let previousPosition = self.row?.id == row.id ? outputReadingPosition() : nil
		if self.row?.id != row.id || self.row?.expanded != row.expanded
		{
			copyCommandButton.resetHover()
			copyOutputButton.resetHover()
		}
		if self.row?.id != row.id
		{
			isHeaderHovered = false
		}
		pendingOutputReadingPosition = previousPosition
		self.row = row
		self.onToggle = onToggle
		self.onOpenFile = onOpenFile
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
		disclosure.setAccessibilityLabel("\(row.expanded ? "Collapse" : "Expand") \(row.title)")
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
		if row.expanded, let command = row.command, row.kind != .group
		{
			commandLabel.attributedStringValue = Self.commandText(command.command)
			commandLabel.toolTip = command.command
			let updatedText = command.output
			if previousPosition != nil, updatedText.hasPrefix(output.string)
			{
				let existingLength = (output.string as NSString).length
				let appendedText = (updatedText as NSString).substring(from: existingLength)
				output.textStorage?.replaceCharacters(
					in: NSRange(
						location: existingLength,
						length: 0
					),
					with: appendedText
				)
			}
			else
			{
				output.string = updatedText
			}
			pendingOutputReadingPosition = previousPosition ?? OutputReadingPosition(
				origin: .zero,
				selection: NSRange(
					location: 0,
					length: 0
				)
			)
			output.setAccessibilityLabel("Shell output")
			shellStatusLabel.stringValue = Self.shellStatus(command)
			shellStatusLabel.toolTip = Self.metadata(command)
			shellStatusLabel.textColor = DesktopTheme.terminalMutedText
			copyCommandButton.isEnabled = !command.command.isEmpty
			copyOutputButton.isEnabled = !command.output.isEmpty
			updateShellGeometry(command)
			views.append(shell)
		}
		else
		{
			output.string = ""
			pendingOutputReadingPosition = nil
			if row.expanded, row.kind == .image
			{
				views.append(imageContainer)
				loadImage(path: row.imagePath)
			}
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
		copyCommandButton.resetHover()
		copyOutputButton.resetHover()
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
		let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
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
		let textColor: NSColor = isHeaderHovered && row != nil ? .labelColor : .secondaryLabelColor
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

		// Keep the button available to pointer, keyboard and accessibility interaction.
		// Only its glyph changes, so hover never shifts the header layout.
		let requestedIcon: DesktopIcon?
		if isHeaderHovered, let row
		{
			requestedIcon = row.expanded ? .chevronDown : .chevronRight
		}
		else
		{
			requestedIcon = nil
		}
		guard requestedIcon != displayedDisclosureIcon
		else
		{
			return
		}
		displayedDisclosureIcon = requestedIcon
		disclosure.image = requestedIcon.map
		{
			DesktopIcons.image($0)
		}
	}

	static func itemSize(
		row: ConversationActivityRow,
		width: CGFloat
	) -> NSSize
	{
		let detail: CGFloat
		if row.expanded, row.kind != .group, let command = row.command
		{
			detail = shellHeight(
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

		if let row, row.expanded, row.kind != .group, let command = row.command
		{
			updateShellGeometry(command)
			updateOutputDocumentSize()
			applyPendingOutputReadingPosition()
		}
		scheduleHeaderHoverSynchronization()
	}

	func outputReadingPosition() -> OutputReadingPosition?
	{
		guard let row, row.expanded, row.kind != .group, row.command != nil
		else
		{
			return nil
		}
		if let pendingOutputReadingPosition
		{
			return pendingOutputReadingPosition
		}
		return OutputReadingPosition(
			origin: scroll.contentView.bounds.origin,
			selection: output.selectedRange()
		)
	}

	func restoreOutputReadingPosition(_ position: OutputReadingPosition)
	{
		guard let row, row.expanded, row.kind != .group, row.command != nil
		else
		{
			return
		}
		pendingOutputReadingPosition = position
		view.needsLayout = true
	}

	private func applyPendingOutputReadingPosition()
	{
		guard let position = pendingOutputReadingPosition,
				scroll.contentSize.width > 0, scroll.contentSize.height > 0,
				let container = output.textContainer, let manager = output.layoutManager
		else
		{
			return
		}
		manager.ensureLayout(for: container)
		// Finish document and clip geometry before restoring the reader's offset.
		// Text storage updates can schedule a later resize of the scroll document.
		output.layoutSubtreeIfNeeded()
		scroll.layoutSubtreeIfNeeded()
		let textLength = (output.string as NSString).length
		let location = min(
			position.selection.location,
			textLength
		)
		let length = min(
			position.selection.length,
			textLength - location
		)
		output.setSelectedRange(NSRange(
			location: location,
			length: length
		))
		let maximumY = max(
			0,
			output.frame.height - scroll.contentSize.height
		)
		let maximumX = max(
			0,
			output.frame.width - scroll.contentSize.width
		)
		let origin = NSPoint(
			x: min(
				maximumX,
				max(
					0,
					position.origin.x
				)
			),
			y: min(
				maximumY,
				max(
					0,
					position.origin.y
				)
			)
		)
		scroll.contentView.scroll(to: origin)
		scroll.reflectScrolledClipView(scroll.contentView)
		pendingOutputReadingPosition = nil
	}

	private func updateOutputDocumentSize()
	{
		guard scroll.contentSize.width > 0,
				let container = output.textContainer, let manager = output.layoutManager
		else
		{
			return
		}
		manager.ensureLayout(for: container)
		let textRect = manager.usedRect(for: container)
		output.setFrameSize(NSSize(
			width: max(
				scroll.contentSize.width,
				ceil(textRect.maxX) + 28
			),
			height: max(
				scroll.contentSize.height,
				ceil(textRect.height) + output.textContainerInset.height * 2
			)
		))
		scroll.updateEdgeFades()
	}

	private func updateShellGeometry(_ command: ConversationCommand)
	{
		let width = view.bounds.width
		commandHeightConstraint?.constant = Self.commandHeight(
			command.command,
			width: width
		)
		shellHeightConstraint?.constant = Self.shellHeight(
			command: command,
			width: width
		)
	}

	private static func commandText(_ command: String) -> NSAttributedString
	{
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byWordWrapping
		paragraph.lineSpacing = terminalLineSpacing
		return NSAttributedString(
			string: "$ \(command)",
			attributes: [
				.font: terminalFont,
				.foregroundColor: DesktopTheme.terminalText,
				.paragraphStyle: paragraph
			]
		)
	}

	private static func commandHeight(
		_ command: String,
		width: CGFloat
	) -> CGFloat
	{
		// Match the two-line preview and keep its 24pt copy target inside the command area.
		let text = commandText(String(command.prefix(maximumShellSampleLength)))
		let measured = text.boundingRect(
			with: NSSize(
				width: max(
					1,
					width - 20 - 28
				),
				height: .greatestFiniteMagnitude
			),
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		).height
		return max(
			24,
			min(
				ceil(measured),
				terminalLineHeight * 2 - terminalLineSpacing
			)
		)
	}

	private static func shellHeight(
		command: ConversationCommand,
		width: CGFloat
	) -> CGFloat
	{
		// Unwrapped lines determine height independently of the transcript width.
		let sample = String(command.output.prefix(maximumShellSampleLength))
		let lineCount = sample.reduce(1)
		{
			$1 == "\n" ? $0 + 1 : $0
		}
		let previewHeight = commandHeight(
			command.command,
			width: width
		)
		let outputHeight = max(
			24,
			ceil(CGFloat(min(
				lineCount,
				20
			)) * terminalLineHeight) + 6
		)
		return min(
			maximumShellHeight,
			max(
				minimumShellHeight,
				previewHeight + outputHeight + 76
			)
		)
	}

	private static func shellStatus(_ command: ConversationCommand) -> String
	{
		if let code = command.exitCode, code != 0
		{
			return "Exit code \(code)"
		}
		let failure = failureText(command)
		if !failure.isEmpty
		{
			return failure
		}
		if command.status == "completed"
		{
			return command.exitCode == 0 ? "✓ Success" : "Completed"
		}
		return "Running…"
	}

	private static func failureText(_ command: ConversationCommand?) -> String
	{
		guard let command
		else
		{
			return ""
		}
		if let code = command.exitCode, code != 0
		{
			return "Exit \(code)"
		}
		if command.status == "failed"
		{
			return "Failed"
		}
		if command.status == "declined"
		{
			return "Declined"
		}
		if ["interrupted", "cancelled", "canceled", "stopped"].contains(command.status)
		{
			return "Interrupted"
		}
		return ""
	}

	func writeCommand(to pasteboard: NSPasteboard)
	{
		guard let command = row?.command
		else
		{
			return
		}
		writeShellText(
			command.command,
			to: pasteboard
		)
	}

	func writeOutput(to pasteboard: NSPasteboard)
	{
		guard let command = row?.command
		else
		{
			return
		}
		writeShellText(
			command.output,
			to: pasteboard
		)
	}

	private func writeShellText(
		_ text: String,
		to pasteboard: NSPasteboard
	)
	{
		pasteboard.clearContents()
		pasteboard.setString(
			text,
			forType: .string
		)
	}

	@objc private func copyCommand()
	{
		writeCommand(to: .general)
	}

	@objc private func copyOutput()
	{
		writeOutput(to: .general)
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

	private static func metadata(_ command: ConversationCommand) -> String
	{
		var parts = [command.status]
		if let cwd = command.cwd
		{
			parts.append(cwd)
		}
		if let exitCode = command.exitCode
		{
			parts.append("Exit \(exitCode)")
		}
		if let milliseconds = command.durationMs
		{
			parts.append(String(
				format: "%.1fs",
				max(
					0,
					milliseconds
				) / 1000
			))
		}
		return parts.joined(separator: " · ")
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
		if let cached = Self.imageCache.object(forKey: path as NSString)
		{
			showImage(cached)
			return
		}
		imageTask = Task
		{
			[weak self] in
			let thumbnail = await Task.detached(priority: .utility)
			{
				ActivityImageThumbnail.load(path: path)
			}.value
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
			Self.imageCache.countLimit = 32
			Self.imageCache.setObject(
				image,
				forKey: path as NSString
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
		if let path = row?.imagePath
		{
			onOpenFile?(path)
		}
	}
}

private struct ActivityImageThumbnail: @unchecked Sendable
{
	let image: CGImage
	static func load(path: String) -> ActivityImageThumbnail?
	{
		guard let source = CGImageSourceCreateWithURL(
			URL(fileURLWithPath: path) as CFURL,
			nil
		),
			let image = CGImageSourceCreateThumbnailAtIndex(
				source,
				0,
				[
					kCGImageSourceCreateThumbnailFromImageAlways: true,
					kCGImageSourceThumbnailMaxPixelSize: 240,
					kCGImageSourceCreateThumbnailWithTransform: true,
				] as CFDictionary
			)
		else
		{
			return nil
		}
		return ActivityImageThumbnail(image: image)
	}
}
