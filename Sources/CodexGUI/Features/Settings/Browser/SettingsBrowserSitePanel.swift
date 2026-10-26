import AppKit

@MainActor
final class SettingsBrowserSitePanel: NSPanel, NSTextFieldDelegate
{
	var onSave: ((String, [String: String]) -> Void)?
	private let site = SettingsFormField(
		title: "Site",
		placeholder: "https://example.com",
		showsTitle: false
	)
	private var shell: DesktopDialogShell?
	private let save = DesktopStyledButton(
		title: "Add",
		presentation: .primary
	)
	private let originalSite: String?
	private let initialPolicy: [String: String]
	private let defaults: [String: Any]
	private var selections: [String: String]
	private var extraRows: [NSView] = []
	private let more = DesktopStyledButton(
		title: "More options",
		presentation: .secondary
	)

	init(
		site: String?,
		policy: [String: Any],
		defaults: [String: Any]
	)
	{
		originalSite = site
		initialPolicy = policy.compactMapValues
		{
			$0 as? String
		}
		selections = initialPolicy
		self.defaults = defaults
		super.init(
			contentRect: .zero,
			styleMask: [.titled, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		title = site == nil ? "Add site permission" : "Edit site permission"
		titleVisibility = .hidden
		titlebarAppearsTransparent = true
		isReleasedWhenClosed = false
		self.site.stringValue = site ?? ""
		self.site.onChange =
		{
			[weak self] value in self?.validate(showError: !value.isEmpty)
		}
		self.site.onEndEditing =
		{
			[weak self] value in self?.validate(showError: !value.isEmpty)
		}
		let policyRows = SettingsBrowserPolicy.fields.enumerated().map
		{
			index, field -> NSView in
			let picker = SettingsChoicePicker(
				choices: [
					.init(
						id: "default",
						title: "Use default"
					),
					.init(
						id: "allow",
						title: "Allow"
					),
					.init(
						id: "deny",
						title: "Block"
					),
				],
				selectedID: selections[field.key] ?? "default"
			)
			picker.setAccessibilityLabel(field.title)
			picker.onSelect =
			{
				[weak self, weak picker] value in
				picker?.select(id: value)
				self?.selections[field.key] = value == "default" ? nil : value
				self?.validate(showError: false)
			}
			let row = SettingsPageLayout.row(
				title: field.title,
				detail: nil,
				control: picker
			)
			if index > 0
			{
				row.isHidden = true
				extraRows.append(row)
			}
			return row
		}
		let cancel = DesktopStyledButton(
			title: "Cancel",
			presentation: .secondary
		)
		cancel.target = self
		cancel.action = #selector(cancelAction)
		cancel.keyEquivalent = "\u{1b}"
		save.title = site == nil ? "Add" : "Save"
		save.setAccessibilityLabel(save.title)
		save.target = self
		save.action = #selector(saveAction)
		save.keyEquivalent = "\r"
		defaultButtonCell = save.cell as? NSButtonCell
		more.target = self
		more.action = #selector(toggleOptions)
		let content = AppKitLayout.verticalStack(
			[self.site] + policyRows,
			spacing: 10
		)
		for item in [self.site] + policyRows
		{
			item.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
		}
		let shell = DesktopDialogShell(
			title: title,
			message: "Choose permissions for a website.",
			content: content,
			actions: [cancel, save],
			leadingAction: more
		)
		shell.onClose =
		{
			[weak self] in self?.dismiss()
		}
		self.shell = shell
		contentView = shell
		validate(showError: false)
		initialFirstResponder = self.site.input
	}

	func controlTextDidChange(_ notification: Notification)
	{
		validate(showError: !site.stringValue.isEmpty)
	}

	func controlTextDidEndEditing(_ notification: Notification)
	{
		validate(showError: !site.stringValue.isEmpty)
	}

	private var normalizedSite: String?
	{
		if site.stringValue == originalSite
		{
			return originalSite
		}
		return SettingsBrowserPolicy.normalizedOrigin(site.stringValue)
	}

	private func validate(showError: Bool)
	{
		let valid = normalizedSite != nil
		let changed = originalSite == nil
			? SettingsBrowserPolicy.hasChanges(
				selections,
				defaults: defaults
			)
			: selections != initialPolicy || normalizedSite != originalSite
		site.error = !valid && showError
			? "Enter an HTTP or HTTPS origin without a path, query, or sign-in details." : ""
		site.status = valid && !changed
			? "These permissions match the defaults or the existing rule." : ""
		save.isEnabled = valid && changed
		resizeToFit()
	}

	func showError(_ message: String)
	{
		site.error = message
		save.isEnabled = false
		resizeToFit()
	}

	private func resizeToFit()
	{
		shell?.resize(window: self)
	}

	@objc private func toggleOptions()
	{
		let expanded = extraRows.first?.isHidden ?? false
		for row in extraRows
		{
			row.isHidden = !expanded
		}
		more.title = expanded ? "Fewer options" : "More options"
		resizeToFit()
	}

	@objc private func saveAction()
	{
		guard save.isEnabled, let normalizedSite
		else
		{
			return
		}
		onSave?(normalizedSite, selections)
	}

	@objc private func cancelAction()
	{
		dismiss()
	}

	override func cancelOperation(_ sender: Any?)
	{
		dismiss()
	}

	func dismiss()
	{
		if let sheetParent
		{
			sheetParent.endSheet(self)
		}
		orderOut(nil)
	}
}
