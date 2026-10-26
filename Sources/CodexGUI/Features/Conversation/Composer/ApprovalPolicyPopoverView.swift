import AppKit

@MainActor
final class ApprovalPolicyPopoverView: NSViewController, DesktopPopoverMaterialContent
{
	var onSelect: ((ApprovalMode) -> Void)?
	var openDocumentation: (URL) -> Void =
	{
		NSWorkspace.shared.open($0)
	}
	private let learnMoreButton = DesktopStyledButton(
		title: "Learn more",
		presentation: .link
	)
	private var selectedMode: ApprovalMode? = .askForApproval
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
		let surface = NSView()
		let header = makeHeadingRow()
		header.heightAnchor.constraint(equalToConstant: LayoutTokens.ApprovalPopover.headerHeight)
			.isActive = true

		rows = makePolicyRows()
		for row in rows
		{
			row.onHover =
			{
				[weak self, weak row] in
				self?.rows.filter
				{
					$0 !== row
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
		}

		for index in rows.indices
		{
			rows[index].nextKeyView = rows[(index + 1) % rows.count]
		}

		rows.last?.nextKeyView = learnMoreButton
		learnMoreButton.nextKeyView = rows.first

		surface.setAccessibilityElement(true)
		surface.setAccessibilityRole(.menu)
		view = surface
		render(mode: selectedMode)
	}

	private func makeHeadingRow() -> NSStackView
	{
		let heading =
			DesktopTextField(labelWithString: "How should Codex actions be approved?")
		heading.font = AppKitFontResolver.font(TypographyTokens.Popover.title)
		heading.textColor = AppKitColorTokens.composerSecondaryText
		heading.setAccessibilityLabel(heading.stringValue)

		learnMoreButton.target = self
		learnMoreButton.action = #selector(learnMore)
		learnMoreButton.setAccessibilityRole(.link)
		learnMoreButton.setAccessibilityLabel("Learn more about sandboxing and approvals")
		let header = AppKitLayout.horizontalStack(
			[heading, NSView(), learnMoreButton],
			spacing: LayoutTokens.ApprovalPopover.headerSpacing,
			alignment: .centerY
		)
		header.edgeInsets = NSEdgeInsets(
			top: LayoutTokens.ApprovalPopover.verticalInset,
			left: LayoutTokens.ApprovalPopover.horizontalInset,
			bottom: LayoutTokens.ApprovalPopover.verticalInset,
			right: LayoutTokens.ApprovalPopover.horizontalInset
		)
		heading.heightAnchor
			.constraint(equalToConstant: LayoutTokens.ApprovalPopover.headerTextHeight)
			.isActive = true

		return header
	}

	@objc private func learnMore()
	{
		openDocumentation(DocumentationLinks.sandboxing)
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
			}) ?? rows.first
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

	func render(mode: ApprovalMode?)
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
private final class ApprovalPolicyRow: DesktopMenuRow
{
	let mode: ApprovalMode
	var onNavigate: ((Int) -> Void)?

	init(mode: ApprovalMode)
	{
		self.mode = mode
		let icon: NSImage
		let explanation: String
		switch mode
		{
		case .askForApproval:
			icon = ApprovalPolicyIcons.askForApproval
			explanation = "Always ask to edit external files and use the internet"
		case .approveForMe:
			icon = ApprovalPolicyIcons.approveForMe
			explanation = "Only ask for actions detected as potentially unsafe"
		case .fullAccess:
			icon = ComposerFooterIcons.fullAccess
			explanation = "Unrestricted access to the internet and any file on your computer"
		}
		super.init(content: Content(
			title: mode.title,
			icon: icon,
			subtitle: explanation,
			indicator: .checkmark
		))
		setAccessibilityHelp(mode.description)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func render(selected: Bool)
	{
		content.role = selected && mode == .fullAccess ? .warning : .normal
		checked = selected
		setAccessibilityHelp(mode.description)
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
