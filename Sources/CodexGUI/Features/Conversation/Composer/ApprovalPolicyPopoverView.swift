import AppKit

private enum ApprovalTextDrawingConfiguration
{
	static let horizontalOffset: CGFloat = -0.5
	static let headingBaselineOffset: CGFloat = 1
	static let explanationBaselineOffset: CGFloat = 1.5
	static let linkHorizontalOffset: CGFloat = 2
	static let linkBaselineOffset = headingBaselineOffset
}

@MainActor
final class ApprovalPolicyPopoverView: NSViewController
{
	var onSelect: ((ApprovalMode) -> Void)?
	var openDocumentation: (URL) -> Void =
	{
		NSWorkspace.shared.open($0)
	}
	private let learnMoreButton = ApprovalPolicyLinkButton(
		title: "Learn more",
		target: nil,
		action: nil
	)
	private var selectedMode: ApprovalMode = .askForApproval
	private var rows: [ApprovalPolicyRow] = []

	init()
	{
		super.init(
			nibName: nil,
			bundle: nil
		)
		preferredContentSize = NSSize(
			width: LayoutTokens.ApprovalPopover.width,
			height: LayoutTokens.ApprovalPopover.preferredHeight
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func loadView()
	{
		let surface = DesktopSurface(
			AppKitColorTokens.popover,
			cornerRadius: ShapeTokens.Popover.cornerRadius,
			bordered: true,
			borderWidth: ShapeTokens.Popover.edgeWidth,
			borderColor: AppKitColorTokens.popoverEdge
		)
		let header = makeHeadingRow()
		header.heightAnchor.constraint(equalToConstant: LayoutTokens.ApprovalPopover.headerHeight)
			.isActive = true

		rows = makePolicyRows()
		for row in rows
		{
			row.onHover =
			{
				[weak self] hoveredRow in
				self?.rows.filter
				{
					$0 !== hoveredRow
				}.forEach
				{
					$0.clearHover()
				}
			}
		}

		let arrangedViews: [NSView] = [header] + rows
		let stack = AppKitLayout.verticalStack(
			arrangedViews,
			spacing: 0
		)
		AppKitLayout.pin(
			stack,
			to: surface,
			inset: LayoutTokens.ApprovalPopover.contentInset
		)
		header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		for row in rows
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
			row.heightAnchor.constraint(equalToConstant: LayoutTokens.ApprovalPopover.rowHeight)
				.isActive = true
		}

		for index in rows.indices
		{
			rows[index].nextKeyView = rows[(index + 1) % rows.count]
		}

		rows.last?.nextKeyView = learnMoreButton
		learnMoreButton.nextKeyView = rows.first

		let backdrop = ApprovalPolicyBackdropView()
		backdrop.material = .popover
		backdrop.blendingMode = .behindWindow
		backdrop.state = .active
		backdrop.addSubview(surface)
		AppKitLayout.pin(
			surface,
			to: backdrop,
			inset: 0
		)
		backdrop.setAccessibilityElement(true)
		backdrop.setAccessibilityRole(.menu)
		view = backdrop
		render(mode: selectedMode)
	}

	private func makeHeadingRow() -> NSStackView
	{
		let heading =
			ApprovalPolicyTextField(labelWithString: "How should Codex actions be approved?")
		heading.font = AppKitFontResolver.font(TypographyTokens.Popover.title)
		heading.horizontalDrawingOffset = 0
		heading.upwardBaselineOffset = ApprovalTextDrawingConfiguration.headingBaselineOffset
		heading.textColor = AppKitColorTokens.secondaryText
		heading.setAccessibilityLabel(heading.stringValue)

		learnMoreButton.target = self
		learnMoreButton.action = #selector(learnMore)
		learnMoreButton.font = AppKitFontResolver.font(TypographyTokens.Popover.title)
		learnMoreButton.isBordered = false
		learnMoreButton.bezelStyle = .inline
		learnMoreButton.setAccessibilityRole(.link)
		learnMoreButton.setAccessibilityLabel("Learn more about sandboxing and approvals")
		refreshLearnMoreStyle()
		let header = NSStackView(views: [heading, NSView(), learnMoreButton])
		header.orientation = .horizontal
		header.alignment = .centerY
		header.spacing = LayoutTokens.ApprovalPopover.headerSpacing
		header.edgeInsets = NSEdgeInsets(
			top: LayoutTokens.ApprovalPopover.verticalInset,
			left: LayoutTokens.ApprovalPopover.horizontalInset,
			bottom: LayoutTokens.ApprovalPopover.verticalInset,
			right: LayoutTokens.ApprovalPopover.horizontalInset
		)
		heading.heightAnchor
			.constraint(equalToConstant: LayoutTokens.ApprovalPopover.headerTextHeight)
			.isActive = true
		learnMoreButton.heightAnchor
			.constraint(equalToConstant: LayoutTokens.ApprovalPopover.headerTextHeight)
			.isActive = true

		return header
	}

	@objc private func learnMore()
	{
		openDocumentation(DocumentationLinks.sandboxing)
	}

	private func refreshLearnMoreStyle()
	{
		learnMoreButton.attributedTitle = NSAttributedString(
			string: "Learn more",
			attributes: [
				.font: AppKitFontResolver.font(TypographyTokens.Popover.title),
				.foregroundColor: AppKitColorTokens.secondaryText,
				.underlineStyle: NSUnderlineStyle.single.rawValue,
			]
		)
	}

	private func makePolicyRows() -> [ApprovalPolicyRow]
	{
		let modes: [ApprovalMode] = [.askForApproval, .approveForMe, .fullAccess]
		return modes.map
		{
			mode in
			let row = ApprovalPolicyRow(mode: mode)
			row.target = self
			row.action = #selector(selectRow(_:))
			row.onNavigate =
			{
				[weak self] offset in self?.moveFocus(
					from: mode,
					offset: offset
				)
			}
			return row
		}
	}

	override func viewDidAppear()
	{
		super.viewDidAppear()
		focusSelectedRow()
	}

	func focusSelectedRow()
	{
		if let selected = rows.first(where:
			{
				$0.mode == selectedMode
			})
		{
			view.window?.makeFirstResponder(selected)
		}
	}

	func clearHover()
	{
		rows.forEach
		{
			$0.clearHover()
		}
	}

	func render(mode: ApprovalMode)
	{
		selectedMode = mode
		refreshLearnMoreStyle()
		for row in rows
		{
			row.render(selected: row.mode == mode)
		}
	}

	@objc private func selectRow(_ sender: ApprovalPolicyRow)
	{
		onSelect?(sender.mode)
	}

	private func moveFocus(
		from mode: ApprovalMode,
		offset: Int
	)
	{
		guard let index = rows.firstIndex(where:
			{
				$0.mode == mode
			})
		else
		{
			return
		}
		let destination: Int
		if offset == .min
		{
			destination = 0
		}
		else if offset == .max
		{
			destination = rows.count - 1
		}
		else
		{
			destination = (index + offset + rows.count) % rows.count
		}
		view.window?.makeFirstResponder(rows[destination])
	}
}

/// Mask the material itself so it cannot fill the panel's square corners.
private final class ApprovalPolicyBackdropView: NSVisualEffectView
{
	private var maskedSize = NSSize.zero

