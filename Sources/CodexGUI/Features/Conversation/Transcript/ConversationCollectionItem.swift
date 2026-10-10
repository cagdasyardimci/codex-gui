import AppKit

@MainActor
private final class CodeCopyButton: NSButton, DesktopControlCursorProviding
{
	var controlCursor: NSCursor
	{
		.arrow
	}
	private var hoverTrackingArea: NSTrackingArea?
	private var isHovered = false
	private var tooltipPanel: NSPanel?
	private var tooltipAppearance: DesktopPanelAppearanceBinding?

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let hoverTrackingArea
		{
			removeTrackingArea(hoverTrackingArea)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		hoverTrackingArea = area
	}

	override func resetCursorRects()
	{
		super.resetCursorRects()
		addCursorRect(
			bounds,
			cursor: .arrow
		)
	}

	override func cursorUpdate(with event: NSEvent)
	{
		NSCursor.arrow.set()
	}

	override func mouseEntered(with event: NSEvent)
	{
		hideCopyTooltip()
		NSCursor.arrow.set()
		isHovered = true
		contentTintColor = .labelColor
		needsDisplay = true
		perform(
			#selector(showCopyTooltip),
			with: nil,
			afterDelay: 0.4
		)
	}

	override func mouseExited(with event: NSEvent)
	{
		isHovered = false
		hideCopyTooltip()
		contentTintColor = .secondaryLabelColor
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent)
	{
		hideCopyTooltip()
		super.mouseDown(with: event)
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		resetInteraction()
		super.viewWillMove(toWindow: newWindow)
	}

	func resetInteraction()
	{
		hideCopyTooltip()
		isHovered = false
		contentTintColor = .secondaryLabelColor
		needsDisplay = true
	}

	@objc private func showCopyTooltip()
	{
		guard isHovered, let window, !isHiddenOrHasHiddenAncestor
		else
		{
			return
		}
		let label = NSTextField(labelWithString: "Copy code")
		label.font = .systemFont(ofSize: 12)
		label.textColor = .labelColor
		label.sizeToFit()
		let size = NSSize(
			width: label.frame.width + 24,
			height: 28
		)
		let surface = DesktopSurface(
			DesktopTheme.inspector,
			cornerRadius: 12,
			bordered: true
		)
		surface.frame = NSRect(
			origin: .zero,
			size: size
		)
		label.frame.origin = NSPoint(
			x: 12,
			y: (size.height - label.frame.height) / 2
		)
		surface.addSubview(label)
		let panel = NSPanel(
			contentRect: NSRect(
				origin: .zero,
				size: size
			),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		panel.ignoresMouseEvents = true
		panel.contentView = surface
		tooltipAppearance = DesktopPanelAppearanceBinding(
			panel: panel,
			source: self
		)
		let screenRect = window.convertToScreen(convert(
			bounds,
			to: nil
		))
		panel.setFrameOrigin(NSPoint(
			x: screenRect.midX - size.width / 2,
			y: screenRect.maxY + 4
		))
		window.addChildWindow(
			panel,
			ordered: .above
		)
		tooltipPanel = panel
	}

	private func hideCopyTooltip()
	{
		NSObject.cancelPreviousPerformRequests(
			withTarget: self,
			selector: #selector(showCopyTooltip),
			object: nil
		)
		tooltipAppearance?.invalidate()
		tooltipAppearance = nil
		if let tooltipPanel
		{
			tooltipPanel.parent?.removeChildWindow(tooltipPanel)
			tooltipPanel.orderOut(nil)
		}
		tooltipPanel = nil
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if isHovered && isEnabled
		{
			NSColor.labelColor.withAlphaComponent(0.1).setFill()
			let diameter = min(
				bounds.width,
				bounds.height
			)
			NSBezierPath(ovalIn: NSRect(
				x: bounds.midX - diameter / 2,
				y: bounds.midY - diameter / 2,
				width: diameter,
				height: diameter
			)).fill()
		}
		super.draw(dirtyRect)
	}
}

@MainActor
final class ConversationCollectionItem: NSCollectionViewItem, NSLayoutManagerDelegate
{
	private static let rowSpacing: CGFloat = 6
	private static let replyActionSpacing: CGFloat = 8.5
	private static let titleHeight: CGFloat = 16
	private static let buttonHeight: CGFloat = 24
	private static let codeCopyButtonSize: CGFloat = 32
	private static let bodyMeasurer = ConversationBodyMeasurer()

