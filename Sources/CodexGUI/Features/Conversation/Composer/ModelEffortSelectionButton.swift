import AppKit

@MainActor
final class ModelEffortSelectionButton: NSButton
{
	private let contentLayout: ModelSelectorLayout
	private typealias ContentLayout = ModelSelectorLayout.Content

	private var summary: String?
	private var effortTitle: String?
	private var fastMode = false
	private var isPickerPresented = false
	private var isModelListPresented = false
	private var presentedWidth: CGFloat?
	private weak var observedWindow: NSWindow?

	override init(frame frameRect: NSRect)
	{
		contentLayout = ModelSelectorLayout()
		super.init(frame: frameRect)
		configure()
	}

	init(metrics: LayoutTokens.ModelSelector)
	{
		contentLayout = ModelSelectorLayout(metrics: metrics)
		super.init(frame: .zero)
		configure()
	}

	private func configure()
	{
		precondition(
			contentLayout.metrics.isValid,
			"Invalid model selector metrics"
		)
		precondition(
			contentLayout.fits(controlHeight: LayoutTokens.composer.controlHeight),
			"Model artwork must fit its control height"
		)
		isBordered = false
		bezelStyle = .inline
		focusRingType = .none
		font = AppKitFontResolver.font(TypographyTokens.Composer.preference)
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
		isPickerPresented: Bool,
		isModelListPresented: Bool = false
	)
	{
		let widthBeforePresentation = isPickerPresented && !self.isPickerPresented
			? intrinsicContentSize.width : nil
		self.summary = summary.flatMap
		{
			$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
		}
		self.effortTitle = effortTitle
		self.fastMode = fastMode
		self.isPickerPresented = isPickerPresented
		self.isModelListPresented = isModelListPresented
		title = displayedTitle
		if let widthBeforePresentation
		{
			let displayedWidth = contentLayout.requestedWidth(
				titleWidth: naturalTextSize.width,
				displaysBolt: displaysBolt
			)
			presentedWidth = max(
				widthBeforePresentation,
				displayedWidth
			)
		}
		else if !isPickerPresented
		{
			presentedWidth = nil
		}

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
		isPickerPresented && !isModelListPresented ? "Select effort" : summary ?? "Select effort"
	}

	private var displaysBolt: Bool
	{
		fastMode && (!isPickerPresented || isModelListPresented) && summary != nil
	}

	private var textFont: NSFont
	{
		font ?? AppKitFontResolver.font(TypographyTokens.Composer.preference)
	}

	private var naturalTextSize: NSSize
	{
		(displayedTitle as NSString).size(withAttributes: [.font: textFont])
	}

	override var intrinsicContentSize: NSSize
	{
		let summaryWidth = ((summary ?? "Select effort") as NSString)
			.size(withAttributes: [.font: textFont]).width
		let closedWidth = contentLayout.requestedWidth(
			titleWidth: summaryWidth,
			displaysBolt: fastMode && summary != nil
		)
		let displayedWidth = contentLayout.requestedWidth(
			titleWidth: naturalTextSize.width,
			displaysBolt: displaysBolt
		)
		let requestedWidth = isPickerPresented ? max(
			closedWidth,
			displayedWidth
		) : closedWidth
		return NSSize(
			width: presentedWidth ?? requestedWidth,
			height: LayoutTokens.composer.controlHeight
		)
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		let shouldDrawSelectionBackground =
			isPickerPresented || cell?.isHighlighted == true

		if shouldDrawSelectionBackground
		{
			AppKitColorTokens.rowHighlight.setFill()
			selectionOutline().fill()
		}

		let tint: NSColor = isEnabled ? AppKitColorTokens.secondaryText : AppKitColorTokens
			.mutedText
		let layout = makeContentLayout()

		if displaysBolt
		{
			drawBolt(
				in: layout.boltRect,
				tint: isEnabled ? AppKitColorTokens.primaryText : tint
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
		contentLayout.content(
			in: bounds,
			titleSize: naturalTextSize,
			displaysBolt: displaysBolt
		)
	}

	private func drawBolt(
		in rect: NSRect,
		tint: NSColor
	)
	{
		DesktopIcons.draw(
			ComposerFooterIcons.bolt,
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
				.foregroundColor: isEnabled && (!isPickerPresented || isModelListPresented)
					? AppKitColorTokens.primaryText : tint,
				.paragraphStyle: paragraphStyle,
			]
		)
		if !isPickerPresented || isModelListPresented,
			let effortTitle, displayedTitle.hasSuffix(" " + effortTitle)
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
		DesktopTextRendering.withFontSmoothingDisabled
		{
			title.draw(in: rect)
		}
	}

	private func drawChevron(
		layout: ContentLayout,
		tint: NSColor
	)
	{
		DesktopIcons.draw(
			ComposerFooterIcons.chevron,
			in: layout.chevronRect,
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
