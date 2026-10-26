import AppKit

/// Complete native search control. Presentation owns artwork, text geometry and field-editor style.
@MainActor
class DesktopSearchField: NSSearchField
{
	enum Presentation: Sendable
	{
		case native
		case viewer
		case viewerOverlay
		case settingsFilled
		case settingsOutlined
		case settingsCatalog

		var isSettings: Bool
		{
			switch self
			{
			case .settingsFilled, .settingsOutlined, .settingsCatalog: true
			default: false
			}
		}
	}

	var presentation: Presentation
	{
		didSet
		{
			applyPresentation()
		}
	}
	var searchPrompt = "Search"
	{
		didSet
		{
			refreshPlaceholder()
			needsDisplay = true
		}
	}
	private struct NativeStyle
	{
		let font: NSFont?
		let textColor: NSColor?
		let isBordered: Bool
		let isBezeled: Bool
		let drawsBackground: Bool
		let focusRingType: NSFocusRingType
		let controlSize: NSControl.ControlSize
	}
	private var nativeStyle: NativeStyle?
	private var placeholderText = NSAttributedString(string: "Search")

	override init(frame frameRect: NSRect)
	{
		presentation = .native
		super.init(frame: frameRect)
		preparePresentation()
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
		preparePresentation()
	}

	private func preparePresentation()
	{
		nativeStyle = NativeStyle(
			font: font,
			textColor: textColor,
			isBordered: isBordered,
			isBezeled: isBezeled,
			drawsBackground: drawsBackground,
			focusRingType: focusRingType,
			controlSize: controlSize
		)
		applyPresentation()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func configureSearch(
		placeholder: String,
		accessibilityLabel: String,
		delegate: NSSearchFieldDelegate?,
		sendsImmediately: Bool? = nil
	)
	{
		if presentation.isSettings
		{
			searchPrompt = placeholder
		}
		else
		{
			placeholderString = placeholder
		}
		setAccessibilityLabel(accessibilityLabel)
		self.delegate = delegate
		if let sendsImmediately
		{
			sendsSearchStringImmediately = sendsImmediately
		}
	}

	private func applyPresentation()
	{
		let value = stringValue
		if presentation == .native
		{
			if cell is DesktopSearchFieldCell
			{
				cell = NSSearchFieldCell(textCell: value)
			}
			if let nativeStyle
			{
				font = nativeStyle.font
				textColor = nativeStyle.textColor
				isBordered = nativeStyle.isBordered
				isBezeled = nativeStyle.isBezeled
				drawsBackground = nativeStyle.drawsBackground
				focusRingType = nativeStyle.focusRingType
				controlSize = nativeStyle.controlSize
			}
			invalidateIntrinsicContentSize()
			needsDisplay = true
			return
		}
		if !(cell is DesktopSearchFieldCell)
		{
			cell = DesktopSearchFieldCell(textCell: value)
		}
		isEditable = true
		isSelectable = true
		isBordered = false
		isBezeled = false
		drawsBackground = false
		(cell as? DesktopSearchFieldCell)?.presentation = presentation
		let searchCell = cell as? NSSearchFieldCell
		if presentation.isSettings
		{
			focusRingType = .none
			font = AppKitFontResolver.font(TypographyTokens.Settings.search)
			textColor = AppKitColorTokens.settingsPrimaryText
			searchCell?.searchButtonCell = nil
			placeholderAttributedString = NSAttributedString(string: "")
			refreshPlaceholder()
		}
		else
		{
			let overlay = presentation == .viewerOverlay
			font = .systemFont(ofSize: overlay ? 14 : 13)
			textColor = AppKitColorTokens.primaryText
			focusRingType = overlay ? .none : .default
			controlSize = overlay ? .regular : .large
			if overlay
			{
				searchCell?.searchButtonCell = nil
			}
			else
			{
				let button = searchCell?.searchButtonCell ?? NSButtonCell()
				button.image = DesktopIcons.image(.search)
				searchCell?.searchButtonCell = button
			}
			if let clear = DesktopIcon(rawValue: "XCircleFilledCrossedClose")
			{
				searchCell?.cancelButtonCell?.image = DesktopIcons.image(
					clear,
					size: 13
				)
			}
		}
		styleCurrentEditor()
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	override var intrinsicContentSize: NSSize
	{
		var size = super.intrinsicContentSize
		switch presentation
		{
		case .native: break
		case .viewer: size.height = 28
		case .viewerOverlay: size.height = 32
		case .settingsFilled, .settingsOutlined, .settingsCatalog: size.height = 36
		}
		return size
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshPlaceholder()
		styleCurrentEditor()
		needsDisplay = true
	}

	override func textDidChange(_ notification: Notification)
	{
		super.textDidChange(notification)
		styleCurrentEditor()
		needsDisplay = true
	}

	private func styleCurrentEditor()
	{
		if let editor = currentEditor(), let searchCell = cell as? DesktopSearchFieldCell
		{
			searchCell.positionEditor(
				editor,
				in: self,
				bounds: bounds
			)
			searchCell.styleEditor(
				editor,
				in: self
			)
		}
	}

	private func refreshPlaceholder()
	{
		guard presentation.isSettings
		else
		{
			return
		}
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			placeholderText = NSAttributedString(
				string: searchPrompt,
				attributes: [
					.font: AppKitFontResolver.font(TypographyTokens.Settings.search),
					.foregroundColor: AppKitColorTokens.settingsTertiaryText,
				]
			)
		}
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if presentation == .viewer
		{
			let path = NSBezierPath(
				roundedRect: bounds.insetBy(
					dx: 0.5,
					dy: 0.5
				),
				xRadius: 9,
				yRadius: 9
			)
			AppKitColorTokens.canvas.setFill()
			path.fill()
			AppKitColorTokens.subtleEdge.setStroke()
			path.stroke()
		}
		guard presentation.isSettings
		else
		{
			super.draw(dirtyRect)
			return
		}
		let surface: NSColor
		switch presentation
		{
		case .settingsCatalog: surface = AppKitColorTokens.settingsCatalogSearchSurface
		case .settingsOutlined: surface = AppKitColorTokens.canvas
		default: surface = AppKitColorTokens.settingsSearchSurface
		}
		surface.setFill()
		let radius = presentation == .settingsCatalog ? ShapeTokens.Settings.catalogSearchRadius
			: bounds.height / 2
		let path = NSBezierPath(
			roundedRect: bounds,
			xRadius: radius,
			yRadius: radius
		)
		path.fill()
		if presentation == .settingsOutlined || presentation == .settingsCatalog
		{
			(presentation == .settingsCatalog ? AppKitColorTokens.settingsCatalogSearchEdge
				: AppKitColorTokens.settingsSelectorEdge).setStroke()
			path.lineWidth = 1
			path.stroke()
		}
		if stringValue.isEmpty, let searchCell = cell as? NSSearchFieldCell
		{
			placeholderText.draw(in: searchCell.searchTextRect(forBounds: bounds))
		}
		else
		{
			super.draw(dirtyRect)
		}
		DesktopIcons.draw(
			.search,
			in: NSRect(
				x: 12,
				y: bounds.midY - 8,
				width: 16,
				height: 16
			),
			tint: AppKitColorTokens.settingsSecondaryText
		)
	}
}

@MainActor
private final class DesktopSearchFieldCell: NSSearchFieldCell
{
	var presentation: DesktopSearchField.Presentation = .viewer

