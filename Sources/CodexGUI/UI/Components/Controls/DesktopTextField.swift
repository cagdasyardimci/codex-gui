import AppKit

/// Shared grayscale text painting for native labels and editable fields.
@MainActor
class DesktopTextField: NSTextField
{
	/// Single-line entry shares one centered line box for placeholder, text and field editor.
	convenience init(singleLine role: TypographyTokens.Role)
	{
		self.init(frame: .zero)
		let centeredCell = DesktopCenteredTextFieldCell(textCell: "")
		centeredCell.typography = role
		cell = centeredCell
		usesSingleLineMode = true
	}

	/// Multiline entry centers a short value while expanding its line box as text wraps.
	convenience init(centeredMultiline role: TypographyTokens.Role)
	{
		self.init(frame: .zero)
		let centeredCell = DesktopCenteredTextFieldCell(textCell: "")
		centeredCell.typography = role
		centeredCell.isMultiline = true
		cell = centeredCell
		isEditable = true
		isSelectable = true
		usesSingleLineMode = false
	}

	override func layout()
	{
		super.layout()
		if let cell = cell as? DesktopCenteredTextFieldCell, let editor = currentEditor()
		{
			cell.positionEditor(
				editor,
				in: self
			)
		}
	}

	override var font: NSFont?
	{
		get
		{
			super.font
		}
		set
		{
			super.font = newValue
			if cell is DesktopCenteredTextFieldCell
			{
				needsLayout = true
			}
		}
	}

	override func draw(_ dirtyRect: NSRect)
	{
		DesktopTextRendering.withFontSmoothingDisabled
		{
			super.draw(dirtyRect)
		}
	}
}

@MainActor
private final class DesktopCenteredTextFieldCell: NSTextFieldCell
{
	var typography = TypographyTokens.Text.paragraph
	var isMultiline = false

	override func drawingRect(forBounds rect: NSRect) -> NSRect
	{
		let lineHeight = max(
			typography.lineHeight ?? 0,
			font.map
			{
				NSLayoutManager().defaultLineHeight(for: $0)
			} ?? 0
		)
		var contentHeight = lineHeight
		if isMultiline, let font
		{
			let editor = (controlView as? NSTextField)?.currentEditor() as? NSTextView
			let value = editor?.string ?? stringValue
			if !value.isEmpty
			{
				contentHeight = max(
					lineHeight,
					ceil((value as NSString).boundingRect(
						with: NSSize(
							width: max(
								rect.width,
								1
							),
							height: .greatestFiniteMagnitude
						),
						options: [.usesLineFragmentOrigin, .usesFontLeading],
						attributes: [.font: font]
					).height)
				)
			}
		}
		let height = min(
			rect.height,
			contentHeight
		)
		return NSRect(
			x: rect.minX,
			y: rect.midY - height / 2,
			width: rect.width,
			height: height
		)
	}

	override func edit(
		withFrame rect: NSRect,
		in controlView: NSView,
		editor textObj: NSText,
		delegate: Any?,
		event: NSEvent?
	)
	{
		super.edit(
			withFrame: rect,
			in: controlView,
			editor: textObj,
			delegate: delegate,
			event: event
		)
		positionEditor(
			textObj,
			in: controlView
		)
	}

	override func select(
		withFrame rect: NSRect,
		in controlView: NSView,
		editor textObj: NSText,
		delegate: Any?,
		start selStart: Int,
		length selLength: Int
	)
	{
		super.select(
			withFrame: rect,
			in: controlView,
			editor: textObj,
			delegate: delegate,
			start: selStart,
			length: selLength
		)
		positionEditor(
			textObj,
			in: controlView
		)
	}

	func positionEditor(
		_ editor: NSText,
		in controlView: NSView
	)
	{
		let rect = drawingRect(forBounds: controlView.bounds)
		if let textView = editor as? NSTextView
		{
			textView.textContainerInset = .zero
			textView.textContainer?.lineFragmentPadding = 0
		}
		// Move the viewport without resetting horizontal scrolling or the selection.
		if let clip = editor.superview as? NSClipView, let container = clip.superview
		{
			clip.frame = controlView.convert(
				rect,
				to: container
			)
		}
		else if let container = editor.superview
		{
			editor.frame = controlView.convert(
				rect,
				to: container
			)
		}
	}
}