	private let titleLabel = NSTextField(labelWithString: "")
	private let bodyTextView = ConversationMarkdownTextView()
	private let messageContainer = NSView()
	private let imageAttachmentsView = UserMessageImageAttachmentsView()
	private var imageAttachmentCount = 0
	private var messageTopConstraint: NSLayoutConstraint?
	private let contentStack = NSStackView()
	private let replyActions = ConversationReplyActionsView()
	private var showsReplyActions = false
	private let userSurface = DesktopSurface(
		DesktopTheme.userBubble,
		cornerRadius: 20
	)
	private let activitySurface = DesktopSurface(
		DesktopTheme.elevated,
		cornerRadius: 12,
		bordered: true
	)
	private var copyButtons: [CodeCopyButton] = []
	private var configuredEntryID: Data?
	private let expandButton = NSButton(
		title: "Show output",
		target: nil,
		action: nil
	)
	private var bodyHeightConstraint: NSLayoutConstraint?
	private var messageWidthConstraint: NSLayoutConstraint?
	private var leadingInsetConstraint: NSLayoutConstraint?
	private var trailingInsetConstraint: NSLayoutConstraint?
	private var topInsetConstraint: NSLayoutConstraint?
	private var bottomInsetConstraint: NSLayoutConstraint?
	private var onToggle: (() -> Void)?
	private var content: PreparedConversationContent?
	private var kind: ConversationEntryKind = .agent
	private var isExpandable = false
	private var codeBlocks: [String] = []
	private var updatingCopyButtonFrames = false
	private weak var observedClipView: NSClipView?
	private var cachedLayoutMetrics:
		(availableWidth: CGFloat, messageWidth: CGFloat, bodyHeight: CGFloat)?

	override func prepareForReuse()
	{
		super.prepareForReuse()
		removeCodeCopyButtons(startingAt: 0)
		configuredEntryID = nil
		onToggle = nil
		content = nil
		codeBlocks.removeAll()
		cachedLayoutMetrics = nil
		imageAttachmentsView.configure([])
		imageAttachmentCount = 0
		showsReplyActions = false
		replyActions.reset()
	}

	override func loadView()
	{
		let container = makeMessageContainerView()
		configureMessageText()
		configureExpansionButton()
		installContentStack()
		view = container
	}

	private func makeMessageContainerView() -> NSView
	{
		let container = NSView()
		messageContainer.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(messageContainer)
		container.addSubview(imageAttachmentsView)
		imageAttachmentsView.isHidden = true
		messageWidthConstraint = messageContainer.widthAnchor.constraint(equalToConstant: 1)
		messageWidthConstraint?.isActive = true
		messageTopConstraint = messageContainer.topAnchor.constraint(equalTo: container.topAnchor)
		NSLayoutConstraint.activate([
			messageContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			messageTopConstraint!,
			messageContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
		])
		for surface in [userSurface, activitySurface]
		{
			AppKitLayout.pin(
				surface,
				to: messageContainer,
				inset: 0
			)
			surface.isHidden = true
		}
		return container
	}

