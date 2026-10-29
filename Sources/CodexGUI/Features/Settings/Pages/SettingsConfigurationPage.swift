import AppKit

@MainActor
final class SettingsConfigurationPage: NSView
{
	private let backend: SettingsBackend
	private let effortVisibility: ReasoningEffortVisibility
	private var choices: [String: SettingsChoicePicker] = [:]
	private let network = RemoteConnectionsSwitch()
	private let dependencies = RemoteConnectionsSwitch()
	private var networkRow: NSView!
	private let featureContents = NSStackView()
	private var featureSwitches: [String: RemoteConnectionsSwitch] = [:]
	private var loadedFeatures = false
	private var loadingFeatures = false
	private let effortContents = NSStackView()
	private let effortPicker = SettingsChoicePicker(choices: [])
	private var advertisedEfforts: [String] = []
	private var loadedEfforts = false
	private var loadingEfforts = false
	private(set) var effortLoading: Task<Void, Never>?

	init(
		backend: SettingsBackend,
		effortVisibility: ReasoningEffortVisibility = ReasoningEffortVisibility()
	)
	{
		self.backend = backend
		self.effortVisibility = effortVisibility
		super.init(frame: .zero)
		let approval = choice(
			"approval_policy",
			title: "Approval policy",
			values: [("on-request", "On request"), ("never", "Never")]
		)
		let sandbox = choice(
			"sandbox_mode",
			title: "Sandbox settings",
			values: [
				("read-only", "Read only"),
				("workspace-write", "Workspace write"),
				("danger-full-access", "Full access")
			]
		)
		configure(
			network,
			label: "Network access",
			action: #selector(changeNetwork)
		)
		configure(
			dependencies,
			label: "Codex dependencies",
			action: #selector(changeDependencies)
		)
		networkRow = SettingsPageLayout.row(
			title: "Network access",
			detail: "Allow commands in the workspace sandbox to access the network.",
			control: network
		)
		let permissions = SettingsPageLayout.section(
			title: "Permissions",
			rows: [
				SettingsPageLayout.row(
					title: "Approval policy",
					detail: "When Codex asks before running commands.",
					control: approval
				),
				SettingsPageLayout.row(
					title: "Sandbox settings",
					detail: "File and command access for new chats.",
					control: sandbox
				),
				networkRow,
			]
		)
		let search = choice(
			"web_search",
			title: "Web search",
			values: [
				("disabled", "Disabled"),
				("cached", "Cached"),
				("indexed", "Indexed"),
				(
					"live",
					"Live"
				),
			]
		)
		let verbosity = choice(
			"model_verbosity",
			title: "Output detail",
			values: [
				("", "Default"),
				("low", "Low"),
				("medium", "Medium"),
				("high", "High"),
			]
		)
		let summary = choice(
			"model_reasoning_summary",
			title: "Reasoning summary",
			values: [
				("", "Default"),
				("auto", "Auto"),
				("concise", "Concise"),
				("detailed", "Detailed"),
				("none", "None"),
			]
		)
		let behavior = SettingsPageLayout.section(
			title: "Behavior",
			rows: [
				SettingsPageLayout.row(
					title: "Web search",
					detail: "Which web results Codex can use.",
					control: search
				),
				SettingsPageLayout.row(
					title: "Output detail",
					detail: "How much detail responses include.",
					control: verbosity
				),
				SettingsPageLayout.row(
					title: "Reasoning summary",
					detail: "The summary shown while Codex reasons.",
					control: summary
				),
			]
		)
		effortPicker.menuWidth = 240
		effortPicker.usesCheckboxesForMultipleSelection = false
		effortPicker.setAccessibilityLabel("Available reasoning efforts")
		effortPicker.onToggle =
		{
			[weak self] effort, visible in
			guard let self, !ReasoningEffortVisibility.requiredVisibleEfforts.contains(effort)
			else
			{
				return
			}
			self.effortVisibility.setVisible(
				visible,
				effort: effort
			)
			self.updateEffortSelection()
		}
		effortContents.orientation = .vertical
		effortContents.alignment = .leading
		effortContents.spacing = 0
		let effortSection = SettingsPageLayout.section(
			title: "Model features",
			rows: [effortContents]
		)
		featureContents.orientation = .vertical
		featureContents.alignment = .leading
		featureContents.spacing = 0
		let tools = SettingsPageLayout.section(
			title: "Tools",
			rows: [
				SettingsPageLayout.row(
					title: "Codex dependencies",
					detail: "Allow Codex to use workspace dependencies.",
					control: dependencies
				),
			]
		)
		let experiments = SettingsPageLayout.section(
			title: "Experimental features",
			rows: [featureContents]
		)
		AppKitLayout.pin(
			SettingsPageLayout.document(
				title: "Configuration",
				sections: [permissions, behavior, effortSection, tools, experiments]
			),
			to: self,
			inset: 0
		)
		refresh()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func refresh()
	{
		let enabled = backend.isConnected && !backend.isBusy
		for (key, picker) in choices
		{
			var options = pickerChoices[key] ?? []
			let policyKey = ["approval_policy": "allowedApprovalPolicies",
								"sandbox_mode": "allowedSandboxModes",
								"web_search": "allowedWebSearchModes"][key]
			if let policyKey, let allowed = backend.requirements[policyKey] as? [Any]
			{
				let allowedStrings = allowed.compactMap
				{
					$0 as? String
				}
				options = options.filter
				{
					allowedStrings.contains($0.id)
				}
			}
			picker.toolTip = nil
			let raw = backend.value(key)
			let value = raw as? String ?? (raw is [String: Any] ? "__custom" : "")
			if !options.contains(where:
				{
					$0.id == value
				})
			{
				options.append(.init(
					id: value,
					title: value == "__custom" ? "Custom policy" : "Default"
				))
			}
			picker.setChoices(
				options,
				selectedID: value
			)
			let customApproval = backend.value("approval_policy") is [String: Any]
			let sandboxBlocked = key == "sandbox_mode" && customApproval
			picker.isEnabled = enabled && options.count > 1 && !sandboxBlocked
		}
		network.state = (backend.value("sandbox_workspace_write.network_access") as? Bool == true)
			? .on : .off
		let customApproval = backend.value("approval_policy") is [String: Any]
		network.isEnabled = enabled && !customApproval
		network.toolTip = nil
		networkRow.isHidden = backend.value("sandbox_mode") as? String != "workspace-write"
		let resolvedDependencies = backend.featureEnabled("workspace_dependencies")
		dependencies.state = resolvedDependencies.map
		{
			$0 ? .on : .off
		} ?? .mixed
		let requiredFeatures = backend.requirements["featureRequirements"] as? [String: Bool] ?? [:]
		dependencies.isEnabled = enabled && resolvedDependencies != nil
			&& requiredFeatures["workspace_dependencies"] == nil
		dependencies.toolTip = nil
		for (key, toggle) in featureSwitches
		{
			if let value = backend.featureEnabled(key)
			{
				toggle.state = value ? .on : .off
			}
			toggle.isEnabled = enabled && requiredFeatures[key] == nil
			toggle.toolTip = nil
		}
		updateEffortSelection()
		if backend.isConnected && !backend.isBusy && !loadedEfforts && !loadingEfforts
		{
			loadEfforts()
		}
		if backend.isConnected && !backend.isBusy && !loadedFeatures && !loadingFeatures
		{
			loadFeatures()
		}
	}

	private var pickerChoices: [String: [SettingsChoicePicker.Choice]] = [:]

	private func choice(
		_ key: String,
		title: String,
		values: [(String, String)]
	) -> SettingsChoicePicker
	{
		let options = values.map
		{
			SettingsChoicePicker.Choice(
				id: $0.0,
				title: $0.1,
				detail: Self.choiceDetail(
					key: key,
					value: $0.0
				)
			)
		}
		let picker = SettingsChoicePicker(choices: options)
		picker.menuWidth = 360
		pickerChoices[key] = options
		choices[key] = picker
		picker.setAccessibilityLabel(title)
		picker.onSelect =
		{
			[weak self] selected in
			guard let self, selected != "__custom"
			else
			{
				return
			}
			let value: Any = selected.isEmpty ? NSNull() : selected
			Task
			{
				await self.backend.write([key: value])
			}
		}
		return picker
	}

	private static func choiceDetail(
		key: String,
		value: String
	) -> String?
	{
		switch (key, value)
		{
		case ("approval_policy", "on-request"): "Ask when additional permission is needed."
		case ("approval_policy", "never"): "Never ask for command approval."
		case ("sandbox_mode", "read-only"): "Read files without allowing changes."
		case ("sandbox_mode", "workspace-write"): "Allow changes inside the workspace."
		case ("sandbox_mode", "danger-full-access"): "Allow unrestricted file and command access."
		case ("web_search", "disabled"): "Turn off web search."
		case ("web_search", "cached"): "Use previously indexed web results."
		case ("web_search", "indexed"): "Search indexed web content."
		case ("web_search", "live"): "Request current results from the web."
		default: nil
		}
	}

	private func configure(
		_ toggle: RemoteConnectionsSwitch,
		label: String,
		action: Selector
	)
	{
		toggle.setAccessibilityLabel(label)
		toggle.target = self
		toggle.action = action
	}

	@objc private func changeNetwork()
	{
		let value = network.state == .on
		refresh()
		Task
		{
			await backend.write(["sandbox_workspace_write.network_access": value])
		}
	}

	@objc private func changeDependencies()
	{
		let value = dependencies.state == .on
		refresh()
		Task
		{
			await backend.write(["features.workspace_dependencies": value])
		}
	}

	@objc private func changeFeature(_ sender: NSButton)
	{
		guard let key = sender.identifier?.rawValue
		else
		{
			return
		}
		let value = sender.state == .on
		refresh()
		Task
		{
			await backend.write(["features.\(key)": value])
		}
	}

	private func updateEffortSelection()
	{
		let checked = Set(advertisedEfforts.filter
		{
			effortVisibility.isVisible($0)
		})
		effortPicker.setMultipleChoices(
			advertisedEfforts.map
			{
				SettingsChoicePicker.Choice(
					id: $0,
					title: ModelPreferencePresentation.effortTitle($0),
					isEnabled: !ReasoningEffortVisibility.requiredVisibleEfforts.contains($0)
				)
			},
			checkedIDs: checked,
			title: "\(checked.count) selected"
		)
		effortPicker.isEnabled = !advertisedEfforts.isEmpty
	}

	private func loadEfforts()
	{
		loadingEfforts = true
		effortLoading = Task
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			defer
			{
				self.loadingEfforts = false
				self.effortLoading = nil
			}
			do
			{
				var efforts: [String] = []
				var seenEfforts = Set<String>()
				var cursors = Set<String>()
				var cursor: String?
				repeat
				{
					var params: [String: Any] = ["limit": 100]
					if let cursor
					{
						params["cursor"] = cursor
					}
					let result = try await backend.perform(
						"model/list",
						params: params
					)
					guard let models = result["data"] as? [[String: Any]]
					else
					{
						throw AppServerError.protocolError("Invalid model list.")
					}
					for model in models
					{
						guard let advertised =
							model["supportedReasoningEfforts"] as? [[String: Any]]
						else
						{
							continue
						}
						for option in advertised
						{
							if let effort = option["reasoningEffort"] as? String, !effort.isEmpty,
								seenEfforts.insert(effort).inserted
							{
								efforts.append(effort)
							}
						}
					}
					cursor = result["nextCursor"] as? String
					if let cursor, !cursors.insert(cursor).inserted
					{
						throw AppServerError.protocolError("Repeated model list cursor.")
					}
				}
				while cursor != nil
				for view in effortContents.arrangedSubviews
				{
					effortContents.removeArrangedSubview(view)
					view.removeFromSuperview()
				}
				let order = ["low", "medium", "high", "xhigh", "max", "ultra"]
				advertisedEfforts = efforts.sorted
				{
					let left = order.firstIndex(of: $0) ?? order.count
					let right = order.firstIndex(of: $1) ?? order.count
					return left == right ? $0 < $1 : left < right
				}
				let row = SettingsPageLayout.row(
					title: "Available reasoning efforts",
					detail: "Choose which reasoning effort levels appear in model controls.",
					control: effortPicker
				)
				effortContents.addArrangedSubview(row)
				row.widthAnchor.constraint(equalTo: effortContents.widthAnchor).isActive = true
				loadedEfforts = true
				refresh()
			}
			catch
			{
			}
		}
	}

