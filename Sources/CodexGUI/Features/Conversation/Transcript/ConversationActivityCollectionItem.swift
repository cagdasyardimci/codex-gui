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
	private static let maximumShellHeight: CGFloat = 278
	private var shellHeightConstraint: NSLayoutConstraint?
	private static let imageHeight: CGFloat = 116
	private let stack = NSStackView()
	private var arrangedWidthConstraints: [NSLayoutConstraint] = []
	private let header = NSStackView()
	private var isHeaderHovered = false
	private var displayedDisclosureIcon: DesktopIcon?
	private var hoverSynchronizationTask: Task<Void, Never>?
	private let icon = NSImageView()
	private let titleLabel = NSTextField(labelWithString: "")
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
	private let failure = NSTextField(labelWithString: "")
	private let shell = DesktopSurface(
		DesktopTheme.elevated,
		cornerRadius: 12,
		bordered: true
	)
	private let shellLabel = NSTextField(labelWithString: "Shell")
	private let shellMetadata = NSTextField(labelWithString: "")
	private let output = NSTextView()
	private let scroll = NSScrollView()
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
	private var imageTask: Task<Void, Never>?
	private static let imageCache = NSCache<NSString, NSImage>()

	override func loadView()
	{
		view = NSView()
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 6
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
		titleLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		failure.font = .systemFont(ofSize: 11)
		failure.textColor = .systemRed
	}

	private func configureActivityButtons()
	{
		for button in [fileButton, disclosure, imageButton]
		{
			button.isBordered = false
			button.target = self
			button.setButtonType(.momentaryPushIn)
		}
		fileButton.action = #selector(openFile)
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
		shellHeightConstraint = shell.heightAnchor.constraint(equalToConstant: 100)
		shellHeightConstraint?.isActive = true
		shellLabel.font = .systemFont(ofSize: 13)
		shellLabel.textColor = .secondaryLabelColor
		shellMetadata.font = .systemFont(ofSize: 11)
		shellMetadata.textColor = .secondaryLabelColor
		shellMetadata.lineBreakMode = .byTruncatingTail
		output.isEditable = false
		output.isSelectable = true
		output.drawsBackground = false
		output.font = .monospacedSystemFont(
			ofSize: 12,
			weight: .regular
		)
		output.textColor = .secondaryLabelColor
		output.textContainerInset = NSSize(
			width: 0,
			height: 3
		)
		output.isVerticallyResizable = true
		output.isHorizontallyResizable = false
		output.autoresizingMask = [.width]
		output.textContainer?.widthTracksTextView = true
		output.textContainer?.containerSize = NSSize(
			width: 1,
			height: CGFloat.greatestFiniteMagnitude
		)
		scroll.drawsBackground = false
		scroll.hasVerticalScroller = true
		scroll.documentView = output
		let shellStack = NSStackView(views: [shellLabel, shellMetadata, scroll])
		shellStack.orientation = .vertical
		shellStack.alignment = .leading
		shellStack.spacing = 8
		AppKitLayout.pin(
			shellStack,
			to: shell,
			inset: 12
		)
		scroll.widthAnchor.constraint(equalTo: shellStack.widthAnchor).isActive = true
		scroll.setContentHuggingPriority(
			.defaultLow,
			for: .vertical
		)
		shellMetadata.widthAnchor.constraint(equalTo: shellStack.widthAnchor).isActive = true
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
		output.string = ""
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
		onOpenFile: @escaping (String) -> Void
	)
	{
		_ = view
		imageTask?.cancel()
		let previousPosition = self.row?.id == row.id ? outputReadingPosition() : nil
		if self.row?.id != row.id
		{
			isHeaderHovered = false
		}
		pendingOutputReadingPosition = previousPosition
		self.row = row
		self.onToggle = onToggle
		self.onOpenFile = onOpenFile
		renderHeader(row)
		let arrangedViews = renderExpandedDetails(
			row,
			previousPosition: previousPosition
		)
		arrangeActivityViews(arrangedViews)
		view.setAccessibilityLabel(row.title)
		view.needsLayout = true
	}

	private func renderHeader(_ row: ConversationActivityRow)
	{
		let hasLink = row.filePath != nil && row.linkTitle != nil
		titleLabel.stringValue = hasLink ? "Read" : row.title
		if row.kind == .read, !hasLink, let linkTitle = row.linkTitle, row.title == "Read"
		{
			titleLabel.stringValue = "Read \(linkTitle)"
		}
		titleLabel.toolTip = row.command?.command ?? row.title
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
		var headerViews: [NSView] = [icon, titleLabel]
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
			if hasLink
			{
				headerViews.append(spacer)
			}
			if canExpand
			{
				headerViews.append(disclosure)
			}
		}
		failure.stringValue = Self.failureText(row.command)
		if !failure.stringValue.isEmpty
		{
			headerViews.append(failure)
		}
		header.setViews(
			headerViews,
			in: .leading
		)
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
			let updatedText = "$ \(command.command)" +
				(command.output.isEmpty ? "" : "\n\(command.output)")
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
			output.setAccessibilityLabel("Shell command and output")
			shellMetadata.stringValue = Self.metadata(command)
			shellMetadata.toolTip = shellMetadata.stringValue
			shellHeightConstraint?.constant = Self.shellHeight(
				command: command,
				width: view.bounds.width
			)
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
			) + 6
		}
		else if row.expanded, row.kind == .image
		{
			detail = imageHeight + 6
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
		if !scroll.isHidden, scroll.contentSize.width > 0
		{
			output.setFrameSize(NSSize(
				width: scroll.contentSize.width,
				height: output.frame.height
			))
		}
		if let row, row.expanded, row.kind != .group, let command = row.command
		{
			shellHeightConstraint?.constant = Self.shellHeight(
				command: command,
				width: view.bounds.width
			)
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
		let textHeight = manager.usedRect(for: container).height + output.textContainerInset
			.height * 2
		output.setFrameSize(NSSize(
			width: scroll.contentSize.width,
			height: max(
				scroll.contentSize.height,
				ceil(textHeight)
			)
		))
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

	private static func shellHeight(
		command: ConversationCommand,
		width: CGFloat
	) -> CGFloat
	{
		// Only a bounded prefix is needed to reach the scrolling panel's height cap.
		let commandSample = String(command.command.prefix(8000))
		let remaining = max(
			0,
			8000 - commandSample.count
		)
		let sample = "$ \(commandSample)" +
			(command.output.isEmpty ? "" : "\n" + String(command.output.prefix(remaining)))
		let size = NSAttributedString(
			string: sample,
			attributes: [
				.font: NSFont.monospacedSystemFont(
					ofSize: 12,
					weight: .regular
				)
			]
		).boundingRect(
			with: NSSize(
				width: max(
					1,
					width - 50
				),
				height: maximumShellHeight
			),
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		).height
		return min(
			maximumShellHeight,
			max(
				100,
				ceil(size) + 76
			)
		)
	}

	private static func icon(for row: ConversationActivityRow) -> DesktopIcon
	{
		switch row.kind
		{
		case .read: return .bookOpen
		case .search, .listFiles: return .search
		case .image: return .images
		case .command: return .terminal
		case .group:
			return row.title.hasPrefix("Read") ? .bookOpen :
				(row.title.hasPrefix("Searched") ? .search : .terminal)
		}
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
