import AppKit

/// Settings form fields keep focus and validation borders independent of the field editor.
@MainActor
final class SettingsFormTextField: NSTextField
{
	enum Presentation
	{
		case outlined
		case dialog
		case nativeRounded
	}

	private let presentation: Presentation

	var hasValidationError = false
	{
		didSet
		{
			needsDisplay = true
		}
	}

	override convenience init(frame frameRect: NSRect)
	{
		self.init(
			frame: frameRect,
			presentation: .outlined
		)
	}

	convenience init(presentation: Presentation)
	{
		self.init(
			frame: .zero,
			presentation: presentation
		)
	}

	init(
		frame frameRect: NSRect,
		presentation: Presentation
	)
	{
		self.presentation = presentation
		super.init(frame: frameRect)
		heightAnchor.constraint(equalToConstant: 36).isActive = true
		if presentation == .nativeRounded
		{
			font = AppKitFontResolver.font(TypographyTokens.Connections.body)
			bezelStyle = .roundedBezel
			usesSingleLineMode = true
			return
		}
		cell = SettingsFormTextFieldCell(textCell: "")
		isEditable = true
		isSelectable = true
		isBezeled = false
		isBordered = false
		drawsBackground = false
		focusRingType = .none
		font = .systemFont(ofSize: presentation == .dialog ? 14 : 13)
		textColor = presentation == .dialog ? .labelColor : AppKitColorTokens.settingsPrimaryText
		cell?.isScrollable = true
		for name in [
			NSControl.textDidBeginEditingNotification,
			NSControl.textDidEndEditingNotification
		]
		{
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(refreshBorder),
				name: name,
				object: self
			)
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var intrinsicContentSize: NSSize
	{
		var size = super.intrinsicContentSize
		size.height = 36
		return size
	}

	@objc private func refreshBorder()
	{
		positionCurrentEditor()
		needsDisplay = true
	}

	override func layout()
	{
		super.layout()
		positionCurrentEditor()
	}

	override func textDidChange(_ notification: Notification)
	{
		super.textDidChange(notification)
		positionCurrentEditor()
	}

	private func positionCurrentEditor()
	{
		guard let editor = currentEditor(), let cell = cell as? SettingsFormTextFieldCell
		else
		{
			return
		}
		cell.positionEditor(
			editor,
			in: self
		)
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if presentation == .dialog
		{
			let outline = NSBezierPath(
				roundedRect: bounds.insetBy(
					dx: 0.5,
					dy: 0.5
				),
				xRadius: 8,
				yRadius: 8
			)
			AppKitColorTokens.elevated.setFill()
			outline.fill()
			super.draw(dirtyRect)
			(currentEditor() != nil ? NSColor.controlAccentColor : AppKitColorTokens.border)
				.setStroke()
			outline.lineWidth = 1
			outline.stroke()
			return
		}
		guard presentation == .outlined
		else
		{
			super.draw(dirtyRect)
			return
		}
		AppKitColorTokens.settingsFormFieldSurface.setFill()
		AppKitShapePath.roundedRect(
			bounds,
			radius: 10,
			curve: ShapeTokens.Connections.curve
		).fill()
		super.draw(dirtyRect)
		if hasValidationError
		{
			AppKitColorTokens.settingsFieldError.withAlphaComponent(0.2).setStroke()
			let halo = AppKitShapePath.roundedRect(
				bounds.insetBy(
					dx: 1,
					dy: 1
				),
				radius: 10,
				curve: ShapeTokens.Connections.curve
			)
			halo.lineWidth = 3
			halo.stroke()
		}
		let focused = currentEditor() != nil
		let border = hasValidationError ? AppKitColorTokens.settingsFieldError
			: (focused ? AppKitColorTokens.settingsFieldFocus
				: AppKitColorTokens.settingsPrimaryText.withAlphaComponent(0.118))
		border.setStroke()
		let path = AppKitShapePath.roundedRect(
			bounds.insetBy(
				dx: 0.5,
				dy: 0.5
			),
			radius: 10,
			curve: ShapeTokens.Connections.curve
		)
		path.lineWidth = 1
		path.stroke()
	}
}

@MainActor
private final class SettingsFormTextFieldCell: NSTextFieldCell
{
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
		let textRect = drawingRect(forBounds: controlView.bounds)
		// Preserve the editor's scrolling origin; only its viewport belongs to the field.
		if let clip = editor.superview as? NSClipView, let container = clip.superview
		{
			clip.frame = controlView.convert(
				textRect,
				to: container
			)
		}
		else if let container = editor.superview
		{
			editor.frame = controlView.convert(
				textRect,
				to: container
			)
		}
	}

	override func drawingRect(forBounds rect: NSRect) -> NSRect
	{
		NSRect(
			x: rect.minX + 10,
			y: rect.midY - 9,
			width: max(
				0,
				rect.width - 20
			),
			height: 18
		)
	}
}