	private func configureMessageText()
	{
		titleLabel.font = .systemFont(
			ofSize: 12,
			weight: .medium
		)
		titleLabel.textColor = .secondaryLabelColor
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.heightAnchor.constraint(equalToConstant: Self.titleHeight).isActive = true

		bodyTextView.isEditable = false
		bodyTextView.isSelectable = true
		bodyTextView.isHorizontallyResizable = false
		bodyTextView.isVerticallyResizable = false
		bodyTextView.drawsBackground = false
		bodyTextView.linkTextAttributes = [
			.foregroundColor: ConversationAttributedStringRenderer.linkColor,
			.underlineStyle: 0,
		]
		bodyTextView.textContainer?.replaceLayoutManager(ConversationMarkdownLayoutManager())
		bodyTextView.layoutManager?.delegate = self
		bodyTextView.textContainerInset = .zero
		bodyTextView.textContainer?.lineFragmentPadding = 0
		bodyTextView.textContainer?.widthTracksTextView = true
		bodyHeightConstraint = bodyTextView.heightAnchor.constraint(equalToConstant: 1)
		// The collection view can retain the old row height while reply actions are added.
		// Keep the measured text height unless that temporary frame cannot fit it.
		bodyHeightConstraint?.priority = NSLayoutConstraint.Priority(999)
		bodyHeightConstraint?.isActive = true
	}

	private func configureExpansionButton()
	{
		expandButton.target = self
		expandButton.action = #selector(toggleExpanded)
		DesktopTheme.styleButton(
			expandButton,
			icon: .chevronDown
		)
		expandButton.heightAnchor.constraint(equalToConstant: Self.buttonHeight).isActive = true
		expandButton.isHidden = true
	}

	private func installContentStack()
	{
		let stack = contentStack
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = Self.rowSpacing
		stack.addArrangedSubview(bodyTextView)
		stack.translatesAutoresizingMaskIntoConstraints = false
		messageContainer.addSubview(stack)
		leadingInsetConstraint = stack.leadingAnchor.constraint(
			equalTo: messageContainer.leadingAnchor
		)
		trailingInsetConstraint = stack.trailingAnchor.constraint(
			equalTo: messageContainer.trailingAnchor
		)
		topInsetConstraint = stack.topAnchor.constraint(equalTo: messageContainer.topAnchor)
		bottomInsetConstraint = stack.bottomAnchor
			.constraint(equalTo: messageContainer.bottomAnchor)
		NSLayoutConstraint.activate([
			leadingInsetConstraint!,
			trailingInsetConstraint!,
			topInsetConstraint!,
			bottomInsetConstraint!,
			bodyTextView.widthAnchor.constraint(equalTo: stack.widthAnchor),
		])
	}

	override func viewDidLayout()
	{
		super.viewDidLayout()
		guard view.window != nil, !view.isHiddenOrHasHiddenAncestor, !view.visibleRect.isEmpty
		else
		{
			return
		}
		updateBodyHeight()
		layoutImageAttachments()
		updateCopyButtonFrames()
	}

	override func viewDidAppear()
	{
		super.viewDidAppear()
		stopObservingClipView()
		if let clipView = view.enclosingScrollView?.contentView
		{
			observedClipView = clipView
			clipView.postsBoundsChangedNotifications = true
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(scrollBoundsDidChange),
				name: NSView.boundsDidChangeNotification,
				object: clipView
			)
		}
		refreshVisibleGeometry()
	}

	override func viewDidDisappear()
	{
		super.viewDidDisappear()
		stopObservingClipView()
	}

	private func stopObservingClipView()
	{
		guard let observedClipView
		else
		{
			return
		}
		NotificationCenter.default.removeObserver(
			self,
			name: NSView.boundsDidChangeNotification,
			object: observedClipView
		)
		self.observedClipView = nil
	}

	@objc private func scrollBoundsDidChange()
	{
		refreshVisibleGeometry()
	}

	private func refreshVisibleGeometry()
	{
		guard view.window != nil, !view.isHiddenOrHasHiddenAncestor, !view.visibleRect.isEmpty
		else
		{
			return
		}
		updateBodyHeight()
		updateCopyButtonFrames()
	}

