import AppKit
import CoreText

/// Image zoom uses the shared action menu and the viewer's value typography.
@MainActor
final class ExpandedImageZoomButton: DesktopPopupButton
{
	override init(
		frame buttonFrame: NSRect,
		pullsDown flag: Bool
	)
	{
		super.init(
			frame: buttonFrame,
			pullsDown: flag
		)
		isBordered = false
		focusRingType = .none
		self.setTypographyRole(TypographyTokens.Button.value)
		toolTip = "Zoom"
		_ = colorObservation
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var intrinsicContentSize: NSSize
	{
		let attributes = AppKitFontResolver.textAttributes(
			TypographyTokens.Button.value,
			font: font
		)
		let width = ((selectedItem?.title ?? "100%") as NSString).size(withAttributes: attributes)
			.width
		return NSSize(
			width: width + 2 * LayoutTokens.Button.regularHorizontalInset,
			height: LayoutTokens.Button.regularHeight
		)
	}

	override var alignmentRectInsets: NSEdgeInsets
	{
		NSEdgeInsets(
			top: 0,
			left: 0,
			bottom: 0,
			right: 0
		)
	}

	private let focusIndicator = DesktopControlFocusIndicator()
	private lazy var colorObservation = ThemeColorObservation(view: self)
	{
		[weak self] in
		self?.needsDisplay = true
		self?.refreshFocus()
	}
	private var hover = false
	private var hoverTracking: NSTrackingArea?
	private var actionMenu: DesktopActionMenu?

	override func layout()
	{
		super.layout()
		refreshFocus()
	}

	override func becomeFirstResponder() -> Bool
	{
		let accepted = super.becomeFirstResponder()
		refreshFocus()
		return accepted
	}

	override func resignFirstResponder() -> Bool
	{
		let accepted = super.resignFirstResponder()
		needsLayout = true
		return accepted
	}

	private func refreshFocus()
	{
		focusIndicator.update(
			in: self,
			shape: .capsule,
			focused: isEnabled && window?.firstResponder === self
		)
	}

	func dismissMenu()
	{
		actionMenu?.close()
		actionMenu = nil
		needsDisplay = true
	}

	private func showMenu()
	{
		guard isEnabled, let menu
		else
		{
			return
		}
		controlTooltip.dismiss()
		dismissMenu()
		for item in menu.items where !item.isHidden && !item.isSeparatorItem
		{
			item.target = self
			item.action = #selector(chooseZoom(_:))
		}
		let presentation = DesktopActionMenu(
			menu: menu,
			backingScale: window?.backingScaleFactor ?? 1,
			minimumWidth: 160,
			showsCheckmarks: true,
			accessibilityLabel: "Image zoom"
		)
		presentation.onClose =
		{
			[weak self] in self?.needsDisplay = true
		}
		actionMenu = presentation
		presentation.show(from: self)
		needsDisplay = true
	}

	@objc private func chooseZoom(_ item: NSMenuItem)
	{
		select(item)
		_ = sendAction(
			action,
			to: target
		)
	}

	override func mouseDown(with event: NSEvent)
	{
		showMenu()
	}

	override func keyDown(with event: NSEvent)
	{
		if [UInt16(36), 49, 125, 126].contains(event.keyCode)
		{
			showMenu()
		}
		else
		{
			super.keyDown(with: event)
		}
	}

	override func accessibilityPerformPress() -> Bool
	{
		guard isEnabled
		else
		{
			return false
		}
		showMenu()
		return true
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		hoverTracking = DesktopHoverTracking.replace(
			in: self,
			previous: hoverTracking
		)
	}

	override func mouseEntered(with event: NSEvent)
	{
		hover = true
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent)
	{
		hover = false
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		ExpandedImageHeaderDrawing.drawBackground(
			control: self,
			hover: hover || actionMenu?.host.isShown == true
		)
		let title = selectedItem?.title ?? ""
		var attributes = AppKitFontResolver.textAttributes(
			TypographyTokens.Button.value,
			font: font ?? AppKitFontResolver.font(
				TypographyTokens.Button.value,
				appearance: effectiveAppearance
			)
		)
		attributes[.foregroundColor] = ExpandedImageHeaderDrawing.foreground(enabled: isEnabled)

		let size = (title as NSString).size(withAttributes: attributes)
		let caretGap: CGFloat = 2
		let contentX = bounds.midX - (size.width + caretGap + 16) / 2 + 1.5
		if let context = NSGraphicsContext.current?.cgContext
		{
			let line = CTLineCreateWithAttributedString(NSAttributedString(
				string: title,
				attributes: attributes
			))
			let glyphBounds = CTLineGetBoundsWithOptions(
				line,
				.useGlyphPathBounds
			)
			context.saveGState()
			context.translateBy(
				x: contentX,
				y: bounds.midY
			)
			if isFlipped
			{
				context.scaleBy(
					x: 1,
					y: -1
				)
			}
			context.textMatrix = .identity
			context.textPosition = NSPoint(
				x: 0,
				y: -glyphBounds.midY
			)
			CTLineDraw(
				line,
				context
			)
			context.restoreGState()
		}
		DesktopIcons.draw(
			DesktopIcons.image(.chevronSmallDown),
			in: NSRect(
				x: contentX + size.width + caretGap,
				y: bounds.midY - 8,
				width: 16,
				height: 16
			),
			tint: ExpandedImageHeaderDrawing.foreground(enabled: isEnabled)
		)
	}
}
