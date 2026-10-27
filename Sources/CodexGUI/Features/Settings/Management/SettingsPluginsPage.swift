import AppKit

@MainActor
final class SettingsPluginsPage: SettingsManagementPage, NSSearchFieldDelegate
{
	private enum Tab: String,
		CaseIterable
	{
		case plugins = "Plugins", mcps = "MCPs", skills = "Skills",
				marketplaces = "Marketplaces"
	}
	private var tab = Tab.plugins
	private var tabCounts: [Tab: Int] = [:]
	private var catalog: [[String: Any]] = []
	private var catalogLoaded = false
	private var cachedRows: [Tab: [NSView]] = [:]
	private var mcpForm: SettingsMCPForm?
	private var pluginsView: SettingsPluginsCatalogView?
	private let searchField = SettingsSearchField()
	private let pluginFilter = SettingsChoicePicker(choices: [
		.init(
			id: "installed",
			title: "Installed"
		),
		.init(
			id: "all",
			title: "All plugins"
		),
	])
	private var installedOnly = true

	init(backend: SettingsBackend)
	{
		super.init(
			title: "Plugins",
			backend: backend
		)
		searchField.usesOutline = true
		searchField.usesCatalogStyle = true
		searchField.searchPrompt = "Search plugins"
		searchField.setAccessibilityLabel("Search plugins")
		searchField.delegate = self
		searchField.widthAnchor
			.constraint(equalToConstant: LayoutTokens.Settings.catalogSearchWidth)
			.isActive = true
		searchField.heightAnchor
			.constraint(equalToConstant: LayoutTokens.Settings.catalogSearchHeight)
			.isActive = true
		pluginFilter.setAccessibilityLabel("Plugin catalog")
		pluginFilter.onSelect =
		{
			[weak self] id in
			self?.installedOnly = id == "installed"
			self?.pluginsView?.setFilter(installedOnly: id == "installed")
		}
		render()
	}
	required init?(coder: NSCoder)
	{
		nil
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if newWindow == nil
		{
			mcpForm = nil
		}
		super.viewWillMove(toWindow: newWindow)
	}

	override var displayTitle: String
	{
		mcpForm == nil ? pageTitle : "MCP server"
	}

	override var showsRefresh: Bool
	{
		false
	}

	override var pageSubtitle: String?
	{
		mcpForm == nil ? "Manage plugins, skills, and MCPs" : nil
	}

	override var headerSpacing: SettingsPageDocument.HeaderSpacing
	{
		.catalog
	}

	override var headerAccessory: NSView?
	{
		guard mcpForm == nil
		else
		{
			return nil
		}
		let browse = button(
			"Browse directory",
			presentation: .settingsHeader(primary: false)
		)
		{
			[weak self] in self?.browseDirectory()
		}
		let add = DesktopStyledButton(
			title: "Add ▾",
			presentation: .settingsHeader(primary: true)
		)
		add.target = self
		add.action = #selector(showAddMenu(_:))
		return controls([browse, add])
	}

	override func sectionsForDisplay() -> [NSView]
	{
		if mcpForm != nil
		{
			return super.sectionsForDisplay()
		}
		var sections: [NSView] = [toolbar()]
		if !rows.isEmpty
		{
			if tab == .mcps
			{
				sections.append(SettingsPageLayout.section(
					title: "Servers",
					rows: rows
				))
			}
			else if tab == .marketplaces
			{
				let list = AppKitLayout.verticalStack(
					rows,
					spacing: 0
				)
				for row in rows
				{
					row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
				}
				sections.append(list)
			}
			else
			{
				sections.append(SettingsPageLayout.card(rows: rows))
			}
		}
		return sections
	}

	override func load()
	{
		if let cached = cachedRows[tab]
		{
			rows = cached
			for row in rows
			{
				row.isHidden = false
			}
			pluginsView = tab == .plugins ? cached.first as? SettingsPluginsCatalogView : nil
			pluginsView?.setSearch(searchField.stringValue)
			render()
			return
		}
		switch tab
		{
		case .plugins, .marketplaces:
			if catalogLoaded
			{
				populateCatalogRows()
				render()
			}
			else
			{
				loadCatalog()
			}
		case .mcps: loadMCPs()
		case .skills: loadSkills()
		}
	}