	func configure(
		_ entry: ConversationEntry,
		content: PreparedConversationContent,
		expanded: Bool,
		showsReplyActions: Bool = false,
		bookmarked: Bool = false,
		onToggleBookmark: (() -> Void)? = nil,
		onToggle: @escaping () -> Void
	)
	{
		_ = view
		let entryID = Data(entry.id.utf8)
		if configuredEntryID != entryID
		{
			removeCodeCopyButtons(startingAt: 0)
			configuredEntryID = entryID
		}
		if self.content !== content
		{
			bodyTextView.dismissExpandedImage()
		}
		self.content = content
		self.onToggle = onToggle
		kind = entry.kind
		self.showsReplyActions = showsReplyActions && kind == .agent
		if self.showsReplyActions
		{
			replyActions.configure(
				source: entry.body,
				bookmarked: bookmarked,
				onToggleBookmark: onToggleBookmark
			)
		}
		else
		{
			replyActions.reset()
		}
		let attachments = kind == .user ? entry.imageAttachments : []
		imageAttachmentCount = attachments.count
		imageAttachmentsView.configure(attachments)
		isExpandable = entry.isExpandable
		cachedLayoutMetrics = nil
		titleLabel.stringValue = entry.title
		titleLabel.setAccessibilityLabel(entry.title)
		titleLabel.isHidden = kind == .user || kind == .agent
		messageContainer.isHidden = imageAttachmentCount > 0 && content.attributedString.length == 0
		userSurface.isHidden = kind != .user || messageContainer.isHidden
		activitySurface.isHidden = kind == .user || kind == .agent
		bodyTextView.textStorage?.setAttributedString(Self.displayText(
			content,
			kind: kind
		))
		bodyTextView.loadWebLinkFavicons()
		bodyTextView.updateSourceAccessibilityHelp()
		bodyTextView.setAccessibilityLabel("\(entry.title) content")
		view.setAccessibilityLabel(entry.title)

		updateCodeCopyButtons(for: content)

		expandButton.isHidden = !entry.isExpandable
		expandButton.title = expanded ? "Hide output" : "Show output"
		expandButton.image = DesktopIcons.image(expanded ? .chevronUp : .chevronDown)
		expandButton.setAccessibilityLabel(expandButton.title)
		expandButton.toolTip = expandButton.title
		// Keep unused controls outside the hierarchy so collection-view reuse cannot expose them.
		var arrangedViews: [NSView] = [bodyTextView]
		if !titleLabel.isHidden
		{
			arrangedViews.insert(
				titleLabel,
				at: 0
			)
		}
		if isExpandable
		{
			arrangedViews.append(expandButton)
		}
		if self.showsReplyActions
		{
			arrangedViews.append(replyActions)
		}
		contentStack.setViews(
			arrangedViews,
			in: .top
		)
		for arrangedView in arrangedViews
		{
			contentStack.setCustomSpacing(
				Self.rowSpacing,
				after: arrangedView
			)
		}
		if self.showsReplyActions, arrangedViews.count > 1
		{
			contentStack.setCustomSpacing(
				Self.replyActionSpacing,
				after: arrangedViews[arrangedViews.count - 2]
			)
		}
		updateBodyHeight()
		layoutImageAttachments()
		updateCopyButtonFrames()
	}

	func setReplyBookmarked(_ bookmarked: Bool)
	{
		replyActions.setBookmarked(bookmarked)
	}

	private func layoutImageAttachments()
	{
		let height = UserMessageImageAttachmentsView.height(
			count: imageAttachmentCount,
			width: view.bounds.width
		)
		imageAttachmentsView.frame = NSRect(
			x: 0,
			y: view.bounds.height - height,
			width: view.bounds.width,
			height: height
		)
		imageAttachmentsView.needsLayout = true
	}

