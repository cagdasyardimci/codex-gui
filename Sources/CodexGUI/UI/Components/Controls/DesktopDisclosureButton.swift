import AppKit

/// A native disclosure control owns its label, reserved indicator slot, focus and expansion state.
@MainActor
final class DesktopDisclosureButton: DesktopAttributedTitleButton
{
	enum Presentation
	{
		case normal, compact, hoverReveal, output, summary, fileList

		var rowHeight: CGFloat
		{
			switch self
			{
			case .normal, .output: 24
			case .compact: 20
			case .hoverReveal: 21
			case .summary: NSView.noIntrinsicMetric
			case .fileList: 36
			}
		}
	}

	static let collapsedFileCount = 3

	private let presentation: Presentation
	private var subject: String?
	private var semanticExpanded = false
	private var fileCount = 0
	private var pointerTracking: NSTrackingArea?
	private var isHovered = false
	private var isContextHovered = false
	private var hasKeyboardFocus = false
	private let reservedIcon = NSImage(size: NSSize(
		width: 16,
		height: 16
	))

	init(
		title: String = "",
		expanded: Bool = false,
		presentation: Presentation = .normal,
		target: AnyObject? = nil,
		action: Selector? = nil
	)
	{
		self.presentation = presentation
		super.init(frame: .zero)
		self.title = title
		self.target = target
		self.action = action
		isBordered = false
		switch presentation
		{
		case .summary: font = AppKitFontResolver.font(TypographyTokens.Summary.body)
		case .output: font = AppKitFontResolver.font(TypographyTokens.Controls.button)
		case .fileList: font = .systemFont(ofSize: 13)
		default: font = .systemFont(ofSize: presentation == .compact ? 13 : 14)
		}
		if presentation == .output
		{
			bezelStyle = .inline
			controlSize = .small
		}
		switch presentation
		{
		case .summary: contentTintColor = AppKitColorTokens.captionText
		case .fileList: contentTintColor = MarkdownAttributedStringRenderer.proseColor
		default: contentTintColor = .secondaryLabelColor
		}
		alignment = .left
		imagePosition = title.isEmpty ? .imageOnly : .imageTrailing
		if presentation == .summary
		{
			imageScaling = .scaleProportionallyDown
		}
		else if presentation != .fileList
		{
			focusRingType = .exterior
			refusesFirstResponder = false
			cell?.lineBreakMode = .byTruncatingTail
			if let cell = cell as? NSButtonCell
			{
				cell.highlightsBy = []
				cell.showsStateBy = []
			}
		}
		setLabel(title)
		setExpanded(expanded)
		if presentation == .fileList
		{
			isHidden = true
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var state: NSControl.StateValue
	{
		didSet
		{
			refreshIndicator()
		}
	}

	func setExpanded(_ expanded: Bool)
	{
		if presentation == .summary || presentation == .fileList
		{
			semanticExpanded = expanded
			if presentation == .fileList
			{
				let remaining = max(
					0,
					fileCount - Self.collapsedFileCount
				)
				setLabel(expanded ? "Collapse files"
					: "Show \(remaining) more \(remaining == 1 ? "file" : "files")")
			}
			else
			{
				refreshIndicator()
			}
			return
		}
		state = expanded ? .on : .off
		if presentation == .output
		{
			setLabel(expanded ? "Hide output" : "Show output")
		}
		else
		{
			refreshIndicator()
		}
	}

	func configureFileList(
		count: Int,
		expanded: Bool
	)
	{
		precondition(presentation == .fileList)
		fileCount = max(
			0,
			count
		)
		isHidden = fileCount <= Self.collapsedFileCount
		setExpanded(expanded)
	}

	func setLabel(_ label: String)
	{
		title = label
		if presentation == .fileList
		{
			imagePosition = .imageRight
		}
		else
		{
			let attributes: [NSAttributedString.Key: Any] = [
				.font: font ?? NSFont.systemFont(ofSize: 14),
				.foregroundColor: presentation == .summary
					? AppKitColorTokens.captionText : NSColor.secondaryLabelColor
			]
			attributedTitle = NSAttributedString(
				string: label,
				attributes: attributes
			)
			if presentation != .summary
			{
				attributedAlternateTitle = attributedTitle
			}
			imagePosition = label.isEmpty ? .imageOnly
				: (presentation == .output ? .imageLeading : .imageTrailing)
		}
		invalidateIntrinsicContentSize()
		refreshIndicator()
	}

	func setSubject(_ subject: String?)
	{
		self.subject = subject
		refreshIndicator()
	}

	func setContextHovered(_ hovered: Bool)
	{
		isContextHovered = hovered
		refreshIndicator()
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		pointerTracking = DesktopHoverTracking.replace(
			in: self,
			previous: pointerTracking
		)
		if let window, window.isKeyWindow
		{
			let point = convert(
				window.mouseLocationOutsideOfEventStream,
				from: nil
			)
			isHovered = !isHidden && visibleRect.contains(point)
		}
		else
		{
			isHovered = false
		}
		refreshIndicator()
	}

	override func mouseEntered(with event: NSEvent)
	{
		isHovered = true
		refreshIndicator()
	}

	override func mouseExited(with event: NSEvent)
	{
		isHovered = false
		refreshIndicator()
	}

	override func becomeFirstResponder() -> Bool
	{
		let accepted = super.becomeFirstResponder()
		if accepted
		{
			hasKeyboardFocus = true
			refreshIndicator()
		}
		return accepted
	}

	override func resignFirstResponder() -> Bool
	{
		let accepted = super.resignFirstResponder()
		if accepted
		{
			hasKeyboardFocus = false
			refreshIndicator()
		}
		return accepted
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		isHovered = false
		hasKeyboardFocus = false
		refreshIndicator()
	}

	private func refreshIndicator()
	{
		let expanded = presentation == .summary || presentation == .fileList
			? semanticExpanded : state == .on
		let visible = presentation != .hoverReveal || expanded || isHovered
			|| isContextHovered || hasKeyboardFocus
		if presentation == .summary
		{
			image = expanded ? nil : DesktopIcons.image(.chevronRight)
		}
		else if presentation == .fileList
		{
			image = NSImage(
				systemSymbolName: expanded ? "chevron.up" : "chevron.down",
				accessibilityDescription: nil
			)
		}
		else if presentation == .output
		{
			image = DesktopIcons.image(expanded ? .chevronUp : .chevronDown)
		}
		else
		{
			let indicator = DesktopDisclosureIndicator(
				expanded: expanded,
				visible: visible
			)
			image = indicator.icon.map
			{
				DesktopIcons.image($0)
			} ?? reservedIcon
		}
		setAccessibilityValue(expanded ? "Expanded" : "Collapsed")
		let accessibleTitle = subject ?? title
		if presentation == .summary
		{
			setAccessibilityLabel(title)
			toolTip = expanded ? "Collapse sources" : "Expand sources"
		}
		else if presentation == .fileList
		{
			setAccessibilityLabel(title)
		}
		else if presentation == .output
		{
			setAccessibilityLabel(title)
			toolTip = title
		}
		else
		{
			setAccessibilityLabel(accessibleTitle.isEmpty ? (expanded ? "Collapse" : "Expand")
				: "\(expanded ? "Collapse" : "Expand") \(accessibleTitle)")
		}
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if presentation == .fileList
		{
			MarkdownTextDrawing.withAntialiasing
			{
				super.draw(dirtyRect)
			}
		}
		else
		{
			super.draw(dirtyRect)
		}
	}

	override var intrinsicContentSize: NSSize
	{
		let native = super.intrinsicContentSize
		if presentation == .summary
		{
			return native
		}
		if presentation == .fileList
		{
			return NSSize(
				width: native.width,
				height: presentation.rowHeight
			)
		}
		return NSSize(
			width: max(
				24,
				native.width
			),
			height: presentation.rowHeight
		)
	}
}
