import AppKit

/// Settings form fields keep focus and validation borders independent of the field editor.
@MainActor
final class SettingsFormTextField: NSTextField
{
	enum Presentation
	{
		case compact
		case outlined
		case dialog
		case nativeRounded
	}

	private let presentation: Presentation
	private let leadingIcon: DesktopIcon?
	private var colorObservation: ThemeColorObservation?

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

	convenience init(
		presentation: Presentation,
		leadingIcon: DesktopIcon? = nil
	)
	{
		self.init(
			frame: .zero,
			presentation: presentation,
			leadingIcon: leadingIcon
		)
	}

	init(
		frame frameRect: NSRect,
		presentation: Presentation,
		leadingIcon: DesktopIcon? = nil
	)
	{
		self.presentation = presentation
		self.leadingIcon = leadingIcon
		super.init(frame: frameRect)
		colorObservation = ThemeColorObservation
		{
			[weak self] in self?.refreshThemeColors()
		}
		heightAnchor.constraint(equalToConstant: fieldHeight).isActive = true
		if presentation == .nativeRounded
		{
			self.setTypographyRole(TypographyTokens.Connections.body)
			bezelStyle = .roundedBezel
			usesSingleLineMode = true
			return
		}
		let fieldCell = SettingsFormTextFieldCell(textCell: "")
		fieldCell.hasLeadingIcon = leadingIcon != nil
		fieldCell.isCompact = presentation == .compact
		fieldCell.typography = typographyRole
		cell = fieldCell
		usesSingleLineMode = true
		isEditable = true
		isSelectable = true
		isBezeled = false
		isBordered = false
		drawsBackground = false
		focusRingType = .none
		self.setTypographyRole(
			typographyRole,
			onUpdate:
			{
				[weak self] in
				self?.refreshThemeColors()
				self?.positionCurrentEditor()
			}
		)
		if presentation == .compact
		{
			alignment = .right
			widthAnchor.constraint(equalToConstant: LayoutTokens.Settings.sizeInputWidth)
				.isActive = true
		}

		textColor = AppKitColorTokens.settingsPrimaryText
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
		size.height = fieldHeight
		return size
	}

	private var typographyRole: TypographyTokens.Role
	{
		switch presentation
		{
		case .dialog: TypographyTokens.Dialog.input
		case .compact: TypographyTokens.Settings.sizeInput
		case .outlined: TypographyTokens.Settings.formInput
		case .nativeRounded: TypographyTokens.Connections.body
		}
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		refreshThemeColors()
	}

	private var fieldHeight: CGFloat
	{
		presentation == .compact ? LayoutTokens.Settings.sizeInputHeight : 36
	}

	override var alignmentRectInsets: NSEdgeInsets
	{
		presentation == .nativeRounded ? super.alignmentRectInsets : NSEdgeInsetsZero
	}

	@objc private func refreshBorder()
	{
		positionCurrentEditor()
		refreshThemeColors()
		needsDisplay = true
	}

	private func refreshThemeColors()
	{
		guard presentation != .nativeRounded
		else
		{
			return
		}
		textColor = AppKitColorTokens.settingsPrimaryText
		if let placeholderString
		{
			var attributes = AppKitFontResolver.textAttributes(
				typographyRole,
				font: font
			)
			attributes[.foregroundColor] = AppKitColorTokens.settingsTertiaryText
			placeholderAttributedString = NSAttributedString(
				string: placeholderString,
				attributes: attributes
			)
		}
		if let editor = currentEditor(), let cell = cell as? SettingsFormTextFieldCell
		{
			cell.styleEditor(
				editor,
				in: self
			)
		}
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
		refreshThemeColors()
	}

	override func draw(_ dirtyRect: NSRect)
	{
		guard presentation != .nativeRounded
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
		drawLeadingIcon()
		if hasValidationError
		{
			AppKitColorTokens.fieldErrorEdge.setStroke()
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
				: AppKitColorTokens.heavyBorder)
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
	private func drawLeadingIcon()
	{
		guard let leadingIcon
		else
		{
			return
		}
		DesktopIcons.draw(
			leadingIcon,
			in: NSRect(
				x: 12,
				y: bounds.midY - 7,
				width: 14,
				height: 14
			),
			tint: AppKitColorTokens.settingsSecondaryText
		)
	}
}

@MainActor
private final class SettingsFormTextFieldCell: NSTextFieldCell
{
	private let editorStyle = ThemeFieldEditorStyle()
	var hasLeadingIcon = false
	var isCompact = false
	var typography = TypographyTokens.Settings.formInput

	override func endEditing(_ textObj: NSText)
	{
		super.endEditing(textObj)
		editorStyle.restore(textObj)
	}

	func styleEditor(
		_ textObj: NSText,
		in controlView: NSView
	)
	{
		editorStyle.apply(
			to: textObj,
			in: controlView
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
		styleEditor(
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
		styleEditor(
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
		let inset: CGFloat = isCompact ? 8 : 10
		let height = typography.lineHeight ?? TypographyTokens.Text.compactControl.lineHeight!
		return NSRect(
			x: rect.minX + (hasLeadingIcon ? 38 : inset),
			y: rect.midY - height / 2,
			width: max(
				0,
				rect.width - (hasLeadingIcon ? 38 + inset : 2 * inset)
			),
			height: height
		)
	}
}