	private func updateCodeCopyButtons(for content: PreparedConversationContent)
	{
		codeBlocks = content.codeBlocks
		removeCodeCopyButtons(startingAt: codeBlocks.count)
		while copyButtons.count < codeBlocks.count
		{
			let button = CodeCopyButton(
				title: "",
				target: self,
				action: #selector(copyCode(_:))
			)
			DesktopTheme.styleButton(
				button,
				icon: .copy
			)
			button.imagePosition = .imageOnly
			button.toolTip = nil
			button.setAccessibilityHelp("Copy code")
			button.lineBreakMode = .byTruncatingTail
			messageContainer.addSubview(
				button,
				positioned: .above,
				relativeTo: contentStack
			)
			copyButtons.append(button)
		}
		for (index, button) in copyButtons.enumerated()
		{
			button.tag = index
			button.target = self
			button.action = #selector(copyCode(_:))
			button.setAccessibilityLabel("Copy code block \(index + 1)")
		}
	}

	private func removeCodeCopyButtons(startingAt index: Int)
	{
		guard index < copyButtons.count
		else
		{
			return
		}
		for button in copyButtons[index...]
		{
			if button.window?.firstResponder === button
			{
				button.window?.makeFirstResponder(bodyTextView)
			}
			button.resetInteraction()
			button.target = nil
			button.action = nil
			button.tag = -1
			button.removeFromSuperview()
		}
		copyButtons.removeSubrange(index...)
	}

	static func itemSize(
		content: PreparedConversationContent,
		width: CGFloat,
		expandable: Bool,
		kind: ConversationEntryKind = .agent,
		imageAttachmentCount: Int = 0,
		showsReplyActions: Bool = false
	) -> NSSize
	{
		let bodySize = content.cachedSize(
			width: width,
			expandable: expandable,
			presentation: presentation(for: kind)
		)
		{
			let inset = contentInset(for: kind)
			let messageWidth = messageWidth(
				content: content,
				availableWidth: width,
				kind: kind
			)
			let text = displayText(
				content,
				kind: kind
			)
			let textWidth = max(
				1,
				messageWidth - 2 * inset.width
			)
			let bodyHeight = content.cachedBodyHeight(
				width: textWidth,
				presentation: presentation(for: kind)
			)
			{
				bodyMeasurer.height(
					of: text,
					width: textWidth
				)
			}
			let titleAllowance = titleSpacingAllowance(for: kind)
			let expansionAllowance = expandable ? rowSpacing + buttonHeight : 0
			return NSSize(
				width: width,
				height: ceil(2 * inset.height + titleAllowance + bodyHeight + expansionAllowance)
			)
		}
		let size = NSSize(
			width: bodySize.width,
			height: bodySize.height + replyActionAllowance(
				kind: kind,
				showsReplyActions: showsReplyActions
			)
		)
		guard kind == .user, imageAttachmentCount > 0
		else
		{
			return size
		}
		let height = UserMessageImageAttachmentsView.height(
			count: imageAttachmentCount,
			width: width
		)
		return NSSize(
			width: size.width,
			height: content.attributedString.length == 0 ? height
				: size.height + height + UserMessageImageAttachmentsView.spacing
		)
	}

	private static func replyActionAllowance(
		kind: ConversationEntryKind,
		showsReplyActions: Bool
	) -> CGFloat
	{
		kind == .agent && showsReplyActions ? replyActionSpacing + ConversationReplyActionsView
			.height : 0
	}

	static func textReadingAnchor(
		content: PreparedConversationContent,
		width: CGFloat,
		kind: ConversationEntryKind,
		offset: CGFloat,
		imageAttachmentCount: Int = 0
	) -> (character: Int, offset: CGFloat)?
	{
		let attachmentHeight = attachmentAllowance(
			count: imageAttachmentCount,
			width: width
		)
		guard offset >= attachmentHeight
		else
		{
			return nil
		}
		return bodyMeasurer.readingAnchor(
			of: displayText(
				content,
				kind: kind
			),
			atY: offset - bodyOriginY(for: kind) - attachmentHeight,
			width: readingTextWidth(
				content: content,
				width: width,
				kind: kind
			)
		)
	}