	override func reloadAfterOperation()
	{
		cachedRows.removeValue(forKey: tab)
		if tab == .plugins || tab == .marketplaces
		{
			catalogLoaded = false
			cachedRows.removeValue(forKey: .plugins)
			cachedRows.removeValue(forKey: .marketplaces)
		}
		super.reloadAfterOperation()
	}

	func resetForEndPresentation()
	{
		invalidateLoad()
		cachedRows.removeAll()
		catalog = []
		catalogLoaded = false
		pluginsView = nil
		tabCounts = [:]
		rows = []
	}

	private func tabs() -> NSView
	{
		SettingsManagementTabs(
			titles: Tab.allCases.map(\.rawValue),
			selected: tab.rawValue,
			counts: Dictionary(uniqueKeysWithValues: tabCounts.map
			{
				($0.key.rawValue, $0.value)
			})
		)
		{
			[weak self] title in
			guard let self, !isOperating, let selected = Tab(rawValue: title)
			else
			{
				return
			}
			if selected == tab
			{
				cachedRows.removeValue(forKey: selected)
				if selected == .plugins || selected == .marketplaces
				{
					catalogLoaded = false
					cachedRows.removeValue(forKey: .plugins)
					cachedRows.removeValue(forKey: .marketplaces)
				}
			}
			tab = selected
			rows = []
			pluginsView = nil
			searchField.stringValue = ""
			searchField.searchPrompt = switch selected
			{
			case .plugins: "Search plugins"
			case .mcps: "Search MCP servers"
			case .skills: "Search skills"
			case .marketplaces: "Search marketplaces"
			}
			load()
		}
	}

	private func toolbar() -> NSView
	{
		var views: [NSView] = [tabs(), NSView(), searchField]
		if tab == .plugins
		{
			views.append(pluginFilter)
		}
		let toolbar = AppKitLayout.horizontalStack(
			views,
			spacing: 8,
			alignment: .centerY
		)
		return toolbar
	}

	private func browseDirectory()
	{
		let plugins = codexHome.appendingPathComponent(
			"plugins",
			isDirectory: true
		)
		NSWorkspace.shared.open(
			FileManager.default.fileExists(atPath: plugins.path) ? plugins : codexHome
		)
	}

	private var codexHome: URL
	{
		ProcessInfo.processInfo.environment["CODEX_HOME"].map
		{
			URL(fileURLWithPath: $0)
		}
		?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
	}

	@objc private func showAddMenu(_ sender: NSButton)
	{
		let menu = NSMenu()
		let server = NSMenuItem(
			title: "MCP server",
			action: #selector(addMCPFromMenu),
			keyEquivalent: ""
		)
		server.target = self
		menu.addItem(server)
		let marketplace = NSMenuItem(
			title: "Marketplace",
			action: #selector(addMarketplaceFromMenu),
			keyEquivalent: ""
		)
		marketplace.target = self
		menu.addItem(marketplace)
		menu.popUp(
			positioning: nil,
			at: NSPoint(
				x: 0,
				y: sender.bounds.maxY
			),
			in: sender
		)
	}

	@objc private func addMCPFromMenu()
	{
		addMCP()
	}

	@objc private func addMarketplaceFromMenu()
	{
		prompt(
			"Add marketplace",
			fields: [("Repository URL or path", "")]
		)
		{
			[weak self] values in
			guard let self, let source = values.first,
					!source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			else
			{
				return
			}
			mutate(
				"marketplace/add",
				params: ["source": source]
			)
		}
	}

	func controlTextDidChange(_ notification: Notification)
	{
		let query = searchField.stringValue
		if tab == .plugins
		{
			pluginsView?.setSearch(query)
			return
		}
		let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		for row in rows
		{
			row.isHidden = !normalized.isEmpty && !searchText(in: row).contains(normalized)
		}
	}

	private func searchText(in view: NSView) -> String
	{
		let ownText = (view as? NSTextField)?.stringValue ?? ""
		return ([ownText] + view.subviews.map(searchText(in:))).joined(separator: " ").lowercased()
	}

