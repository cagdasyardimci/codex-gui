import AppKit

/// Local project creation owns folder selection and form eligibility; the shell owns dialog chrome.
@MainActor
final class ProjectCreationViewController: NSViewController
{
	var onDecision: ((Bool) -> Void)?
	let nameField = SettingsFormField(
		title: "Project name",
		presentation: .projectName,
		leadingIcon: .folder,
		showsTitle: false
	)
	let createButton = DesktopStyledButton(
		title: "Create project",
		presentation: .dialogPrimary,
		size: .regular
	)
	let cancelButton = DesktopStyledButton(
		title: "Cancel",
		presentation: .dialogDismiss,
		size: .regular
	)
	let deviceButton = DesktopStyledButton(
		title: "this computer",
		presentation: .inlineValue,
		size: .compact
	)
	let addButton = DesktopStyledButton(
		title: "Add",
		presentation: .folderAdd,
		size: .regular
	)
	private(set) var folder: URL?
	private var deviceMenu: DesktopActionMenu?
	private lazy var dialog = DesktopDialogShell(
		title: "Create project",
		content: makeContent(),
		actions: [cancelButton, createButton],
		style: .projectCreate
	)
	var projectName: String
	{
		nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	override func loadView()
	{
		createButton.target = self
		createButton.action = #selector(create)
		createButton.keyEquivalent = "\r"
		cancelButton.target = self
		cancelButton.action = #selector(cancel)
		deviceButton.target = self
		deviceButton.action = #selector(showDevices)
		deviceButton.showsTrailingChevron = true
		addButton.symbol = .folderPlus
		addButton.target = self
		addButton.action = #selector(addFolder)
		nameField.onChange =
		{
			[weak self] _ in self?.refreshEligibility()
		}
		dialog.onClose =
		{
			[weak self] in self?.onDecision?(false)
		}
		view = dialog
		refreshEligibility()
	}

	private func makeContent() -> NSView
	{
		let heading = DesktopLineBoxLabel(
			"Source folders",
			role: TypographyTokens.Text.body
		)
		heading.textColor = AppKitColorTokens.primaryText
		let source = DesktopSurface(
			AppKitColorTokens.composer,
			cornerRadius: 10,
			bordered: true
		)
		let prompt = DesktopLineBoxLabel(
			"Add a folder on",
			role: TypographyTokens.Text.menu
		)
		prompt.textColor = AppKitColorTokens.secondaryText
		let deviceRow = AppKitLayout.horizontalStack(
			[prompt, deviceButton],
			spacing: 4
		)
		let sourceControls = AppKitLayout.verticalStack(
			[deviceRow, addButton],
			spacing: 8
		)
		sourceControls.alignment = .centerX
		AppKitLayout.pin(
			sourceControls,
			to: source,
			insets: NSEdgeInsets(
				top: 22,
				left: 12,
				bottom: 26,
				right: 12
			)
		)
		let stack = AppKitLayout.verticalStack(
			[nameField, heading, source],
			spacing: 12
		)
		stack.setCustomSpacing(
			10,
			after: heading
		)
		for row in [nameField, source]
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		return stack
	}

	func selectFolder(_ url: URL)
	{
		folder = url
		addButton.title = url.lastPathComponent
		if projectName.isEmpty
		{
			nameField.stringValue = url.lastPathComponent
		}
		refreshEligibility()
	}

	private func refreshEligibility()
	{
		createButton.isEnabled = folder != nil && !projectName.isEmpty
	}

	@objc private func create()
	{
		guard view.window?.makeFirstResponder(nil) == true, folder != nil,
				!projectName.isEmpty
		else
		{
			return
		}
		onDecision?(true)
	}
	@objc private func cancel()
	{
		onDecision?(false)
	}

	@objc private func showDevices()
	{
		if deviceMenu?.host.isShown == true
		{
			deviceMenu?.close(); return
		}
		let menu = NSMenu()
		menu.autoenablesItems = false
		let local = NSMenuItem(
			title: "This computer",
			action: #selector(selectComputer),
			keyEquivalent: ""
		)
		local.image = DesktopIcons.localComputerImage()
		local.target = self
		local.state = .on
		menu.addItem(local)
		menu.addItem(.separator())
		let remote = NSMenuItem(
			title: "Add remote",
			action: nil,
			keyEquivalent: ""
		)
		remote.image = DesktopIcons.image(.plus)
		remote.isEnabled = false
		menu.addItem(remote)
		deviceMenu = DesktopActionMenu(
			menu: menu,
			minimumWidth: 200,
			alignment: .centered,
			showsCheckmarks: true,
			accessibilityLabel: "Source computer"
		)
		deviceMenu?.show(from: deviceButton)
	}

	@objc private func selectComputer()
	{
	}

	@objc private func addFolder()
	{
		guard let window = view.window
		else
		{
			return
		}
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.allowsMultipleSelection = false
		panel.prompt = "Add"
		panel.beginSheetModal(for: window)
		{
			[weak self] response in
			guard response == .OK, let url = panel.url
			else
			{
				return
			}
			self?.selectFolder(url)
		}
	}
}
