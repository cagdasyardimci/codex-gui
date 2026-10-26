import AppKit

/// General settings use the same reading column and cards as the account and connection pages.
@MainActor
final class SettingsGeneralPage: NSView
{
	var onChooseEditor: (() -> Void)?
	var onUseSystemDefault: (() -> Void)?
	var onSelectEditorApplication: ((URL?) -> Void)?
	var onSelectApprovalMode: ((ApprovalMode) -> Void)?

	private let defaultPermissions = RemoteConnectionsSwitch()
	private let configuredPermissions = SettingsPageLayout.message("")
	private let fullAccess = RemoteConnectionsSwitch()
	private let editor = SettingsEditorPicker()
	let notificationControls = SettingsNotificationControls()
	private var approvalMode = ApprovalMode.askForApproval
	private var document: SettingsPageDocument?

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		defaultPermissions.setAccessibilityLabel("Default permissions")
		fullAccess.target = self
		fullAccess.action = #selector(selectFullAccess)
		fullAccess.setAccessibilityLabel("Full access")
		renderPermissions(
			mode: .askForApproval,
			enabled: false
		)

		let permissionRows = [
			row(
				"Default permissions",
				detail: "Codex can read and edit files in its workspace. "
					+ "It can ask for additional access when needed.",
				control: defaultPermissions
			),
			row(
				"Full access",
				detail: "Codex can edit any file on your computer "
					+ "and run commands with network access, "
					+ "without your approval. This increases the risk of data loss, leaks, "
					+ "or unexpected behavior.",
				control: fullAccess
			),
		]
		editor.onChooseEditor =
		{
			[weak self] in self?.onChooseEditor?()
		}
		editor.onUseSystemDefault =
		{
			[weak self] in self?.onUseSystemDefault?()
		}
		editor.onSelectApplication =
		{
			[weak self] application in self?.onSelectEditorApplication?(application)
		}
		let permissions = section(
			"Permissions",
			rows: permissionRows
		)
		let general = section(
			"General",
			rows: [
				row(
					"Editor",
					detail: "Where files and folders open by default",
					control: editor
				),
			]
		)
		let notificationSection = SettingsPageLayout.section(
			title: "Notifications",
			content: notificationControls
		)
		configuredPermissions.isHidden = true
		let document = SettingsPageLayout.document(
			title: "General",
			sections: [configuredPermissions, permissions, general, notificationSection],
			columnWidth: .fitsViewport
		)
		self.document = document
		AppKitLayout.pin(
			document,
			to: self,
			inset: 0
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func setAdditionalSettings(_ content: NSView)
	{
		document?.appendSection(content)
	}

	func setEditor(application: URL?)
	{
		editor.setApplication(application)
	}

	func setNotificationStatus(_ message: String)
	{
		notificationControls.setNotificationStatus(message)
	}

	func renderPermissions(
		mode: ApprovalMode,
		enabled: Bool,
		configurationDefaults: RunConfigurationDefaults? = nil
	)
	{
		approvalMode = mode
		defaultPermissions.state = .on
		fullAccess.state = mode == .fullAccess ? .on : .off
		defaultPermissions.isEnabled = false
		fullAccess.isEnabled = enabled
		fullAccess.toolTip = mode == .approveForMe
			? "Current permission mode: Approve for me" : nil
		let custom = configurationDefaults.map
		{
			$0.approvalPolicy != nil || $0.sandboxMode != nil || $0.networkAccess != nil
		} ?? false
		configuredPermissions.isHidden = !custom
		if custom, let defaults = configurationDefaults
		{
			let sandbox = defaults.sandboxMode?.rawValue ?? "composer preset"
			let approval = defaults.approvalPolicy?.rawValue ?? "composer preset"
			configuredPermissions.stringValue = "Configured permissions: \(sandbox), "
				+ "approval \(approval). Choose a preset below to replace these defaults."
			defaultPermissions.state = .off
			fullAccess.state = defaults.sandboxMode == .dangerFullAccess
				&& defaults.approvalPolicy == .never ? .on : .off
		}
	}

	@objc private func selectFullAccess()
	{
		let mode: ApprovalMode = fullAccess.state == .on ? .fullAccess : .askForApproval
		renderPermissions(
			mode: approvalMode,
			enabled: fullAccess.isEnabled
		)
		onSelectApprovalMode?(mode)
	}

	private func section(
		_ title: String,
		rows: [NSView]
	) -> NSView
	{
		SettingsPageLayout.section(
			title: title,
			rows: rows
		)
	}

	private func row(
		_ title: String,
		detail: String?,
		control: NSView
	) -> NSView
	{
		SettingsPageLayout.row(
			title: title,
			detail: detail,
			control: control
		)
	}
}
