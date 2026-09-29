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
			width: 440,
			height: 220
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func loadView()
	{
		let surface = DesktopSurface(
			DesktopTheme.inspector,
			cornerRadius: 16
		)
		let heading = NSTextField(labelWithString: "How should actions be approved?")
		heading.font = .systemFont(ofSize: 13)
		heading.textColor = .secondaryLabelColor
		heading.setAccessibilityLabel(heading.stringValue)
		let modes: [ApprovalMode] = [.askForApproval, .approveForMe, .fullAccess]
		rows = modes.map
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
		let arrangedViews: [NSView] = [heading] + rows
		let stack = AppKitLayout.verticalStack(
			arrangedViews,
			spacing: 2
		)
		stack.setCustomSpacing(
			10,
			after: heading
		)
		AppKitLayout.pin(
			stack,
			to: surface,
			inset: 12
		)
		for row in rows
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
			row.heightAnchor.constraint(equalToConstant: 54).isActive = true
		}
		for index in rows.indices
		{
			rows[index].nextKeyView = rows[(index + 1) % rows.count]
		}
		view = surface
		render(mode: selectedMode)
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
	private let explanation = NSTextField(wrappingLabelWithString: "")
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

		titleLabel.stringValue = mode.title
		titleLabel.font = .systemFont(ofSize: 13)
		explanation.stringValue = mode.description
		explanation.font = .systemFont(ofSize: 12)
		explanation.maximumNumberOfLines = 2

		let symbol: String
		switch mode
		{
		case .askForApproval: symbol = "hand.raised"
		case .approveForMe: symbol = "checkmark.shield"
		case .fullAccess: symbol = "exclamationmark.shield"
		}
		symbolView.image = NSImage(
			systemSymbolName: symbol,
			accessibilityDescription: nil
		)
		checkView.image = NSImage(
			systemSymbolName: "checkmark",
			accessibilityDescription: nil
		)

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
				constant: 8
			),
			symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
			symbolView.widthAnchor.constraint(equalToConstant: 16),
			symbolView.heightAnchor.constraint(equalToConstant: 18),
			titleLabel.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 32
			),
			titleLabel.topAnchor.constraint(
				equalTo: topAnchor,
				constant: 6
			),
			titleLabel.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -28
			),
			explanation.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			explanation.topAnchor.constraint(
				equalTo: titleLabel.bottomAnchor,
				constant: 2
			),
			explanation.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -28
			),
			explanation.bottomAnchor.constraint(
				lessThanOrEqualTo: bottomAnchor,
				constant: -4
			),
			checkView.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -8
			),
			checkView.centerYAnchor.constraint(equalTo: centerYAnchor),
			checkView.widthAnchor.constraint(equalToConstant: 14),
			checkView.heightAnchor.constraint(equalToConstant: 14),
		])
		render(selected: false)
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
		let tint: NSColor = highlightsFullAccess ? .systemOrange : .labelColor
		titleLabel.textColor = tint
		explanation.textColor = highlightsFullAccess ? tint : .secondaryLabelColor
		symbolView.contentTintColor = selected ? tint : .secondaryLabelColor
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