	static func textReadingOffset(
		content: PreparedConversationContent,
		width: CGFloat,
		kind: ConversationEntryKind,
		character: Int,
		lineOffset: CGFloat,
		imageAttachmentCount: Int = 0
	) -> CGFloat?
	{
		guard let lineY = bodyMeasurer.lineOrigin(
			of: displayText(
				content,
				kind: kind
			),
			atCharacter: character,
			width: readingTextWidth(
				content: content,
				width: width,
				kind: kind
			)
		)
		else
		{
			return nil
		}
		return attachmentAllowance(
			count: imageAttachmentCount,
			width: width
		)
			+ bodyOriginY(for: kind) + lineY + lineOffset
	}

	private static func attachmentAllowance(
		count: Int,
		width: CGFloat
	) -> CGFloat
	{
		guard count > 0
		else
		{
			return 0
		}
		return UserMessageImageAttachmentsView.height(
			count: count,
			width: width
		)
			+ UserMessageImageAttachmentsView.spacing
	}

	private static func readingTextWidth(
		content: PreparedConversationContent,
		width: CGFloat,
		kind: ConversationEntryKind
	) -> CGFloat
	{
		max(
			1,
			messageWidth(
				content: content,
				availableWidth: width,
				kind: kind
			)
				- 2 * contentInset(for: kind).width
		)
	}

	private static func titleSpacingAllowance(for kind: ConversationEntryKind) -> CGFloat
	{
		kind == .user || kind == .agent ? 0 : titleHeight + rowSpacing
	}

	private static func bodyOriginY(for kind: ConversationEntryKind) -> CGFloat
	{
		let titleAllowance = titleSpacingAllowance(for: kind)
		return contentInset(for: kind).height + titleAllowance
	}

	private static func presentation(for kind: ConversationEntryKind) -> Int
	{
		switch kind
		{
		case .agent: 0
		case .user: 1
		case .command: 2
		case .tool: 3
		case .notice: 4
		}
	}

	private static func contentInset(for kind: ConversationEntryKind) -> NSSize
	{
		switch kind
		{
		case .agent: NSSize(
				width: 0,
				height: 4
			)
		case .user: NSSize(
				width: 16,
				height: 12
			)
		case .command, .tool, .notice: NSSize(
				width: 12,
				height: 10
			)
		}
	}

	private static func messageWidth(
		content: PreparedConversationContent,
		availableWidth: CGFloat,
		kind: ConversationEntryKind
	) -> CGFloat
	{
		guard kind == .user
		else
		{
			return availableWidth
		}
		let maximumWidth = min(
			520,
			max(
				80,
				availableWidth * 0.7
			)
		)
		let naturalWidth = content.cachedNaturalWidth(presentation: presentation(for: kind))
		{
			ceil(displayText(
				content,
				kind: kind
			).size().width) + 32
		}
		return min(
			availableWidth,
			min(
				maximumWidth,
				max(
					80,
					naturalWidth
				)
			)
		)
	}

	private static func displayText(
		_ content: PreparedConversationContent,
		kind: ConversationEntryKind
	) -> NSAttributedString
	{
		guard kind != .agent && kind != .user
		else
		{
			return content.attributedString
		}
		return content.cachedDisplayText(presentation: presentation(for: kind))
		{
			let text = NSMutableAttributedString(attributedString: content.attributedString)
			let range = NSRange(
				location: 0,
				length: text.length
			)
			let paragraph = NSMutableParagraphStyle()
			paragraph.lineSpacing = 2
			paragraph.lineBreakMode = .byCharWrapping
			text.addAttributes(
				[
					.font: NSFont.monospacedSystemFont(
						ofSize: 11,
						weight: .regular
					),
					.foregroundColor: NSColor.secondaryLabelColor,
					.paragraphStyle: paragraph,
				],
				range: range
			)
			return text
		}
	}

