import AppKit

@MainActor
final class ModelEffortSelectionButton: NSButton
{
	private enum LayoutMetrics
	{
		static let totalHorizontalAllowance: CGFloat = 16
		static let buttonHeight: CGFloat = 28
		static let maximumWidth: CGFloat = 300
		static let pickerMinimumWidth: CGFloat = 164
		static let boltSize = NSSize(
			width: 12,
			height: 14
		)
		static let boltToTitleSpacing: CGFloat = 6
		static let titleToChevronSpacing: CGFloat = 6
		static let chevronArmWidth: CGFloat = 3
		// Preserve the existing extra point beyond the chevron's 8-point span.
		static let chevronExtraWidthAllowance: CGFloat = 1

		static var boltReservedWidth: CGFloat
		{
			boltSize.width + boltToTitleSpacing
		}

		static var chevronSpanWidth: CGFloat
		{
			chevronArmWidth * 2
		}

		static var trailingReservedWidth: CGFloat
		{
			titleToChevronSpacing + chevronSpanWidth + chevronExtraWidthAllowance
		}
	}

	private struct ContentLayout
	{
		let boltRect: NSRect
		let textRect: NSRect
		let chevronOriginX: CGFloat
	}

	private var summary: String?
	private var effortTitle: String?
	private var fastMode = false
	private var isPickerPresented = false
	private weak var observedWindow: NSWindow?

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)

		isBordered = false
		bezelStyle = .inline
		focusRingType = .none
		font = .systemFont(ofSize: 13)
		image = nil

		update(
			summary: nil,
			fastMode: false,
			isPickerPresented: false
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func update(
		summary: String?,
		effortTitle: String? = nil,
		fastMode: Bool,
		isPickerPresented: Bool
	)
	{
		self.summary = summary.flatMap
		{
			$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
		}
		self.effortTitle = effortTitle
		self.fastMode = fastMode
		self.isPickerPresented = isPickerPresented
		title = displayedTitle

		let selectionDescription = self.summary ?? "Select effort"
		toolTip = fastMode ? "\(selectionDescription) · Fast mode enabled" : selectionDescription
		setAccessibilityLabel("Model and effort: \(selectionDescription)")
		setAccessibilityValue(fastMode ? "Fast mode enabled" : "Standard speed")
		setAccessibilityHelp("Open model, reasoning effort, and speed settings")

		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	private var displayedTitle: String
	{
		isPickerPresented ? "Select effort" : summary ?? "Select effort"
	}

	private var displaysBolt: Bool
	{
		fastMode && !isPickerPresented && summary != nil
	}

	private var textFont: NSFont
	{
		font ?? .systemFont(ofSize: 13)
	}

	private var naturalTextSize: NSSize
	{
		(displayedTitle as NSString).size(withAttributes: [.font: textFont])
	}

	private var leadingReservedWidth: CGFloat
	{
		displaysBolt ? LayoutMetrics.boltReservedWidth : 0
	}

	override var intrinsicContentSize: NSSize
	{
		let contentWidth = ceil(naturalTextSize.width)
			+ LayoutMetrics.totalHorizontalAllowance
			+ LayoutMetrics.trailingReservedWidth
			+ leadingReservedWidth
		let minimumWidth: CGFloat = isPickerPresented ? LayoutMetrics.pickerMinimumWidth : 1
		let buttonWidth = min(
			LayoutMetrics.maximumWidth,
			max(
				minimumWidth,
				contentWidth
			)
		)

		return NSSize(
			width: buttonWidth,
			height: LayoutMetrics.buttonHeight
		)
	}

	override func draw(_ dirtyRect: NSRect)
	{
		let shouldDrawSelectionBackground =
			isPickerPresented || cell?.isHighlighted == true

		if shouldDrawSelectionBackground
		{
			DesktopTheme.selection.setFill()
			selectionOutline().fill()
		}

		let tint: NSColor = isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
		let layout = makeContentLayout()

		if displaysBolt
		{
			drawBolt(
				in: layout.boltRect,
				tint: tint
			)
		}

		drawTitle(
			in: layout.textRect,
			tint: tint
		)
		drawChevron(
			layout: layout,
			tint: tint
		)
	}

	private func makeContentLayout() -> ContentLayout
	{
		let textSize = naturalTextSize
		let leadingWidth = leadingReservedWidth
		let availableWidth = max(
			0,
			bounds.width - LayoutMetrics.totalHorizontalAllowance
		)
		let naturalContentWidth =
			textSize.width + leadingWidth + LayoutMetrics.trailingReservedWidth
		let contentWidth = min(
			availableWidth,
			naturalContentWidth
		)
		let textWidth = max(
			0,
			contentWidth - leadingWidth - LayoutMetrics.trailingReservedWidth
		)
		let contentOriginX = bounds.midX - contentWidth / 2

		let boltRect = NSRect(
			x: contentOriginX,
			y: bounds.midY - LayoutMetrics.boltSize.height / 2,
			width: LayoutMetrics.boltSize.width,
			height: LayoutMetrics.boltSize.height
		)
		let textRect = NSRect(
			x: contentOriginX + leadingWidth,
			y: bounds.midY - textSize.height / 2,
			width: textWidth,
			height: textSize.height
		)

		let chevronOriginX = textRect.maxX + LayoutMetrics.titleToChevronSpacing

		return ContentLayout(
			boltRect: boltRect,
			textRect: textRect,
			chevronOriginX: chevronOriginX
		)
	}

	private func drawBolt(
		in rect: NSRect,
		tint: NSColor
	)
	{
		DesktopIcons.draw(
			.bolt,
			in: rect,
			tint: tint
		)
	}

	private func drawTitle(
		in rect: NSRect,
		tint: NSColor
	)
	{
		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.lineBreakMode = .byTruncatingMiddle

		let title = NSMutableAttributedString(
			string: displayedTitle,
			attributes: [
				.font: textFont,
				.foregroundColor: isEnabled ? NSColor.labelColor : tint,
				.paragraphStyle: paragraphStyle,
			]
		)
		if !isPickerPresented, let effortTitle, displayedTitle.hasSuffix(" " + effortTitle)
		{
			let effortRange = NSRange(
				location: title.length - (effortTitle as NSString).length,
				length: (effortTitle as NSString).length
			)
			title.addAttribute(
				.foregroundColor,
				value: tint,
				range: effortRange
			)
		}
		title.draw(in: rect)
	}

	private func drawChevron(
		layout: ContentLayout,
		tint: NSColor
	)
	{
		DesktopIcons.draw(
			.chevronDown,
			in: NSRect(
				x: layout.chevronOriginX - 2,
				y: bounds.midY - 5,
				width: 10,
				height: 10
			),
			tint: tint
		)
	}

	private func selectionOutline() -> NSBezierPath
	{
		NSBezierPath(
			roundedRect: bounds,
			xRadius: bounds.height / 2,
			yRadius: bounds.height / 2
		)
	}

	override var focusRingMaskBounds: NSRect
	{
		bounds
	}

	override func drawFocusRingMask()
	{
		selectionOutline().fill()
	}

	override func becomeFirstResponder() -> Bool
	{
		let accepted = super.becomeFirstResponder()
		needsDisplay = true
		return accepted
	}

	override func resignFirstResponder() -> Bool
	{
		let accepted = super.resignFirstResponder()
		needsDisplay = true
		return accepted
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()

		if let observedWindow
		{
			NotificationCenter.default.removeObserver(
				self,
				name: nil,
				object: observedWindow
			)
		}

		observedWindow = window

		if let window
		{
			for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification]
			{
				NotificationCenter.default.addObserver(
					self,
					selector: #selector(windowFocusChanged),
					name: name,
					object: window
				)
			}
		}

		needsDisplay = true
	}

	@objc private func windowFocusChanged()
	{
		needsDisplay = true
	}
}
