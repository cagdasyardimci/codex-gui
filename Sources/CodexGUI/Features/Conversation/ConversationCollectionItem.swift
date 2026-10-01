import AppKit

@MainActor
final class ConversationCollectionItem: NSCollectionViewItem
{
	private static let rowSpacing: CGFloat = 6
	private static let titleHeight: CGFloat = 16
	private static let buttonHeight: CGFloat = 24
	private static let bodyMeasurer = ConversationBodyMeasurer()

	private let titleLabel = NSTextField(labelWithString: "")
	private let bodyTextView = NSTextView()
	private let messageContainer = NSView()
	private let contentStack = NSStackView()
	private let userSurface = DesktopSurface(
		DesktopTheme.userBubble,
		cornerRadius: 20
	)
	private let activitySurface = DesktopSurface(
		DesktopTheme.elevated,
		cornerRadius: 12,
		bordered: true
	)
	private var copyButtons: [NSButton] = []
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
	private var copyButtonLayoutSize: NSSize?
	private weak var observedClipView: NSClipView?
	private var cachedLayoutMetrics:
		(availableWidth: CGFloat, messageWidth: CGFloat, bodyHeight: CGFloat)?

	override func loadView()
	{
		let container = NSView()
		messageContainer.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(messageContainer)
		messageWidthConstraint = messageContainer.widthAnchor.constraint(equalToConstant: 1)
		messageWidthConstraint?.isActive = true
		NSLayoutConstraint.activate([
			messageContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			messageContainer.topAnchor.constraint(equalTo: container.topAnchor),
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
		bodyTextView.textContainerInset = .zero
		bodyTextView.textContainer?.lineFragmentPadding = 0
		bodyTextView.textContainer?.widthTracksTextView = true
		bodyHeightConstraint = bodyTextView.heightAnchor.constraint(equalToConstant: 1)
		bodyHeightConstraint?.isActive = true

		expandButton.target = self
		expandButton.action = #selector(toggleExpanded)
		DesktopTheme.styleButton(
			expandButton,
			symbol: "chevron.down"
		)
		expandButton.heightAnchor.constraint(equalToConstant: Self.buttonHeight).isActive = true
		expandButton.isHidden = true

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
		view = container
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
		copyButtonLayoutSize = nil
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
		onToggle: @escaping () -> Void
	)
	{
		_ = view
		self.content = content
		self.onToggle = onToggle
		kind = entry.kind
		isExpandable = entry.isExpandable
		cachedLayoutMetrics = nil
		copyButtonLayoutSize = nil
		titleLabel.stringValue = entry.title
		titleLabel.setAccessibilityLabel(entry.title)
		titleLabel.isHidden = kind == .user || kind == .agent
		userSurface.isHidden = kind != .user
		activitySurface.isHidden = kind == .user || kind == .agent
		bodyTextView.textStorage?.setAttributedString(Self.displayText(
			content,
			kind: kind
		))
		bodyTextView.setAccessibilityLabel("\(entry.title) content")
		view.setAccessibilityLabel(entry.title)

		rebuildCodeCopyButtons(for: content)

		expandButton.isHidden = !entry.isExpandable
		expandButton.title = expanded ? "Hide output" : "Show output"
		expandButton.image = NSImage(
			systemSymbolName: expanded ? "chevron.up" : "chevron.down",
			accessibilityDescription: nil
		)
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
		contentStack.setViews(
			arrangedViews,
			in: .top
		)
		updateBodyHeight()
		updateCopyButtonFrames()
	}

	private func rebuildCodeCopyButtons(for content: PreparedConversationContent)
	{
		for button in copyButtons
		{
			button.removeFromSuperview()
		}
		copyButtons.removeAll()
		codeBlocks = content.codeBlocks
		for index in codeBlocks.indices
		{
			let button = NSButton(
				title: "Copy code \(index + 1)",
				target: self,
				action: #selector(copyCode(_:))
			)
			button.tag = index
			DesktopTheme.styleButton(
				button,
				symbol: "doc.on.doc"
			)
			button.lineBreakMode = .byTruncatingTail
			bodyTextView.addSubview(button)
			copyButtons.append(button)
			button.setAccessibilityLabel("Copy code block \(index + 1)")
		}
	}

	static func itemSize(
		content: PreparedConversationContent,
		width: CGFloat,
		expandable: Bool,
		kind: ConversationEntryKind = .agent
	) -> NSSize
	{
		content.cachedSize(
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
			let titleAllowance = kind == .user || kind == .agent ? 0 : titleHeight + rowSpacing
			let expansionAllowance = expandable ? rowSpacing + buttonHeight : 0
			return NSSize(
				width: width,
				height: ceil(2 * inset.height + titleAllowance + bodyHeight + expansionAllowance)
			)
		}
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
			availableWidth * 0.88
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
		guard kind != .agent
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
			paragraph.lineSpacing = kind == .user ? 4 : 2
			paragraph.lineBreakMode = kind == .user ? .byWordWrapping : .byCharWrapping
			text.addAttributes(
				[
					.font: kind == .user
						? NSFont.systemFont(ofSize: 15)
						: NSFont.monospacedSystemFont(
							ofSize: 11,
							weight: .regular
						),
					.foregroundColor: kind == .user ? NSColor.labelColor : NSColor
						.secondaryLabelColor,
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
				kind: kind
			)
			let titleHeight = kind == .user || kind == .agent ? 0 : Self.titleHeight + Self
				.rowSpacing
			let expandHeight = isExpandable ? Self.rowSpacing + Self.buttonHeight : 0
			metrics = (
				view.bounds.width,
				Self.messageWidth(
					content: content,
					availableWidth: view.bounds.width,
					kind: kind
				),
				size.height - 2 * inset.height - titleHeight - expandHeight
			)
			cachedLayoutMetrics = metrics
		}
		if messageWidthConstraint?.constant != metrics.messageWidth
		{
			messageWidthConstraint?.constant = metrics.messageWidth
		}
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
				copyButtonLayoutSize != bodyTextView.bounds.size,
				let content, let layout = bodyTextView.layoutManager,
				let container = bodyTextView.textContainer
		else
		{
			return
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
			let location = min(
				range.location,
				max(
					0,
					layout.numberOfGlyphs - 1
				)
			)
			let line = layout.lineFragmentRect(
				forGlyphAt: location,
				effectiveRange: nil
			)
			let origin = bodyTextView.textContainerOrigin
			button.frame = NSRect(
				x: max(
					0,
					bodyTextView.bounds.width - 94
				),
				y: origin.y + line.minY,
				width: min(
					90,
					bodyTextView.bounds.width
				),
				height: Self.buttonHeight
			)
		}
		copyButtonLayoutSize = bodyTextView.bounds.size
	}

	@objc private func toggleExpanded()
	{
		onToggle?()
	}

	@objc private func copyCode(_ sender: NSButton)
	{
		guard codeBlocks.indices.contains(sender.tag)
		else
		{
			return
		}
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(
			codeBlocks[sender.tag],
			forType: .string
		)
	}
}

@MainActor
private final class ConversationBodyMeasurer
{
	private let storage = NSTextStorage()
	private let layout = NSLayoutManager()
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
		return max(
			1,
			ceil(layout.usedRect(for: container).height) + 2
		)
	}
}