	private func updateBodyHeight()
	{
		guard let content, view.bounds.width > 0
		else
		{
			return
		}
		let inset = Self.contentInset(for: kind)
		let attachmentAllowance = content.attributedString.length == 0 ? 0
			: Self.attachmentAllowance(
				count: imageAttachmentCount,
				width: view.bounds.width
			)
		let metrics: (availableWidth: CGFloat, messageWidth: CGFloat, bodyHeight: CGFloat)
		if let cachedLayoutMetrics, cachedLayoutMetrics.availableWidth == view.bounds.width
		{
			metrics = cachedLayoutMetrics
		}
		else
		{
			let size = Self.itemSize(
				content: content,
				width: view.bounds.width,
				expandable: isExpandable,
				kind: kind,
				imageAttachmentCount: imageAttachmentCount,
				showsReplyActions: showsReplyActions
			)
			let titleAllowance = Self.titleSpacingAllowance(for: kind)
			let expandHeight = isExpandable ? Self.rowSpacing + Self.buttonHeight : 0
			let replyAllowance = Self.replyActionAllowance(
				kind: kind,
				showsReplyActions: showsReplyActions
			)
			metrics = (
				view.bounds.width,
				Self.messageWidth(
					content: content,
					availableWidth: view.bounds.width,
					kind: kind
				),
				size.height - 2 * inset.height - titleAllowance - expandHeight
					- attachmentAllowance - replyAllowance
			)
			cachedLayoutMetrics = metrics
		}
		if messageWidthConstraint?.constant != metrics.messageWidth
		{
			messageWidthConstraint?.constant = metrics.messageWidth
		}
		messageTopConstraint?.constant = attachmentAllowance
		if leadingInsetConstraint?.constant != inset.width
		{
			leadingInsetConstraint?.constant = inset.width
			trailingInsetConstraint?.constant = -inset.width
		}
		if topInsetConstraint?.constant != inset.height
		{
			topInsetConstraint?.constant = inset.height
			bottomInsetConstraint?.constant = -inset.height
		}
		if bodyHeightConstraint?.constant != metrics.bodyHeight
		{
			bodyHeightConstraint?.constant = metrics.bodyHeight
		}
	}

	private func updateCopyButtonFrames()
	{
		guard !copyButtons.isEmpty, view.window != nil, !view.isHiddenOrHasHiddenAncestor,
				!view.visibleRect.isEmpty, bodyTextView.bounds.width > 0,
				!updatingCopyButtonFrames,
				let content, let layout = bodyTextView.layoutManager,
				let container = bodyTextView.textContainer
		else
		{
			return
		}
		updatingCopyButtonFrames = true
		defer
		{
			updatingCopyButtonFrames = false
		}
		layout.ensureLayout(for: container)
		for (index, button) in copyButtons.enumerated()
		{
			guard content.codeBlockRanges.indices.contains(index), layout.numberOfGlyphs > 0
			else
			{
				continue
			}
			let range = content.codeBlockRanges[index]
			let characterLocation = min(
				range.location,
				max(
					0,
					bodyTextView.string.utf16.count - 1
				)
			)
			let location = layout.glyphIndexForCharacter(at: characterLocation)
			let header = (layout as? ConversationMarkdownLayoutManager)?.codeBlockHeaderRect(
				atCharacter: characterLocation,
				in: container
			)
			let line = header ?? layout.lineFragmentRect(
				forGlyphAt: location,
				effectiveRange: nil
			)
			let origin = bodyTextView.textContainerOrigin
			let card = (layout as? ConversationMarkdownLayoutManager)?.codeBlockRect(
				atCharacter: characterLocation,
				in: container
			)
			let left = max(
				0,
				origin.x + (card?.minX ?? 0)
			)
			let right = min(
				bodyTextView.bounds.width,
				origin.x + (card?.maxX ?? container.size.width)
			)
			let availableWidth = max(
				0,
				right - left
			)
			let inset = min(
				6,
				availableWidth / 2
			)
			let width = min(
				Self.codeCopyButtonSize,
				availableWidth - 2 * inset
			)
			let textFrame = NSRect(
				x: right - inset - width,
				y: origin.y + line.minY + max(
					0,
					(line.height - Self.codeCopyButtonSize) / 2
				),
				width: width,
				height: Self.codeCopyButtonSize
			)
			let frame = bodyTextView.convert(
				textFrame,
				to: messageContainer
			)
			if button.frame != frame
			{
				button.resetInteraction()
				button.frame = frame
				button.window?.invalidateCursorRects(for: button)
			}
		}
	}

