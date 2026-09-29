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
		static let chevronArmWidth: CGFloat = 4
		// Preserve the existing extra point beyond the chevron's 8-point span.
		static let chevronExtraWidthAllowance: CGFloat = 1
		static let chevronVerticalOffset: CGFloat = 2
		static let chevronLineWidth: CGFloat = 1.2

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
		let chevronStart: NSPoint
		let chevronTip: NSPoint
		let chevronEnd: NSPoint
	}

	private var summary: String?
	private var fastMode = false
	private var isPickerPresented = false
	private let boltSymbol = NSImage(
		systemSymbolName: "bolt.fill",
		accessibilityDescription: nil
	)
	private weak var observedWindow: NSWindow?

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)

		isBordered = false
		bezelStyle = .inline
		focusRingType = .exterior
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
		fastMode: Bool,
		isPickerPresented: Bool
	)
	{
		self.summary = summary.flatMap
		{
			$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
		}
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
		let hasKeyboardFocus = window?.isKeyWindow == true && window?.firstResponder === self
		let shouldDrawSelectionBackground =
			isPickerPresented || cell?.isHighlighted == true || hasKeyboardFocus

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
		// Flipped views increase Y downward; keep the tip visually below both arms.
		let upwardYDirection: CGFloat = isFlipped ? -1 : 1
		let armY = bounds.midY + upwardYDirection * LayoutMetrics.chevronVerticalOffset
		let tipY = bounds.midY - upwardYDirection * LayoutMetrics.chevronVerticalOffset

		return ContentLayout(
			boltRect: boltRect,
			textRect: textRect,
			chevronStart: NSPoint(
				x: chevronOriginX,
				y: armY
			),
			chevronTip: NSPoint(
				x: chevronOriginX + LayoutMetrics.chevronArmWidth,
				y: tipY
			),
			chevronEnd: NSPoint(
				x: chevronOriginX + LayoutMetrics.chevronSpanWidth,
				y: armY
			)
		)
	}

	private func drawBolt(
		in rect: NSRect,
		tint: NSColor
	)
	{
		let sizeConfiguration = NSImage.SymbolConfiguration(
			pointSize: 12,
			weight: .regular
		)
		let sizedSymbol = boltSymbol?.withSymbolConfiguration(sizeConfiguration)
		let colorConfiguration = NSImage.SymbolConfiguration(paletteColors: [tint])
		let tintedSymbol = sizedSymbol?.withSymbolConfiguration(colorConfiguration)

		tintedSymbol?.draw(in: rect)
	}

	private func drawTitle(
		in rect: NSRect,
		tint: NSColor
	)
	{
		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.lineBreakMode = .byTruncatingMiddle

		(displayedTitle as NSString).draw(
			in: rect,
			withAttributes: [
				.font: textFont,
				.foregroundColor: tint,
				.paragraphStyle: paragraphStyle,
			]
		)
	}

	private func drawChevron(
		layout: ContentLayout,
		tint: NSColor
	)
	{
		let chevron = NSBezierPath()
		chevron.move(to: layout.chevronStart)
		chevron.line(to: layout.chevronTip)
		chevron.line(to: layout.chevronEnd)
		chevron.lineWidth = LayoutMetrics.chevronLineWidth
		chevron.lineCapStyle = .round

		tint.setStroke()
		chevron.stroke()
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
