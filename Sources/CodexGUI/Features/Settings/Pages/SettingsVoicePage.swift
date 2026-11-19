import AppKit

/// Realtime defaults are distinct from ChatGPT's account-level voice preference.
@MainActor
final class SettingsVoicePage: NSView
{
	private let backend: SettingsBackend
	let chooseButton = DesktopStyledButton(
		title: "Default",
		presentation: .secondary,
		size: .small
	)
	private(set) var sheet: SettingsVoiceSheet?
	private let playback: ReadAloudRuntime
	private let previewDirectory = FileManager.default.homeDirectoryForCurrentUser
	private var voices: [String]?
	private var defaultPreviewVoice: String?
	private var previewAvailable = false
	private var draftVoice: String?
	private var catalogGeneration: UUID?
	private(set) var loading: Task<Void, Never>?
	private(set) var previewTask: Task<Void, Never>?
	private(set) var saveTask: Task<Void, Never>?

	init(backend: SettingsBackend)
	{
		self.backend = backend
		playback = ReadAloudRuntime(service: backend.server)
		super.init(frame: .zero)
		chooseButton.target = self
		chooseButton.action = #selector(openSheet)
		let section = SettingsPageLayout.section(
			title: "Realtime",
			rows: [SettingsPageLayout.row(
				title: "Voice",
				detail: "Default voice for Codex realtime sessions.",
				control: chooseButton
			)]
		)

		AppKitLayout.pin(
			SettingsPageLayout.document(
				title: "Voice",
				sections: [section]
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
		let generation = backend.isConnected ? backend.server.connectionGeneration : nil
		if catalogGeneration != generation
		{
			retireCatalog()
			catalogGeneration = generation
		}
		renderControls()
		guard let generation, !backend.isBusy, voices == nil, loading == nil,
				window != nil, sheet == nil
		else
		{
			return
		}
		loading = Task
		{
			[weak self] in
			await self?.loadCatalog(generation: generation)
		}
		renderControls()
	}

	private func renderControls()
	{
		let saved = savedVoice
		let canEdit = backend.isConnected && !backend.isBusy && saveTask == nil
		chooseButton.title = Self.choices(for: voices ?? []).first
		{
			$0.id == saved
		}?.title
		?? "Default"
		chooseButton.setAccessibilityLabel("Choose voice, " + chooseButton.title)
		chooseButton.isEnabled = canEdit && sheet == nil && loading == nil
			&& (voices?.isEmpty == false || !saved.isEmpty)
		sheet?.render(
			selection: draftVoice ?? saved,
			canEdit: canEdit,
			isSaving: saveTask != nil
		)
	}

	@objc private func openSheet()
	{
		guard chooseButton.isEnabled, let window, window.attachedSheet == nil
		else
		{
			return
		}
		let sheet = SettingsVoiceSheet(
			choices: Self.choices(for: voices ?? []),
			availableHeight: window.contentView?.bounds.height ?? 600
		)
		self.sheet = sheet
		sheet.onSelect =
		{
			[weak self] id in
			guard let self, saveTask == nil, id.isEmpty || voices?.contains(id) == true
			else
			{
				return
			}
			stopPreview()
			draftVoice = id == savedVoice ? nil : id
			renderControls()
			previewSelection()
		}
		sheet.onDone =
		{
			[weak self] in self?.saveSelection()
		}
		renderControls()
		sheet.beginSheet(in: window)
		{
			[weak self, weak sheet] _ in
			sheet?.orderOut(nil)
			guard let self, self.sheet === sheet
			else
			{
				return
			}
			self.sheet = nil
			draftVoice = nil
			stopPreview()
			renderControls()
		}
	}

	private var savedVoice: String
	{
		backend.value("realtime.voice") as? String ?? ""
	}

	private var previewVoice: String?
	{
		let selection = draftVoice ?? savedVoice
		if selection.isEmpty
		{
			return defaultPreviewVoice
		}
		return voices?.contains(selection) == true ? selection : nil
	}

	private func saveSelection()
	{
		guard sheet != nil, saveTask == nil, backend.isConnected, !backend.isBusy
		else
		{
			return
		}
		stopPreview()
		guard let draftVoice
		else
		{
			sheet?.finishDecision(true)
			return
		}
		saveTask = Task
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			let saved = await backend
				.write(["realtime.voice": draftVoice.isEmpty ? NSNull() : draftVoice])
			guard !Task.isCancelled
			else
			{
				return
			}
			saveTask = nil
			if saved
			{
				self.draftVoice = nil
				sheet?.finishDecision(true)
			}
			renderControls()
		}
		renderControls()
	}

	private func previewSelection()
	{
		guard sheet != nil, previewAvailable, backend.isConnected, !backend.isBusy,
				saveTask == nil, let id = previewVoice
		else
		{
			return
		}
		let sample = Self.voiceGroups.first
		{
			$0.ids.contains(id)
		}?.sample ?? Self.englishSample
		let playback = playback
		let directory = previewDirectory
		previewTask = Task
		{
			[weak self] in
			guard !Task.isCancelled
			else
			{
				return
			}
			try? await playback.play(
				text: sample,
				in: directory,
				voice: id
			)
			{
			}
			guard !Task.isCancelled, let self
			else
			{
				return
			}
			previewTask = nil
		}
	}

	private func stopPreview()
	{
		previewTask?.cancel()
		previewTask = nil
		playback.cancel()
	}

	private func loadCatalog(generation: UUID) async
	{
		// Bound recovery within one refresh. A later Settings refresh can try again.
		for _ in 0 ..< 2
		{
			guard !Task.isCancelled, catalogGeneration == generation
			else
			{
				return
			}
			do
			{
				let response = try await backend.perform(
					"thread/realtime/listVoices",
					params: [:]
				)
				let catalog = try AppServer.realtimeAudioVoices(from: response)
				let defaultVoice = AppServer.realtimeAudioDefault(from: response)
				let canPreview = if catalog.isEmpty
				{
					false
				}
				else
				{
					(try? await backend.server
						.realtimeWebSocketCredentialsAvailable(in: previewDirectory)) == true
				}
				guard !Task.isCancelled, catalogGeneration == generation
				else
				{
					return
				}
				voices = catalog
				defaultPreviewVoice = defaultVoice.flatMap
				{
					catalog.contains($0) ? $0 : nil
				}
				previewAvailable = canPreview
				break
			}
			catch
			{
				continue
			}
		}
		guard !Task.isCancelled, catalogGeneration == generation
		else
		{
			return
		}
		loading = nil
		renderControls()
	}

	private func retireCatalog()
	{
		let retired = sheet
		sheet = nil
		retired?.finishDecision(false)
		stopPreview()
		saveTask?.cancel()
		saveTask = nil
		draftVoice = nil
		loading?.cancel()
		loading = nil
		voices = nil
		defaultPreviewVoice = nil
		previewAvailable = false
		catalogGeneration = nil
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		if window == nil
		{
			retireCatalog()
		}
		else
		{
			refresh()
		}
	}

	static func choices(for voices: [String]) -> [SettingsChoicePicker.Choice]
	{
		let knownVoices = Set(voiceGroups.flatMap
		{
			$0.ids
		})
		let ungrouped = voices.filter
		{
			!knownVoices.contains($0)
		}
		// Unlabelled choices come first so they aren't presented under the preceding heading.
		return [.init(
			id: "",
			title: "Default"
		)] + ungrouped.map
		{
			.init(
				id: $0,
				title: $0.capitalized
			)
		} + voiceGroups.flatMap
		{
			group in group.ids.filter(voices.contains).map
			{
				.init(
					id: $0,
					title: $0 == "rindo" ? "Rindō" : $0.capitalized,
					section: group.title
				)
			}
		}
	}

	private static let englishSample = "Hello! Here’s a short sample of this voice."
	private static let voiceGroups: [(title: String, ids: [String], sample: String)] = [
		(
			"American English",
			["bubbie", "juniper", "spruce", "maple", "sol", "breeze", "cove", "ember"],
			englishSample
		),
		("Brazilian Portuguese", ["rio", "viola"], "Olá! Aqui vai uma pequena amostra desta voz."),
		("British English", ["arbor", "vale"], englishSample),
		("French", ["rivage", "aube"], "Bonjour ! Voici un court extrait de cette voix."),
		("German", ["miko", "sonna"], "Hallo! Hier ist eine kurze Hörprobe dieser Stimme."),
		("Hindi", ["neer", "leher"], "नमस्ते! यह इस आवाज़ की एक छोटी सी झलक है।"),
		("Japanese", ["rindo", "himari"], "こんにちは。この声の短いサンプルをお聞きください。"),
		("Korean", ["hanul", "haetsal"], "안녕하세요! 이 목소리의 짧은 예시를 들려드릴게요."),
		("Mexican Spanish", ["tinta"], "¡Hola! Aquí tienes una breve muestra de esta voz."),
	]
}