	nonisolated func layoutManager(
		_ layoutManager: NSLayoutManager,
		didCompleteLayoutFor textContainer: NSTextContainer?,
		atEnd _: Bool
	)
	{
		// This text view and its TextKit layout are owned by the main actor.
		precondition(Thread.isMainThread)
		let managerID = ObjectIdentifier(layoutManager)
		let containerID = textContainer.map(ObjectIdentifier.init)
		MainActor.assumeIsolated
		{
			guard managerID == bodyTextView.layoutManager.map(ObjectIdentifier.init),
					containerID == bodyTextView.textContainer.map(ObjectIdentifier.init)
			else
			{
				return
			}
			// Attachment layout can finish after a frame update at the same bounds size.
			// Request a native layout pass rather than querying TextKit inside its callback.
			viewIfLoaded?.needsLayout = true
		}
	}

	@objc private func toggleExpanded()
	{
		onToggle?()
	}

	@objc private func copyCode(_ sender: NSButton)
	{
		writeCodeBlock(
			from: sender,
			to: .general
		)
	}

	func writeCodeBlock(
		from button: NSButton,
		to pasteboard: NSPasteboard
	)
	{
		guard copyButtons.contains(where:
			{
				$0 === button
			}),
			codeBlocks.indices.contains(button.tag)
		else
		{
			return
		}
		pasteboard.clearContents()
		pasteboard.setString(
			codeBlocks[button.tag],
			forType: .string
		)
	}
}

@MainActor
private final class ConversationBodyMeasurer
{
	private let storage = NSTextStorage()
	private let layout = ConversationMarkdownLayoutManager()
	private let container = NSTextContainer(
		size: NSSize(
			width: 1,
			height: CGFloat.greatestFiniteMagnitude
		)
	)
	private weak var text: NSAttributedString?

	init()
	{
		container.lineFragmentPadding = 0
		layout.addTextContainer(container)
		storage.addLayoutManager(layout)
	}

	func height(
		of text: NSAttributedString,
		width: CGFloat
	) -> CGFloat
	{
		prepare(
			text,
			width: width
		)
		return max(
			1,
			ceil(layout.usedRect(for: container).height) + 2
		)
	}

	func readingAnchor(
		of text: NSAttributedString,
		atY y: CGFloat,
		width: CGFloat
	) -> (character: Int, offset: CGFloat)?
	{
		prepare(
			text,
			width: width
		)
		guard layout.numberOfGlyphs > 0, y >= 0, y <= layout.usedRect(for: container).maxY
		else
		{
			return nil
		}
		let glyph = min(
			layout.numberOfGlyphs - 1,
			layout.glyphIndex(
				for: NSPoint(
					x: 0,
					y: y
				),
				in: container
			)
		)
		let line = layout.lineFragmentRect(
			forGlyphAt: glyph,
			effectiveRange: nil
		)
		return (layout.characterIndexForGlyph(at: glyph), y - line.minY)
	}

	func lineOrigin(
		of text: NSAttributedString,
		atCharacter character: Int,
		width: CGFloat
	) -> CGFloat?
	{
		prepare(
			text,
			width: width
		)
		guard character >= 0, character < storage.length, layout.numberOfGlyphs > 0
		else
		{
			return nil
		}
		let glyph = layout.glyphIndexForCharacter(at: character)
		return layout.lineFragmentRect(
			forGlyphAt: glyph,
			effectiveRange: nil
		).minY
	}

	private func prepare(
		_ text: NSAttributedString,
		width: CGFloat
	)
	{
		if self.text !== text
		{
			storage.setAttributedString(text)
			self.text = text
		}
		if container.size.width != width
		{
			container.size = NSSize(
				width: width,
				height: .greatestFiniteMagnitude
			)
		}
		layout.ensureLayout(for: container)
	}
}