	override func layout()
	{
		super.layout()
		let size = bounds.size
		guard size.width > 0, size.height > 0, size != maskedSize
		else
		{
			return
		}
		maskedSize = size
		maskImage = NSImage(
			size: size,
			flipped: false
		)
		{
			rect in
			NSColor.white.setFill()
			NSBezierPath(
				roundedRect: rect,
				xRadius: ShapeTokens.Popover.cornerRadius,
				yRadius: ShapeTokens.Popover.cornerRadius
			).fill()
			return true
		}
	}
}

@MainActor
private final class ApprovalPolicyRow: NSButton
{
	let mode: ApprovalMode
	var onNavigate: ((Int) -> Void)?
	var onHover: ((ApprovalPolicyRow) -> Void)?
	private let titleLabel = ApprovalPolicyTextField(labelWithString: "")
	private let explanation = ApprovalPolicyTextField(labelWithString: "")
	private let symbolView = NSImageView()
	private let checkView = NSImageView()
	private var tracking: NSTrackingArea?
	private var hovered = false
	private var selected = false

	init(mode: ApprovalMode)
	{
		self.mode = mode
		super.init(frame: .zero)
		title = ""
		isBordered = false
		bezelStyle = .inline
		focusRingType = .exterior
		setAccessibilityRole(.menuItem)
		setAccessibilityLabel(mode.title)
		setAccessibilityHelp(mode.description)

		configureLabels()
		configureSymbols()
		installContents()

		render(selected: false)
	}