	private struct EditorStyle
	{
		let insertionPointColor: NSColor
		let backgroundColor: NSColor
		let drawsBackground: Bool
		let inset: NSSize
		let lineFragmentPadding: CGFloat?
	}

	private weak var styledEditor: NSTextView?
	private var originalEditorStyle: EditorStyle?

	override func endEditing(_ textObj: NSText)
	{
		super.endEditing(textObj)
		guard let editor = textObj as? NSTextView, editor === styledEditor,
				let original = originalEditorStyle
		else
		{
			return
		}
		editor.insertionPointColor = original.insertionPointColor
		editor.backgroundColor = original.backgroundColor
		editor.drawsBackground = original.drawsBackground
		editor.textContainerInset = original.inset
		if let padding = original.lineFragmentPadding
		{
			editor.textContainer?.lineFragmentPadding = padding
		}
		styledEditor = nil
		originalEditorStyle = nil
	}

	func styleEditor(
		_ textObj: NSText,
		in controlView: NSView
	)
	{
		guard (controlView as? DesktopSearchField)?.presentation.isSettings == true,
				let editor = textObj as? NSTextView
		else
		{
			return
		}
		if styledEditor !== editor
		{
			originalEditorStyle = EditorStyle(
				insertionPointColor: editor.insertionPointColor,
				backgroundColor: editor.backgroundColor,
				drawsBackground: editor.drawsBackground,
				inset: editor.textContainerInset,
				lineFragmentPadding: editor.textContainer?.lineFragmentPadding
			)
			styledEditor = editor
		}
		controlView.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			editor.insertionPointColor = AppKitColorTokens.settingsPrimaryText
			if (controlView as? DesktopSearchField)?.presentation == .settingsCatalog
			{
				editor.backgroundColor = AppKitColorTokens.settingsCatalogSearchSurface
			}
			else if (controlView as? DesktopSearchField)?.presentation == .settingsOutlined
			{
				editor.backgroundColor = AppKitColorTokens.canvas
			}
			else
			{
				let surface = AppKitColorTokens.settingsSearchSurface
				editor.backgroundColor = AppKitColorTokens.canvas.blended(
					withFraction: surface.alphaComponent,
					of: surface.withAlphaComponent(1)
				) ?? AppKitColorTokens.canvas
			}
		}
		// Match the composer's caret repainting without covering the custom empty prompt.
		editor.drawsBackground = !editor.string.isEmpty
		editor.textContainerInset = .zero
		editor.textContainer?.lineFragmentPadding = 0
		editor.needsDisplay = true
	}

