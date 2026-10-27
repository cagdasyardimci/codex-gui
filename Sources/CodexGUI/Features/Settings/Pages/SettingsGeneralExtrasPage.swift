import AppKit

/// Server-backed preferences embedded in the General reading column.
@MainActor
final class SettingsGeneralExtrasPage: NSView
{
	private let backend: SettingsBackend
	private let speed = SettingsChoicePicker(choices: [])
	private var tiers: [SettingsChoicePicker.Choice] = []
	private var catalogRequested = false
	private var catalogTask: Task<Void, Never>?

	private let compression = RemoteConnectionsSwitch()

	init(backend: SettingsBackend)
	{
		self.backend = backend
		super.init(frame: .zero)
		speed.setAccessibilityLabel("Speed")
		speed.onSelect =
		{
			[weak self] value in
			guard let self
			else
			{
				return
			}
			Task
			{
				await self.backend.write(["service_tier": value])
			}
		}
		compression.setAccessibilityLabel("Compress local chat history")
		compression.target = self
		compression.action = #selector(changeCompression)
		let section = SettingsPageLayout.section(
			title: "Codex",
			rows: [
				SettingsPageLayout.row(
					title: "Speed",
					detail: "Response speed for new chats.",
					control: speed
				),
				SettingsPageLayout.row(
					title: "Compress local chat history",
					detail: "Reduce the disk space used by local chats. Restart Codex to apply.",
					control: compression
				),
			]
		)
		AppKitLayout.pin(
			section,
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
		let current = backend.value("service_tier") as? String ?? "default"
		var choices: [SettingsChoicePicker.Choice] = [.init(
			id: "default",
			title: "Standard"
		)]
		choices += tiers.filter
		{
			$0.id != "default"
		}

		if !choices.contains(where:
			{
				$0.id == current
			})
		{
			choices.append(.init(
				id: current,
				title: current
			))
		}
		speed.setChoices(
			choices,
			selectedID: current
		)
		speed.isEnabled = enabled
		let resolvedCompression = backend.featureEnabled("local_thread_store_compression")
		compression.state = resolvedCompression.map
		{
			$0 ? .on : .off
		} ?? .mixed
		let requiredFeatures = backend.requirements["featureRequirements"] as? [String: Bool] ?? [:]
		compression.isEnabled = enabled && resolvedCompression != nil
			&& requiredFeatures["local_thread_store_compression"] == nil
		compression.toolTip = requiredFeatures["local_thread_store_compression"] == nil ? nil
			: "Controlled by organization policy."
		if !backend.isConnected
		{
			catalogRequested = false
		}
		if enabled && !catalogRequested && window != nil
		{
			loadTiers()
		}
	}

	private func loadTiers()
	{
		catalogRequested = true
		catalogTask = Task
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			do
			{
				var models: [ModelOption] = []
				var cursor: String?
				var seen = Set<String>()
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
					models += (result["data"] as? [[String: Any]] ?? [])
						.compactMap(ModelOption.init(json:))
					cursor = result["nextCursor"] as? String
					if let cursor, !seen.insert(cursor).inserted
					{
						throw AppServerError.protocolError("Codex repeated the model cursor.")
					}
				}
				while cursor != nil
				guard !Task.isCancelled
				else
				{
					return
				}
				let configured = backend.value("model") as? String
				let model = models.first
				{
					$0.id == configured
				} ?? models.first
				{
					$0.isDefault
				}
				tiers = (model?.serviceTiers ?? []).map
				{
					.init(
						id: $0.id,
						title: $0.name,
						detail: $0.description
					)
				}
				speed.toolTip = model.map
				{
					"Service tiers available for \($0.displayName)."
				}
				refresh()
			}
			catch
			{
				guard !Task.isCancelled
				else
				{
					return
				}
			}
		}
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		if window == nil
		{
			catalogTask?.cancel()
			catalogTask = nil
			catalogRequested = false
		}
		else
		{
			refresh()
		}
	}

	@objc private func changeCompression()
	{
		let value = compression.state == .on
		refresh()
		Task
		{
			await backend.write(["features.local_thread_store_compression": value])
		}
	}
}
