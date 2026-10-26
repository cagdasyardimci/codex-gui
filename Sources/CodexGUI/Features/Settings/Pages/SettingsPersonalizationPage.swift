import AppKit

@MainActor
final class SettingsPersonalizationPage: NSView
{
	private let backend: SettingsBackend
	private let memories = RemoteConnectionsSwitch()
	private let external = RemoteConnectionsSwitch()
	private let deleteMemories = RemoteConnectionsButton(
		title: "Delete…",
		presentation: .destructive
	)
	private let instructions = NSTextView()
	private let save = RemoteConnectionsButton(
		title: "Save",
		presentation: .primary
	)
	private let reload = RemoteConnectionsButton(
		title: "Reload",
		presentation: .secondary
	)
	private let instructionStatus = SettingsPageLayout.status("")
	private let actionStatus = SettingsPageLayout.status("")
	private let instructionsURL: URL
	private var loadedInstructions: String?

	init(backend: SettingsBackend)
	{
		self.backend = backend
		let home = ProcessInfo.processInfo.environment["CODEX_HOME"]
		instructionsURL = (home.map
		{
			URL(fileURLWithPath: $0)
		}
		?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"))
			.appendingPathComponent("AGENTS.md")
		super.init(frame: .zero)
		memories.target = self
		memories.action = #selector(changeMemories)
		memories.setAccessibilityLabel("Enable Codex memories")
		external.target = self
		external.action = #selector(changeExternal)
		external.setAccessibilityLabel("Allow memories from tool-assisted chats")
		deleteMemories.target = self
		deleteMemories.action = #selector(confirmDelete)
		let memorySection = SettingsPageLayout.section(
			title: "Memories",
			rows: [
				SettingsPageLayout.row(
					title: "Enable Codex memories",
					detail: "Let Codex create and use memories from your chats.",
					control: memories
				),
				SettingsPageLayout.row(
					title: "Allow memories from tool-assisted chats",
					detail: "Include chats that use external context when creating memories.",
					control: external
				),
				SettingsPageLayout.row(
					title: "Delete Codex memories",
					detail: "Permanently remove saved Codex memories.",
					control: deleteMemories
				),
			]
		)
		instructions.isRichText = false
		instructions.font = .systemFont(ofSize: 13)
		instructions.textContainerInset = NSSize(
			width: 12,
			height: 12
		)
		instructions.isVerticallyResizable = true
		instructions.isHorizontallyResizable = false
		instructions.autoresizingMask = [.width]
		instructions.textContainer?.widthTracksTextView = true
		instructions.setAccessibilityLabel("Codex instructions")
		let editor = NSScrollView()
		editor.hasVerticalScroller = true
		editor.autohidesScrollers = true
		editor.borderType = .bezelBorder
		editor.documentView = instructions
		editor.heightAnchor.constraint(equalToConstant: 220).isActive = true
		save.target = self
		save.action = #selector(saveInstructions)
		reload.target = self
		reload.action = #selector(reloadInstructions)
		let actions = NSStackView(views: [reload, save])
		actions.orientation = .horizontal
		actions.spacing = 8
		let instructionContents = AppKitLayout.verticalStack(
			[
				SettingsPageLayout.message("Instructions that Codex follows in every project."),
				editor,
				instructionStatus,
				actions,
			],
			spacing: 12
		)
		for child in instructionContents.arrangedSubviews where child !== actions
		{
			child.widthAnchor.constraint(equalTo: instructionContents.widthAnchor).isActive = true
		}
		let instructionSection = AppKitLayout.verticalStack(
			[
				RemoteConnectionsLabel(
					"Codex instructions",
					role: TypographyTokens.Connections.section
				),
				instructionContents,
			],
			spacing: 16
		)
		instructionContents.widthAnchor.constraint(equalTo: instructionSection.widthAnchor)
			.isActive = true
		AppKitLayout.pin(
			SettingsPageLayout.document(
				title: "Personalization",
				sections: [memorySection, actionStatus, instructionSection]
			),
			to: self,
			inset: 0
		)
		loadInstructions()
		refresh()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func refresh()
	{
		let enabled = backend.isConnected && !backend.isBusy
		let resolvedFeature = backend.featureEnabled("memories")
		let featureEnabled = resolvedFeature == true
		memories.state = featureEnabled
			&& backend.value("memories.generate_memories") as? Bool != false
			&& backend.value("memories.use_memories") as? Bool != false ? .on : .off
		let requiredFeatures = backend.requirements["featureRequirements"] as? [String: Bool] ?? [:]
		memories.isEnabled = enabled && resolvedFeature != nil
			&& requiredFeatures["memories"] == nil
		memories.toolTip = requiredFeatures["memories"] == nil ? nil
			: "Controlled by organization policy."
		external.state = backend.value("memories.disable_on_external_context") as? Bool != true
			? .on : .off
		external.isEnabled = enabled && memories.state == .on
		deleteMemories.isEnabled = enabled
	}

	@objc private func changeMemories()
	{
		let enabled = memories.state == .on
		refresh()
		Task
		{
			await backend.write([
				"features.memories": enabled,
				"memories.generate_memories": enabled,
				"memories.use_memories": enabled,
			])
		}
	}

	@objc private func changeExternal()
	{
		let disabled = external.state != .on
		refresh()
		Task
		{
			await backend.write(["memories.disable_on_external_context": disabled])
		}
	}

	@objc private func confirmDelete()
	{
		guard let window, backend.isConnected && !backend.isBusy
		else
		{
			return
		}
		let confirmation = DesktopNativeConfirmation(
			title: "Delete Codex memories?",
			message: "This permanently deletes saved Codex memories. Chats are kept.",
			confirmTitle: "Delete Memories",
			emphasis: .warning
		)
		confirmation.beginSheet(in: window)
		{
			[weak self] confirmed in
			guard confirmed, let self,
					self.backend.isConnected && !self.backend.isBusy
			else
			{
				return
			}
			self.deleteMemories.isEnabled = false
			Task
			{
				do
				{
					_ = try await self.backend.perform(
						"memory/reset",
						params: [:]
					)
					self.actionStatus.stringValue = "Codex memories deleted."
				}
				catch
				{
					self.actionStatus.stringValue = error.localizedDescription
				}
				self.refresh()
			}
		}
	}

	private func loadInstructions()
	{
		do
		{
			let text = try currentInstructions()
			save.isEnabled = true
			loadedInstructions = text
			instructions.string = text
			instructionStatus.stringValue = ""
		}
		catch
		{
			instructionStatus.stringValue = "Could not read instructions: "
				+ error.localizedDescription
			save.isEnabled = false
		}
	}

	@objc private func reloadInstructions()
	{
		if instructions.string == loadedInstructions || loadedInstructions == nil
		{
			loadInstructions()
			return
		}
		guard let window
		else
		{
			return
		}
		let confirmation = DesktopNativeConfirmation(
			title: "Discard your instruction changes?",
			message: "Reload replaces this draft with the saved instructions.",
			confirmTitle: "Reload"
		)
		confirmation.beginSheet(in: window)
		{
			[weak self] confirmed in
			if confirmed
			{
				self?.loadInstructions()
			}
		}
	}

	private func currentInstructions() throws -> String
	{
		if !FileManager.default.fileExists(atPath: instructionsURL.path)
		{
			return ""
		}
		return try String(
			contentsOf: instructionsURL,
			encoding: .utf8
		)
	}

	@objc private func saveInstructions()
	{
		guard let loadedInstructions
		else
		{
			return
		}
		do
		{
			guard try currentInstructions() == loadedInstructions
			else
			{
				instructionStatus.stringValue = "Instructions changed outside the app. "
					+ "Use Reload before saving. Your draft is kept."
				return
			}
			try FileManager.default.createDirectory(
				at: instructionsURL.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			try instructions.string.write(
				to: instructionsURL,
				atomically: true,
				encoding: .utf8
			)
			self.loadedInstructions = instructions.string
			instructionStatus.stringValue = "Saved."
		}
		catch
		{
			instructionStatus.stringValue = error.localizedDescription
		}
	}
}