	private func configureLabels()
	{
		titleLabel.stringValue = mode.title
		titleLabel.font = AppKitFontResolver.font(TypographyTokens.Popover.title)
		switch mode
		{
		case .askForApproval:
			explanation.stringValue = "Always ask to edit external files and use the internet"
		case .approveForMe:
			explanation.stringValue = "Only ask for actions detected as potentially unsafe"
		case .fullAccess:
			explanation.stringValue =
				"Unrestricted access to the internet and any file on your computer"
		}
		explanation.font = AppKitFontResolver.font(TypographyTokens.Popover.explanation)
		explanation.upwardBaselineOffset = ApprovalTextDrawingConfiguration
			.explanationBaselineOffset
		explanation.maximumNumberOfLines = 1
		explanation.lineBreakMode = .byClipping
	}

	private func configureSymbols()
	{
		switch mode
		{
		case .askForApproval: symbolView.image = ApprovalPolicyIcons.askForApproval
		case .approveForMe: symbolView.image = ApprovalPolicyIcons.approveForMe
		case .fullAccess: symbolView.image = ComposerFooterIcons.fullAccess
		}
		symbolView.imageScaling = .scaleProportionallyUpOrDown
		symbolView.alphaValue = LayoutTokens.ApprovalPopover.idleIconOpacity
		checkView.image = ApprovalPolicyIcons.selectedCheck
		checkView.alphaValue = LayoutTokens.ApprovalPopover.idleIconOpacity
	}