	override func titleRect(forBounds rect: NSRect) -> NSRect
	{
		if isSettings
		{
			return searchTextRect(forBounds: rect)
		}
		return super.titleRect(forBounds: rect)
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
			in: controlView,
			bounds: rect
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
			in: controlView,
			bounds: rect
		)
		styleEditor(
			textObj,
			in: controlView
		)
	}

	func positionEditor(
		_ editor: NSText,
		in controlView: NSView,
		bounds: NSRect
	)
	{
		guard isSettings
		else
		{
			return
		}
		let textRect = searchTextRect(forBounds: bounds)
		// A scrollable field editor lives inside a clip view. Move that viewport,
		// leaving the editor's local origin and horizontal scrolling to AppKit.
		// Applying control-view coordinates directly to the editor doubles the inset.
		if let clipView = editor.superview as? NSClipView, let container = clipView.superview
		{
			clipView.frame = controlView.convert(
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

	private var isSettings: Bool
	{
		presentation.isSettings
	}

	override func searchButtonRect(forBounds rect: NSRect) -> NSRect
	{
		NSRect(
			x: rect.minX + 10,
			y: rect.midY - 8,
			width: 16,
			height: 16
		)
	}

	override func searchTextRect(forBounds rect: NSRect) -> NSRect
	{
		if !isSettings
		{
			let font = font ?? NSFont.systemFont(ofSize: 13)
			let height = min(
				rect.height,
				ceil(font.ascender - font.descender + font.leading)
			)
			let leading = searchButtonCell == nil ? rect.minX
				: searchButtonRect(forBounds: rect).maxX + 6
			let trailing = stringValue.isEmpty ? rect.maxX - 10
				: cancelButtonRect(forBounds: rect).minX - 6
			return NSRect(
				x: leading,
				y: rect.midY - height / 2,
				width: max(
					0,
					trailing - leading
				),
				height: height
			)
		}
		let textHeight: CGFloat = TypographyTokens.Settings.search.lineHeight ?? 18
		let trailing = stringValue.isEmpty ? rect.maxX - 12
			: cancelButtonRect(forBounds: rect).minX - 8
		return NSRect(
			x: rect.minX + 36,
			y: rect.midY - textHeight / 2,
			width: max(
				0,
				trailing - rect.minX - 36
			),
			height: textHeight
		)
	}

	override func cancelButtonRect(forBounds rect: NSRect) -> NSRect
	{
		NSRect(
			x: rect.maxX - (isSettings ? 25 : 23),
			y: rect.midY - 6.5,
			width: 13,
			height: 13
		)
	}
}
