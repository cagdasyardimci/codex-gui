import AppKit

@MainActor
final class SettingsBrowserPage: NSView
{
	private let backend: SettingsBackend
	private var document: NSView?
	private var permissionTable: SettingsBrowserPermissionsTable?
	private var showsSiteSettings = false
	private var actions: [SettingsBrowserActionButton] = []
	private var sitePanel: SettingsBrowserSitePanel?
	private let browser = RemoteConnectionsSwitch()
	private let siteTools = RemoteConnectionsSwitch()

	init(backend: SettingsBackend)
	{
		self.backend = backend
		super.init(frame: .zero)
		browser.setAccessibilityLabel("Browser")
		browser.target = self
		browser.action = #selector(changeBrowser)
		siteTools.setAccessibilityLabel("Enable full CDP access")
		siteTools.target = self
		siteTools.action = #selector(changeSiteTools)
		refresh()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func refresh()
	{
		let resolvedBrowser = backend.featureEnabled("browser_use")
		browser.state = resolvedBrowser.map
		{
			$0 ? .on : .off
		} ?? .mixed
		browser.isEnabled = editable && resolvedBrowser != nil
		let resolvedSiteTools = backend.featureEnabled("browser_use_full_cdp_access")
		siteTools.state = resolvedSiteTools.map
		{
			$0 ? .on : .off
		} ?? .mixed
		siteTools.isEnabled = editable && resolvedSiteTools != nil
		let featureRequirements = backend.requirements["featureRequirements"] as? [String: Bool]
		if let fixed = featureRequirements?["browser_use"]
		{
			browser.state = fixed ? .on : .off
			browser.isEnabled = false
		}
		if let fixed = featureRequirements?["browser_use_full_cdp_access"]
		{
			siteTools.state = fixed ? .on : .off
			siteTools.isEnabled = false
		}
		let horizontalOffset = permissionTable?.horizontalOffset ?? 0
		let verticalOffset = (document?.subviews.first as? NSScrollView)?
			.contentView.bounds.origin ?? .zero
		document?.removeFromSuperview()
		actions.removeAll()
		let history = SettingsChoicePicker(
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
			selectedID: (backend.value("browser_use.allow_history_access") as? Bool).map
			{
				$0 ? "allow" : "deny"
			} ?? "default"
		)
		history.setAccessibilityLabel("Browser history access")
		history.isEnabled = editable
		history.onSelect =
		{
			[weak self] value in
			guard let self
			else
			{
				return
			}
			Task
			{
				await self.backend.write([
					"browser_use.allow_history_access": value == "default"
						? NSNull() : value == "allow",
				])
			}
		}
		let permissions = SettingsPageLayout.section(
			title: "Browser permissions",
			rows: [
				SettingsPageLayout.row(
					title: "Site settings",
					detail: "Manage website permissions for browser tools.",
					control: action(
						showsSiteSettings ? "Done" : "Manage",
						enabled: true
					)
					{
						[weak self] in
						guard let self
						else
						{
							return
						}
						self.showsSiteSettings.toggle()
						self.refresh()
					}
				),
				SettingsPageLayout.row(
					title: "History",
					detail: "Choose whether Codex can access browser history.",
					control: history
				),
			]
		)
		let browserCard = SettingsPageLayout.card(rows: [SettingsPageLayout.row(
			title: "Browser",
			detail: "Allow Codex to use browser tools.",
			control: browser
		)])
		let defaults = backend.value("browser_use.default_origin_policy") as? [String: Any] ?? [:]
		let table = SettingsBrowserPermissionsTable(
			defaults: defaults,
			origins: origins,
			enabled: editable,
			onDefault:
			{
				[weak self] key, value in
				guard let self
				else
				{
					return
				}
				Task
				{
					await self.backend.write(["browser_use.default_origin_policy.\(key)": value])
				}
			},
			onSite:
			{
				[weak self] site, key, value in
				guard let self, self.editable
				else
				{
					return
				}
				var current = self.origins
				guard var policy = current[site] as? [String: Any]
				else
				{
					return
				}
				policy[key] = value is NSNull ? nil : value
				current[site] = policy
				Task
				{
					await self.backend.write(["browser_use.origins": current])
				}
			},
			onEdit:
			{
				[weak self] in self?.editSite($0)
			},
			onRemove:
			{
				[weak self] in self?.removeSite($0)
			}
		)
		let addSite = SettingsPageLayout.section(
			title: "Custom permissions",
			rows: [SettingsPageLayout.row(
				title: "Add a website",
				detail: "Set permissions for individual websites.",
				control: action("Add site")
				{
					[weak self] in self?.editSite(nil)
				}
			)]
		)
		let advanced = SettingsPageLayout.section(
			title: "Advanced",
			rows: [SettingsPageLayout.row(
				title: "Enable full CDP access",
				detail: "Allow browser tools to use the full Chrome DevTools Protocol.",
				control: siteTools
			)]
		)
		var sections: [NSView] = [browserCard, permissions]
		if showsSiteSettings
		{
			sections.append(contentsOf: [table, addSite])
		}
		sections.append(advanced)
		let content = SettingsPageLayout.document(
			title: "Browser",
			sections: sections,
			subtitle: "Manage browser tools and site access."
		)
		document = content
		permissionTable = showsSiteSettings ? table : nil
		AppKitLayout.pin(
			content,
			to: self,
			inset: 0
		)
		layoutSubtreeIfNeeded()
		table.restoreHorizontalOffset(horizontalOffset)
		if let scroll = content.subviews.first as? NSScrollView
		{
			scroll.contentView.scroll(to: verticalOffset)
			scroll.reflectScrolledClipView(scroll.contentView)
		}
	}

	@objc private func changeBrowser()
	{
		let enabled = browser.state == .on
		refresh()
		Task
		{
			await backend.write(["features.browser_use": enabled])
		}
	}

	@objc private func changeSiteTools()
	{
		let enabled = siteTools.state == .on
		refresh()
		Task
		{
			await backend.write(["features.browser_use_full_cdp_access": enabled])
		}
	}

	private var editable: Bool
	{
		backend.isConnected && !backend.isBusy
	}

	private var origins: [String: Any]
	{
		backend.value("browser_use.origins") as? [String: Any] ?? [:]
	}

	private func action(
		_ title: String,
		enabled: Bool? = nil,
		handler: @escaping () -> Void
	) -> NSButton
	{
		let button = SettingsBrowserActionButton(
			title: title,
			handler: handler
		)
		button.isEnabled = enabled ?? editable
		actions.append(button)
		return button
	}

	private func editSite(_ site: String?)
	{
		guard editable, let window
		else
		{
			return
		}
		let initial = site.flatMap
		{
			origins[$0] as? [String: Any]
		} ?? [:]
		let panel = SettingsBrowserSitePanel(
			site: site,
			policy: initial,
			defaults: backend.value("browser_use.default_origin_policy") as? [String: Any] ?? [:]
		)
		panel.onSave =
		{
			[weak self, weak panel] origin, policy in
			guard let self, self.editable
			else
			{
				return
			}
			var current = self.origins
			if let site,
				!(NSDictionary(dictionary: current[site] as? [String: Any] ?? [:])
				.isEqual(to: initial))
			{
				panel?.showError("This rule changed. Cancel and reopen it before saving.")
				return
			}
			if site != origin && current[origin] != nil
			{
				panel?.showError("A rule already exists for this site.")
				return
			}
			if let site
			{
				current.removeValue(forKey: site)
			}
			current[origin] = policy
			panel?.dismiss()
			Task
			{
				await self.backend.write(["browser_use.origins": current])
			}
		}
		sitePanel = panel
		window.beginSheet(panel)
	}

	private func removeSite(_ site: String)
	{
		guard editable, let window
		else
		{
			return
		}
		let initial = origins[site] as? [String: Any] ?? [:]
		let confirmation = DesktopNativeConfirmation(
			title: "Remove permissions for \(site)?",
			message: "This site will use the default website permissions.",
			confirmTitle: "Remove",
			defaultAction: .confirm
		)
		confirmation.beginSheet(in: window)
		{
			[weak self] confirmed in
			guard confirmed, let self, self.editable,
					NSDictionary(dictionary: self.origins[site] as? [String: Any] ?? [:])
					.isEqual(to: initial)
			else
			{
				return
			}
			var current = self.origins
			current.removeValue(forKey: site)
			Task
			{
				await self.backend.write(["browser_use.origins": current])
			}
		}
	}
}

@MainActor
final class SettingsBrowserActionButton: RemoteConnectionsButton
{
	private let handler: () -> Void

	init(
		title: String,
		handler: @escaping () -> Void
	)
	{
		self.handler = handler
		super.init(
			title: title,
			presentation: .secondary
		)
		target = self
		action = #selector(performAction)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	@objc private func performAction()
	{
		handler()
	}
}