	private func loadFeatures()
	{
		loadingFeatures = true
		Task
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			defer
			{
				self.loadingFeatures = false
			}
			do
			{
				var rows: [[String: Any]] = []
				var cursor: String?
				var cursors = Set<String>()
				repeat
				{
					var params: [String: Any] = ["limit": 100]
					if let cursor
					{
						params["cursor"] = cursor
					}
					let result = try await backend.perform(
						"experimentalFeature/list",
						params: params
					)
					guard let data = result["data"] as? [[String: Any]]
					else
					{
						throw AppServerError.protocolError("Invalid experimental feature list.")
					}
					rows += data
					cursor = result["nextCursor"] as? String
					if let cursor, !cursors.insert(cursor).inserted
					{
						throw AppServerError.protocolError("Repeated experimental feature cursor.")
					}
				}
				while cursor != nil
				for view in featureContents.arrangedSubviews
				{
					featureContents.removeArrangedSubview(view)
					view.removeFromSuperview()
				}
				for feature in rows
				{
					guard let key = feature["name"] as? String,
							let title = feature["displayName"] as? String, !title.isEmpty,
							feature["stage"] as? String == "beta"
					else
					{
						continue
					}
					let toggle = RemoteConnectionsSwitch()
					configure(
						toggle,
						label: title,
						action: #selector(changeFeature(_:))
					)
					toggle.identifier = NSUserInterfaceItemIdentifier(key)
					toggle.state = feature["enabled"] as? Bool == true ? .on : .off
					featureSwitches[key] = toggle
					let row = SettingsPageLayout.row(
						title: title,
						detail: feature["description"] as? String,
						control: toggle
					)
					featureContents.addArrangedSubview(row)
					row.widthAnchor.constraint(equalTo: featureContents.widthAnchor).isActive = true
				}
				if featureSwitches.isEmpty
				{
				}
				loadedFeatures = true
				refresh()
			}
			catch
			{
			}
		}
	}
}
