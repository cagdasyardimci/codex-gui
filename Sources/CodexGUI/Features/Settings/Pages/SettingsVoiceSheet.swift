import AppKit

/// Presents the voice catalog and its actions in an attached Settings sheet.
@MainActor
final class SettingsVoiceSheet: DesktopConfirmationPanel
{
	private let cancel = DesktopStyledButton(
		title: "Cancel",
		presentation: .dialogCancel,
		size: .regular
	)
	private let done = DesktopStyledButton(
		title: "Done",
		presentation: .dialogPrimary,
		size: .regular
	)
	private var rows: [(String, SettingsChoiceMenuRow)] = []
	private var shell: DesktopDialogShell?
	var onSelect: ((String) -> Void)?
	var onDone: (() -> Void)?

	init(
		choices: [SettingsChoicePicker.Choice],
		availableHeight: CGFloat
	)
	{
		super.init(
			contentRect: .zero,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		title = "Voice"
		isReleasedWhenClosed = false
		isOpaque = false
		backgroundColor = .clear
		hasShadow = true

		let scroll = NSScrollView()
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.scrollerStyle = .overlay
		scroll.drawsBackground = false
		scroll.contentView.drawsBackground = false
		scroll.heightAnchor.constraint(equalToConstant: min(
			480,
			max(
				180,
				availableHeight - 120
			)
		))
		.isActive = true
		let document = DesktopFlippedView()
		document.translatesAutoresizingMaskIntoConstraints = false
		scroll.documentView = document
		let sections = AppKitLayout.verticalStack(
			[],
			spacing: LayoutTokens.Button.contentSpacing
		)
		AppKitLayout.pin(
			sections,
			to: document,
			inset: 0
		)
		document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

		var heading: String?
		var group: [NSView] = []
		func appendGroup()
		{
			guard !group.isEmpty
			else
			{
				return
			}
			let section = heading.map
			{
				SettingsPageLayout.section(
					title: $0,
					rows: group
				)
			}
			?? SettingsPageLayout.card(rows: group)
			sections.addArrangedSubview(section)
			section.widthAnchor.constraint(equalTo: sections.widthAnchor).isActive = true
			group.removeAll()
		}
		for choice in choices
		{
			if choice.section != heading
			{
				appendGroup()
				heading = choice.section
			}
			let row = SettingsChoiceMenuRow(
				title: choice.title,
				icon: nil,
				checked: false,
				detail: nil,
				showsCheckbox: false
			)
			row.setAccessibilityRole(.radioButton)
			row.onChoose =
			{
				[weak self] in self?.onSelect?(choice.id)
			}
			group.append(row)
			rows.append((choice.id, row))
		}
		appendGroup()

		cancel.target = self
		cancel.action = #selector(cancelOperation(_:))
		done.target = self
		done.action = #selector(doneAction)
		done.keyEquivalent = "\r"

		let shell = DesktopDialogShell(
			title: title,
			content: scroll,
			actions: [cancel, done]
		)
		shell.onClose =
		{
			[weak self] in self?.cancelOperation(nil)
		}
		self.shell = shell
		contentView = shell
		shell.resize(window: self)
		defaultButtonCell = done.cell as? NSButtonCell
	}

	func render(
		selection: String,
		canEdit: Bool,
		isSaving: Bool
	)
	{
		for (id, row) in rows
		{
			row.checked = id == selection
			row.isEnabled = canEdit
		}
		cancel.isEnabled = !isSaving
		shell?.closeButton.isEnabled = !isSaving
		done.isEnabled = canEdit && rows.contains
		{
			$0.0 == selection
		}
	}

	override func cancelOperation(_ sender: Any?)
	{
		if cancel.isEnabled
		{
			super.cancelOperation(sender)
		}
	}

	@objc private func doneAction()
	{
		onDone?()
	}
}
