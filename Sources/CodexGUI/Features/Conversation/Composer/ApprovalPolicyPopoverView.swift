import AppKit

@MainActor
final class ApprovalPolicyPopoverView: NSViewController
{
	var onSelect: ((ApprovalMode) -> Void)?
	private var selectedMode: ApprovalMode = .askForApproval
	private var rows: [ApprovalPolicyRow] = []

	init()
	{
		super.init(
			nibName: nil,
			bundle: nil
		)
		preferredContentSize = NSSize(
			width: 434,
			height: 159
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func loadView()
	{
		let surface = DesktopSurface(
			NSColor.textBackgroundColor,
			cornerRadius: 10
		)
		let header = makeHeadingRow()

		rows = makePolicyRows()

		let arrangedViews: [NSView] = [header] + rows
		let stack = AppKitLayout.verticalStack(
			arrangedViews,
			spacing: 0
		)
		stack.setCustomSpacing(
			6,
			after: header
		)
		AppKitLayout.pin(
			stack,
			to: surface,
			inset: 8
		)
		header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		for row in rows
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
			row.heightAnchor.constraint(equalToConstant: 42).isActive = true
		}

		for index in rows.indices
		{
			rows[index].nextKeyView = rows[(index + 1) % rows.count]
		}

		view = surface
		render(mode: selectedMode)
	}

	private func makeHeadingRow() -> NSStackView
	{
		let heading = NSTextField(labelWithString: "How should Codex actions be approved?")
		heading.font = .systemFont(ofSize: 13)
		heading.textColor = ApprovalPopoverStyle.secondary
		heading.setAccessibilityLabel(heading.stringValue)

		let header = NSStackView(views: [heading, NSView()])
		header.orientation = .horizontal
		header.spacing = 8

		return header
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
		if let selected = rows.first(where:
			{
				$0.mode == selectedMode
			})
		{
			view.window?.makeFirstResponder(selected)
		}
	}

	func render(mode: ApprovalMode)
	{
		selectedMode = mode
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

@MainActor
private final class ApprovalPolicyRow: NSButton
{
	let mode: ApprovalMode
	var onNavigate: ((Int) -> Void)?
	private let titleLabel = NSTextField(labelWithString: "")
	private let explanation = NSTextField(labelWithString: "")
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
		titleLabel.font = .systemFont(ofSize: 13)
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
		explanation.font = .systemFont(ofSize: 12)
		explanation.maximumNumberOfLines = 1
		explanation.lineBreakMode = .byClipping
	}

	private func configureSymbols()
	{
		let symbol: DesktopIcon
		switch mode
		{
		case .askForApproval: symbol = .handRaised
		case .approveForMe: symbol = .shieldCheck
		case .fullAccess: symbol = .warning
		}
		symbolView.image = DesktopIcons.image(symbol)
		checkView.image = DesktopIcons.image(.check)
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
				constant: 2
			),
			symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
			symbolView.widthAnchor.constraint(equalToConstant: 16),
			symbolView.heightAnchor.constraint(equalToConstant: 18),
			titleLabel.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 24
			),
			titleLabel.topAnchor.constraint(
				equalTo: topAnchor,
				constant: 3
			),
			titleLabel.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -22
			),
			explanation.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			explanation.topAnchor.constraint(
				equalTo: titleLabel.bottomAnchor,
				constant: 2
			),
			explanation.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -22
			),
			explanation.bottomAnchor.constraint(
				lessThanOrEqualTo: bottomAnchor,
				constant: -4
			),
			checkView.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -2
			),
			checkView.centerYAnchor.constraint(equalTo: centerYAnchor),
			checkView.widthAnchor.constraint(equalToConstant: 14),
			checkView.heightAnchor.constraint(equalToConstant: 14),
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
		symbolView.contentTintColor = highlightsFullAccess ? tint : ApprovalPopoverStyle.primary
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
		hovered = true
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent)
	{
		hovered = false
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if hovered
		{
			DesktopTheme.selection.setFill()
			NSBezierPath(
				roundedRect: bounds,
				xRadius: 8,
				yRadius: 8
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

enum ApprovalPopoverStyle
{
	static let fullAccess = NSColor(
		srgbRed: 1,
		green: 0.29,
		blue: 0,
		alpha: 1
	)
	static let primary = color(
		light: 0.13,
		dark: 0.9
	)
	static let secondary = color(
		light: 0.57,
		dark: 0.6
	)
	static let icon = color(
		light: 0.33,
		dark: 0.75
	)

	private static func color(
		light: CGFloat,
		dark: CGFloat
	) -> NSColor
	{
		NSColor(name: nil)
		{
			appearance in
			NSColor(
				white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
					? dark : light,
				alpha: 1
			)
		}
	}
}