	private func loadCatalog()
	{
		run
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			let result = try await backend.perform(
				"plugin/list",
				params: [:]
			)
			catalog = result["marketplaces"] as? [[String: Any]] ?? []
			catalogLoaded = true
			populateCatalogRows()
		}
	}

	private func populateCatalogRows()
	{
		tabCounts[.marketplaces] = userMarketplaces.count
		rows = []
		if tab == .marketplaces
		{
			for marketplace in userMarketplaces
			{
				appendMarketplace(marketplace)
			}
		}
		else
		{
			let plugins = SettingsPluginsCatalogView(marketplaces: catalog)
			{
				[weak self] entry in
				self?.makePluginRow(
					entry.plugin,
					marketplace: entry.marketplace
				)
			}
			pluginsView = plugins
			plugins.setFilter(installedOnly: installedOnly)
			plugins.setSearch(searchField.stringValue)
			tabCounts[.plugins] = plugins.installedCount
			rows.append(plugins)
		}
		cachedRows[tab] = rows
	}

	private var userMarketplaces: [[String: Any]]
	{
		let bundled: Set<String> = [
			"openai-primary-runtime",
			"openai-bundled",
			"openai-curated-remote",
		]
		return catalog.filter
		{
			!bundled.contains($0["name"] as? String ?? "")
		}
	}

	private func makePluginRow(
		_ plugin: [String: Any],
		marketplace: [String: Any]
	) -> NSView?
	{
		guard let id = plugin["id"] as? String, let name = plugin["name"] as? String
		else
		{
			return nil
		}
		let installed = plugin["installed"] as? Bool ?? false
		let policy = plugin["installPolicy"] as? String ?? "NOT_AVAILABLE"
		let blocked = policy == "NOT_AVAILABLE"
			|| plugin["availability"] as? String == "DISABLED_BY_ADMIN"
		let managed = policy == "INSTALLED_BY_DEFAULT"
			&& plugin["installPolicySource"] as? String == "WORKSPACE_SETTING"
		let interstitial = plugin["mustShowInstallationInterstitial"] as? Bool == true
		let policyDetail = blocked ? "Unavailable under your workspace policy."
			: managed ? "Installed by default through your workspace setting."
			: interstitial ? "Complete this plugin’s installation in ChatGPT." : nil

		var accessories: [SettingsCatalogRow.Accessory] = []
		if installed
		{
			accessories.append(.toggle(SettingsCatalogRow.Toggle(
				label: name,
				isOn: plugin["enabled"] as? Bool ?? false,
				enabled: !blocked,
				help: blocked ? policyDetail : nil
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
					await backend
						.write(
							["plugins.\(SettingsManagementPolicy.quotedKey(id)).enabled": enabled]
						)
					reloadAfterOperation()
				}
			}))
			accessories.append(.action(SettingsCatalogRow.Action(
				title: "View \(name)",
				icon: .chevronRight,
				enabled: !blocked,
				help: blocked ? policyDetail : nil
			)
			{
				[weak self] in self?.showPluginDetails(
					id: id,
					name: name,
					plugin: plugin
				)
			}))
		}
		else
		{
			let install = SettingsCatalogRow.Action(
				title: "Install",
				enabled: !blocked && !interstitial,
				help: blocked ? policyDetail : nil
			)
			{
				[weak self] in
				guard let self
				else
				{
					return
				}
				confirm(
					"Install plugin",
					detail: "Install “\(name)” and its tools from this marketplace?"
				)
				{
					[weak self] in
					guard let self
					else
					{
						return
					}
					var params: [String: Any] = [
						"pluginName": name,
						"installAttemptId": UUID().uuidString
					]
					if let path = marketplace["path"] as? String
					{
						params["marketplacePath"] = path
					}
					else
					{
						params["remoteMarketplaceName"] = marketplace["name"]
					}
					mutate(
						"plugin/install",
						params: params
					)
				}
			}
			accessories.append(.action(install))
		}
		let interface = plugin["interface"] as? [String: Any]
		let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
		let logoURL = dark
			? interface?["logoUrlDark"] as? String ?? interface?["logoUrl"] as? String
			: interface?["logoUrl"] as? String
		return SettingsCatalogRow(
			title: interface?["displayName"] as? String ?? name,
			details: [policyDetail ?? interface?["shortDescription"] as? String
				?? marketplace["name"] as? String ?? ""],
			accessories: accessories,
			logoURL: logoURL
		)
	}

	private func showPluginDetails(
		id: String,
		name: String,
		plugin: [String: Any]
	)
	{
		guard let window
		else
		{
			return
		}
		let interface = plugin["interface"] as? [String: Any]
		let confirmation = DesktopNativeConfirmation(
			title: interface?["displayName"] as? String ?? name,
			message: interface?["shortDescription"] as? String ?? "",
			confirmTitle: "Uninstall",
			cancelTitle: "Close"
		)
		confirmation.beginSheet(in: window)
		{
			[weak self] confirmed in
			guard confirmed, let self, self.window === window
			else
			{
				return
			}
			self.confirm(
				"Uninstall plugin",
				detail: "Remove “\(name)” from Codex?"
			)
			{
				[weak self] in
				self?.mutate(
					"plugin/uninstall",
					params: ["pluginId": id]
				)
			}
		}
	}

	private func appendMarketplace(_ marketplace: [String: Any])
	{
		guard let name = marketplace["name"] as? String
		else
		{
			return
		}
		let upgrade = SettingsCatalogRow.Action(title: "Upgrade")
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			mutate(
				"marketplace/upgrade",
				params: ["marketplaceName": name]
			)
		}
		let remove = SettingsCatalogRow.Action(
			title: "Remove \(name)",
			icon: .trash
		)
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			confirm(
				"Remove marketplace",
				detail: "Remove “\(name)” from configured marketplaces?"
			)
			{
				[weak self] in
				guard let self
				else
				{
					return
				}
				mutate(
					"marketplace/remove",
					params: ["marketplaceName": name]
				)
			}
		}
		let count = (marketplace["plugins"] as? [[String: Any]])?.count ?? 0
		rows.append(SettingsCatalogRow(
			title: name,
			details: ["\(count) plugins", marketplace["path"] as? String ?? ""],
			accessories: [.action(upgrade), .action(remove)]
		))
	}

	private func loadSkills()
	{
		run
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			let result = try await backend.perform(
				"skills/list",
				params: [:]
			)
			let userSkillsPath = codexHome.appendingPathComponent("skills")
				.standardizedFileURL.path + "/"
			rows = []
			var skillCount = 0
			for entry in result["data"] as? [[String: Any]] ?? []
			{
				for skill in entry["skills"] as? [[String: Any]] ?? []
				{
					guard let name = skill["name"] as? String,
							let path = skill["path"] as? String
					else
					{
						continue
					}
					let skillPath = URL(fileURLWithPath: path).standardizedFileURL.path
					guard skillPath.hasPrefix(userSkillsPath),
							!skillPath.hasPrefix(userSkillsPath + ".system/")
					else
					{
						continue
					}
					skillCount += 1
					let control = toggle(
						name,
						enabled: skill["enabled"] as? Bool ?? false
					)
					{
						[weak self] enabled in
						guard let self
						else
						{
							return
						}
						mutate(
							"skills/config/write",
							params: ["path": path, "enabled": enabled]
						)
					}
					rows.append(SettingsPageLayout.row(
						title: name,
						detail: skill["description"] as? String,
						control: control
					))
				}
			}
			tabCounts[.skills] = skillCount
			cachedRows[.skills] = rows
		}
	}

	private func loadMCPs()
	{
		let configurations = backend.value("mcp_servers") as? [String: [String: Any]] ?? [:]
		tabCounts[.mcps] = configurations.count
		rows = []
		for name in configurations.keys.sorted()
		{
			appendMCP([
				"name": name,
				"authStatus": configurations[name]?["url"] == nil ? "unknown" : "oAuth",
			])
		}
		cachedRows[.mcps] = rows
		render()
	}

	private func appendMCP(_ server: [String: Any])
	{
		guard let name = server["name"] as? String
		else
		{
			return
		}
		let configs = backend.value("mcp_servers") as? [String: [String: Any]] ?? [:]
		let config = configs[name] ?? [:]
		let enabled = toggle(
			name,
			enabled: config["enabled"] as? Bool ?? true
		)
		{
			[weak self] enabled in
			guard let self
			else
			{
				return
			}
			var all = backend.value("mcp_servers") as? [String: [String: Any]] ?? [:]
			var updated = all[name] ?? [:]
			updated["enabled"] = enabled
			all[name] = updated
			saveMCPs(all)
		}
		let settings = DesktopActionButton(
			icon: .settings,
			label: "Configure \(name)"
		)
		{
			[weak self] in
			self?.showMCPActions(
				name: name,
				configuration: config,
				canAuthenticate: ["notLoggedIn", "oAuth"]
					.contains(server["authStatus"] as? String ?? "")
			)
		}
		let row = SettingsPageLayout.row(
			title: name,
			detail: nil,
			control: controls([settings, enabled])
		)
		row.heightAnchor
			.constraint(greaterThanOrEqualToConstant: LayoutTokens.Settings.mcpRowHeight)
			.isActive = true
		rows.append(row)
	}

	private func showMCPActions(
		name: String,
		configuration: [String: Any],
		canAuthenticate: Bool
	)
	{
		guard let window
		else
		{
			return
		}
		let alert = NSAlert()
		alert.messageText = name
		alert.addButton(withTitle: "Edit")
		alert.addButton(withTitle: "Remove")
		if canAuthenticate
		{
			alert.addButton(withTitle: "Authenticate")
		}
		alert.addButton(withTitle: "Cancel")
		alert.beginSheetModal(for: window)
		{
			[weak self] response in
			guard let self, self.window === window
			else
			{
				return
			}
			switch response
			{
			case .alertFirstButtonReturn:
				self.editMCP(
					name: name,
					configuration: configuration
				)
			case .alertSecondButtonReturn:
				self.removeMCP(name)
			case .alertThirdButtonReturn where canAuthenticate:
				self.authenticateMCP(name)
			default: break
			}
		}
	}

	private func authenticateMCP(_ name: String)
	{
		run
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			let result = try await backend.perform(
				"mcpServer/oauth/login",
				params: ["name": name]
			)
			guard let raw = result["authorizationUrl"] as? String, let url = URL(string: raw),
					["https", "http"].contains(url.scheme?.lowercased() ?? "")
			else
			{
				throw AppServerError.protocolError("Codex returned an invalid authorization URL.")
			}
			NSWorkspace.shared.open(url)
		}
	}

	private func addMCP()
	{
		editMCP(
			name: nil,
			configuration: [:]
		)
	}

	private func editMCP(
		name: String?,
		configuration: [String: Any]
	)
	{
		guard !isOperating
		else
		{
			return
		}
		let form = SettingsMCPForm(
			name: name,
			configuration: configuration
		)
		mcpForm = form
		form.onCancel =
		{
			[weak self] in
			guard let self, !isOperating
			else
			{
				return
			}
			mcpForm = nil
			load()
		}
		form.onSave =
		{
			[weak self] enteredName, config in
			guard let self, !isOperating
			else
			{
				return
			}
			var servers = backend.value("mcp_servers") as? [String: [String: Any]] ?? [:]
			if name == nil, servers[enteredName] != nil
			{
				render()
				return
			}
			servers[enteredName] = config
			saveMCPs(
				servers,
				closeForm: true
			)
		}
		rows = [form]
		render()
	}

	private func saveMCPs(
		_ servers: [String: [String: Any]],
		closeForm: Bool = false
	)
	{
		run
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			guard await backend.write(["mcp_servers": servers])
			else
			{
				return
			}
			_ = try await backend.perform(
				"config/mcpServer/reload",
				params: [:]
			)
			if closeForm
			{
				mcpForm = nil
			}
			reloadAfterOperation()
		}
	}

	private func removeMCP(_ name: String)
	{
		confirm(
			"Remove MCP server",
			detail: "Remove “\(name)” from your MCP configuration?"
		)
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			var servers = backend.value("mcp_servers") as? [String: [String: Any]] ?? [:]
			servers.removeValue(forKey: name)
			saveMCPs(servers)
		}
	}

	private func mutate(
		_ method: String,
		params: [String: Any]
	)
	{
		run
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			_ = try await backend.perform(
				method,
				params: params
			)
			reloadAfterOperation()
		}
	}
}