	private func installContents()
	{
		let children: [NSView] = [titleLabel, explanation, symbolView, checkView]
		for child in children
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			addSubview(child)
			child.setAccessibilityElement(false)
		}
		NSLayoutConstraint.activate([
			symbolView.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: LayoutTokens.ApprovalPopover.iconInset
			),
			symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
			symbolView.widthAnchor
				.constraint(equalToConstant: LayoutTokens.ApprovalPopover.iconSize),
			symbolView.heightAnchor
				.constraint(equalToConstant: LayoutTokens.ApprovalPopover.iconSize),
			titleLabel.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: LayoutTokens.ApprovalPopover.titleInset
			),
			titleLabel.topAnchor.constraint(
				equalTo: topAnchor,
				constant: LayoutTokens.ApprovalPopover.verticalInset
			),
			titleLabel.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -LayoutTokens.ApprovalPopover.horizontalInset
			),
			titleLabel.heightAnchor
				.constraint(equalToConstant: LayoutTokens.ApprovalPopover.titleHeight),
			explanation.heightAnchor
				.constraint(equalToConstant: LayoutTokens.ApprovalPopover.explanationHeight),
			explanation.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			explanation.topAnchor.constraint(
				equalTo: titleLabel.bottomAnchor,
				constant: 0
			),
			explanation.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -LayoutTokens.ApprovalPopover.horizontalInset
			),
			explanation.bottomAnchor.constraint(
				lessThanOrEqualTo: bottomAnchor,
				constant: -LayoutTokens.ApprovalPopover.verticalInset
			),
			checkView.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -LayoutTokens.ApprovalPopover.horizontalInset
			),
			checkView.centerYAnchor.constraint(equalTo: centerYAnchor),
			checkView.widthAnchor
				.constraint(equalToConstant: LayoutTokens.ApprovalPopover.checkSize),
			checkView.heightAnchor
				.constraint(equalToConstant: LayoutTokens.ApprovalPopover.checkSize),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var acceptsFirstResponder: Bool
	{
		true
	}

	func render(selected: Bool)
	{
		self.selected = selected
		let highlightsFullAccess = selected && mode == .fullAccess
		let tint: NSColor = highlightsFullAccess
			? ApprovalPopoverStyle.fullAccess : ApprovalPopoverStyle.primary
		titleLabel.textColor = tint
		explanation.textColor = highlightsFullAccess ? tint : ApprovalPopoverStyle.secondary
		symbolView.contentTintColor = highlightsFullAccess ? tint : ApprovalPopoverStyle.icon
		checkView.contentTintColor = tint
		checkView.isHidden = !selected
		setAccessibilityValue(selected ? "Selected" : "Not selected")
		needsDisplay = true
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		guard super.hitTest(point) != nil
		else
		{
			return nil
		}
		return self
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let tracking
		{
			removeTrackingArea(tracking)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		tracking = area
	}

	override func mouseEntered(with event: NSEvent)
	{
		onHover?(self)
		hovered = true
		updateIconOpacity()
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent)
	{
		clearHover()
	}

	private func updateIconOpacity()
	{
		let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		let opacity = hovered && dark ? LayoutTokens.ApprovalPopover.hoveredIconOpacity
			: LayoutTokens.ApprovalPopover.idleIconOpacity
		symbolView.alphaValue = opacity
		checkView.alphaValue = opacity
	}

	func clearHover()
	{
		guard hovered
		else
		{
			return
		}
		hovered = false
		updateIconOpacity()
		needsDisplay = true
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		updateIconOpacity()
		needsDisplay = true
	}

	private var rowRadius: CGFloat
	{
		effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			? ShapeTokens.ApprovalPopover.darkRowRadius : ShapeTokens.ApprovalPopover.rowRadius
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if hovered
		{
			ApprovalPopoverStyle.rowHover.setFill()
			NSBezierPath(
				roundedRect: bounds,
				xRadius: rowRadius,
				yRadius: rowRadius
			).fill()
		}
		super.draw(dirtyRect)
	}

	override func keyDown(with event: NSEvent)
	{
		switch event.keyCode
		{
		case 125: onNavigate?(1)
		case 126: onNavigate?(-1)
		case 115: onNavigate?(.min)
		case 119: onNavigate?(.max)
		case 36, 76, 49: performClick(nil)
		default: super.keyDown(with: event)
		}
	}
}

@MainActor
enum ApprovalPopoverStyle
{
	static let fullAccess = AppKitColorTokens.fullAccess
	static let rowHover = AppKitColorTokens.approvalRowHover
	static let primary = AppKitColorTokens.approvalPrimary
	static let secondary = AppKitColorTokens.approvalSecondary
	static let icon = AppKitColorTokens.approvalIcon
}

/// Keep menu typography consistent with the reference's grayscale antialiasing.
private final class ApprovalPolicyTextField: NSTextField
{
	var horizontalDrawingOffset = ApprovalTextDrawingConfiguration.horizontalOffset
	var upwardBaselineOffset: CGFloat = 0

	override var allowsVibrancy: Bool
	{
		false
	}

	override func draw(_ dirtyRect: NSRect)
	{
		DesktopTextRendering.withFontSmoothingDisabled
		{
			NSGraphicsContext.current?.cgContext.translateBy(
				x: horizontalDrawingOffset,
				y: isFlipped ? -upwardBaselineOffset : upwardBaselineOffset
			)
			super.draw(dirtyRect)
		}
	}
}

private final class ApprovalPolicyLinkButton: NSButton
{
	override var allowsVibrancy: Bool
	{
		false
	}

	override func draw(_ dirtyRect: NSRect)
	{
		DesktopTextRendering.withFontSmoothingDisabled
		{
			NSGraphicsContext.current?.cgContext.translateBy(
				x: ApprovalTextDrawingConfiguration.linkHorizontalOffset,
				y: isFlipped ? -ApprovalTextDrawingConfiguration.linkBaselineOffset
					: ApprovalTextDrawingConfiguration.linkBaselineOffset
			)
			super.draw(dirtyRect)
		}
	}
}
