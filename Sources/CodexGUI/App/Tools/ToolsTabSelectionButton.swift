import AppKit

@MainActor
final class ToolsTabSelectionButton: NSButton
{
	var onNavigate: ((UInt16) -> Bool)?
	var tabID: UUID?

	override var focusRingMaskBounds: NSRect
	{
		bounds
	}

	override func drawFocusRingMask()
	{
		bounds.fill()
	}

	override func becomeFirstResponder() -> Bool
	{
		let accepted = super.becomeFirstResponder()
		if accepted
		{
			focusRingType = NSApp.currentEvent?.type == .keyDown ? .exterior : .none
		}
		return accepted
	}

	func configurePresentation(
		selected: Bool,
		preview: Bool = false,
		file: Bool = false
	)
	{
		let selectionCell: ToolsTabSelectionButtonCell
		if let existing = cell as? ToolsTabSelectionButtonCell
		{
			selectionCell = existing
		}
		else
		{
			let previous = cell as? NSButtonCell
			selectionCell = ToolsTabSelectionButtonCell(textCell: title)
			if let previous
			{
				selectionCell.target = previous.target
				selectionCell.action = previous.action
				selectionCell.state = previous.state
				selectionCell.image = previous.image
				selectionCell.alternateImage = previous.alternateImage
				selectionCell.alternateTitle = previous.alternateTitle
				selectionCell.keyEquivalent = previous.keyEquivalent
				selectionCell.keyEquivalentModifierMask = previous.keyEquivalentModifierMask
				selectionCell.tag = previous.tag
				selectionCell.isEnabled = previous.isEnabled
				selectionCell.isContinuous = previous.isContinuous
				selectionCell.allowsMixedState = previous.allowsMixedState
				selectionCell.highlightsBy = previous.highlightsBy
				selectionCell.showsStateBy = previous.showsStateBy
			}
			cell = selectionCell
		}
		selectionCell.documentTitleGap = file ? 5 : 0
		if window?.firstResponder !== self
		{
			focusRingType = .none
		}
		bezelStyle = .inline
		isBordered = false
		controlSize = .small
		alignment = .left
		imagePosition = .imageLeading
		cell?.lineBreakMode = .byTruncatingTail
		cell?.usesSingleLineMode = true
		setTypographyRole(
			TypographyTokens.Controls.tab,
			italic: preview
		)
		contentTintColor = selected ? AppKitColorTokens.primaryText : AppKitColorTokens
			.secondaryText
		setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		toolTip = toolTip ?? title
		setAccessibilityValue(selected ? "Selected" : "Not selected")
	}

	override func keyDown(with event: NSEvent)
	{
		if onNavigate?(event.keyCode) == true
		{
			return
		}
		super.keyDown(with: event)
	}
}

@MainActor
final class ToolsTabSelectionButtonCell: NSButtonCell
{
	var documentTitleGap: CGFloat = 0

	override func titleRect(forBounds rect: NSRect) -> NSRect
	{
		let title = super.titleRect(forBounds: rect)
		return NSRect(
			x: title.minX + documentTitleGap,
			y: title.minY,
			width: max(
				0,
				title.width - documentTitleGap
			),
			height: title.height
		)
	}

	override func drawTitle(
		_ title: NSAttributedString,
		withFrame frame: NSRect,
		in controlView: NSView
	) -> NSRect
	{
		DesktopTextRendering.withFontSmoothingDisabled
		{
			super.drawTitle(
				title,
				withFrame: frame,
				in: controlView
			)
		}
	}
}

enum ToolsChangesShortcut
{
	static let key = "g"
	static let modifiers: NSEvent.ModifierFlags = [.control, .shift]
	static let label = "⌃⇧G"
}
