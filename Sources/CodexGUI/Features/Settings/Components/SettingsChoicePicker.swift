import AppKit

/// Compact settings selector shared by application destinations and notification choices.
@MainActor
class SettingsChoicePicker: DesktopHoverButton
{
	struct Choice
	{
		let id: String
		let title: String
		var icon: NSImage? = nil
		var detail: String? = nil
		var section: String? = nil
		var isEnabled = true
		var isSelected: Bool? = nil
		var help: String? = nil
	}

	var leadingIcon: NSImage?
	{
		didSet
		{
			invalidateIntrinsicContentSize(); needsDisplay = true
		}
	}
	private var selectionIcon: NSImage?
	{
		leadingIcon ?? selection?.icon
	}
	var menuWidth: CGFloat = 240
	var usesCheckboxesForMultipleSelection = true
	var onSelect: ((String) -> Void)?
	var onToggle: ((String, Bool) -> Void)?
	var onMenuWillOpen: (() -> Void)?
	private(set) var selectedID: String?
	private var checkedIDs: Set<String>?
	private var multipleSelectionTitle = ""
	private var choices: [Choice]
	private var pickerMenu: SettingsChoiceMenu?
	private let chevron = DesktopIcons.image(
		.chevronDown,
		size: 12
	)

	init(
		choices: [Choice],
		selectedID: String? = nil
	)
	{
		self.choices = choices
		self.selectedID = selectedID ?? choices.first?.id
		super.init(frame: .zero)
		isBordered = false
		setButtonType(.momentaryChange)
		font = AppKitFontResolver.font(TypographyTokens.Connections.body)
		focusRingType = .exterior
		target = self
		action = #selector(showChoices)
		setContentHuggingPriority(
			.required,
			for: .horizontal
		)
		setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
		updateSelection()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func setChoices(
		_ choices: [Choice],
		selectedID: String?
	)
	{
		pickerMenu?.close()
		self.choices = choices
		checkedIDs = nil
		self.selectedID = selectedID ?? choices.first?.id
		updateSelection()
	}

	/// Updates checks without closing an open multi-select menu.
	func setMultipleChoices(
		_ choices: [Choice],
		checkedIDs: Set<String>,
		title: String
	)
	{
		if self.choices.map(\.id) != choices.map(\.id)
		{
			pickerMenu?.close()
		}
		self.choices = choices
		self.checkedIDs = checkedIDs
		multipleSelectionTitle = title
		pickerMenu?.updateChecks(checkedIDs)
		updateSelection()
	}

	func select(id: String)
	{
		guard choices.contains(where:
			{
				$0.id == id && $0.isEnabled
			}), selectedID != id
		else
		{
			return
		}
		selectedID = id
		updateSelection()
	}

	private var selection: Choice?
	{
		guard checkedIDs == nil
		else
		{
			return nil
		}
		return choices.first
		{
			$0.id == selectedID
		} ?? choices.first
	}

	private func updateSelection()
	{
		title = checkedIDs == nil ? selection?.title ?? "" : multipleSelectionTitle
		setAccessibilityValue(title)
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	@objc private func showChoices()
	{
		guard isEnabled
		else
		{
			return
		}
		if pickerMenu?.isShown == true
		{
			pickerMenu?.close()
			return
		}
		onMenuWillOpen?()
		guard !choices.isEmpty
		else
		{
			return
		}
		let menu = SettingsChoiceMenu(
			choices: choices,
			selectedID: selectedID,
			accessibilityLabel: accessibilityLabel() ?? "Settings choices",
			width: menuWidth,
			checkedIDs: checkedIDs,
			showsCheckboxes: usesCheckboxesForMultipleSelection
		)
		menu.onSelect =
		{
			[weak self] id in
			guard let self, self.choices.contains(where:
				{
					$0.id == id && $0.isEnabled
				})
			else
			{
				return
			}
			self.onSelect?(id)
		}
		menu.onToggle =
		{
			[weak self] id, checked in self?.onToggle?(id, checked)
		}
		pickerMenu = menu
		menu.show(from: self)
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if newWindow == nil
		{
			pickerMenu?.close()
		}
		super.viewWillMove(toWindow: newWindow)
	}

	override var alignmentRectInsets: NSEdgeInsets
	{
		NSEdgeInsets()
	}
	override var intrinsicContentSize: NSSize
	{
		let textWidth = ceil((title as NSString).size(withAttributes: [
			.font: font ?? AppKitFontResolver.font(TypographyTokens.Connections.body)
		]).width)
		return NSSize(
			width: textWidth + 44 + (selectionIcon == nil ? 0 : 22),
			height: 28
		)
	}

	override var isEnabled: Bool
	{
		didSet
		{
			needsDisplay = true
		}
	}

	private var outline: NSBezierPath
	{
		AppKitShapePath.roundedRect(
			bounds.insetBy(
				dx: 0.5,
				dy: 0.5
			),
			radius: 12.5,
			curve: ShapeTokens.Connections.curve
		)
	}

	override func draw(_ dirtyRect: NSRect)
	{
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		bounds.clip()
		let active = isEnabled && (isHovered || isHighlighted || pickerMenu?.isShown == true)
		let foreground = AppKitColorTokens.settingsPrimaryText
		(active ? AppKitColorTokens.settingsSelectorHover : AppKitColorTokens
			.settingsSelectorSurface).setFill()
		outline.fill()
		AppKitColorTokens.settingsSelectorEdge.setStroke()
		outline.stroke()
		var textX: CGFloat = 12
		if let image = selectionIcon
		{
			let iconRect = NSRect(
				x: textX,
				y: bounds.midY - 8,
				width: 16,
				height: 16
			)
			if image.isTemplate
			{
				DesktopIcons.draw(
					image,
					in: iconRect,
					tint: foreground
				)
			}
			else
			{
				image.draw(in: iconRect)
			}
			textX += 22
		}
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		let attributes: [NSAttributedString.Key: Any] = [
			.font: font ?? AppKitFontResolver.font(TypographyTokens.Connections.body),
			.foregroundColor: foreground.withAlphaComponent(isEnabled ? 1 : 0.4),
			.paragraphStyle: paragraph
		]
		let textSize = (title as NSString).size(withAttributes: attributes)
		(title as NSString).draw(
			in: NSRect(
				x: textX,
				y: bounds.midY - textSize.height / 2,
				width: max(
					0,
					bounds.maxX - 32 - textX
				),
				height: textSize.height
			),
			withAttributes: attributes
		)
		DesktopIcons.draw(
			chevron,
			in: NSRect(
				x: bounds.maxX - 24,
				y: bounds.midY - 6,
				width: 12,
				height: 12
			),
			tint: AppKitColorTokens.settingsTertiaryText
		)
	}

	override var focusRingMaskBounds: NSRect
	{
		bounds
	}
	override func drawFocusRingMask()
	{
		outline.fill()
	}
}
