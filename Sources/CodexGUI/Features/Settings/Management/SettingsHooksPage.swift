import AppKit

@MainActor
final class SettingsHooksPage: SettingsManagementPage
{
	init(backend: SettingsBackend)
	{
		super.init(
			title: "Hooks",
			backend: backend
		)
	}
	required init?(coder: NSCoder)
	{
		nil
	}

	override var subtitleView: NSView?
	{
		let description = SettingsPageLayout.message(
			"Manage lifecycle hooks from config and enabled plugins."
		)
		let link = DesktopStyledButton(
			title: "Learn more",
			target: self,
			action: #selector(openDocumentation)
		)
		link.presentation = .nativeLink
		let stack = NSStackView(views: [description, link, NSView()])
		stack.orientation = .horizontal
		stack.spacing = 4
		return stack
	}

	override var headerAccessory: NSView?
	{
		let refresh = DesktopActionButton(
			title: "Refresh",
			presentation: .icon
		)
		refresh.image = NSImage(
			systemSymbolName: "arrow.clockwise",
			accessibilityDescription: nil
		)
		refresh.setAccessibilityLabel("Refresh hooks")
		refresh.isEnabled = !isOperating
		refresh.onAction =
		{
			[weak self] in self?.load()
		}
		return refresh
	}

	override func sectionsForDisplay() -> [NSView]
	{
		var sections: [NSView] = []
		if !rows.isEmpty
		{
			sections.append(SettingsPageLayout.card(rows: rows))
		}
		return sections
	}

	@objc private func openDocumentation()
	{
		if let url = URL(string: "https://developers.openai.com/docs/hooks")
		{
			NSWorkspace.shared.open(url)
		}
	}

	override func load()
	{
		run
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			let response = try await backend.perform(
				"hooks/list",
				params: [:]
			)
			let entries = response["data"] as? [[String: Any]] ?? []
			rows = entries.flatMap
			{
				entry -> [NSView] in
				let hooks = entry["hooks"] as? [[String: Any]] ?? []
				return hooks.map
				{
					hook in
					let key = hook["key"] as? String ?? ""
					let statePath = "hooks.state.\(SettingsManagementPolicy.quotedKey(key))"
					let name = hook["eventName"] as? String ?? key
					let managed = hook["isManaged"] as? Bool ?? true
					let trust = hook["trustStatus"] as? String ?? "untrusted"
					let enable = toggle(
						name,
						enabled: hook["enabled"] as? Bool ?? false
					)
					{
						[weak self] enabled in
						guard let self
						else
						{
							return
						}
						run
						{
							[weak self] in
							guard let self
							else
							{
								return
							}
							await backend.write(["\(statePath).enabled": enabled])
							loadedHooks()
						}
					}
					(enable as? NSControl)?.isEnabled = !managed
					var controls = [enable]
					if !managed, trust != "trusted", let hash = hook["currentHash"] as? String
					{
						controls.append(button("Trust")
						{
							[weak self] in
							guard let self
							else
							{
								return
							}
							confirm(
								"Trust hook",
								detail: hook["command"] as? String ?? name
							)
							{
								[weak self] in
								guard let self
								else
								{
									return
								}
								run
								{
									[weak self] in
									guard let self
									else
									{
										return
									}
									let path = "\(statePath).trusted_hash"
									await backend.write([path: hash])
									loadedHooks()
								}
							}
						})
					}
					return SettingsPageLayout.row(
						title: name,
						detail: "\(trust) · \(hook["sourcePath"] as? String ?? "")",
						control: self.controls(controls)
					)
				}
			}
		}
	}

	private func loadedHooks()
	{
		reloadAfterOperation()
	}
}
