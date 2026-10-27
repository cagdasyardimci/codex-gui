import AppKit

/// Realtime defaults are distinct from ChatGPT's account-level voice preference.
@MainActor
final class SettingsVoicePage: NSView
{
	private let backend: SettingsBackend
	private let voice = SettingsChoicePicker(choices: [])
	private var voices: [String] = []
	private var requested = false
	private var loading: Task<Void, Never>?

	init(backend: SettingsBackend)
	{
		self.backend = backend
		super.init(frame: .zero)
		voice.setAccessibilityLabel("Realtime voice")
		voice.onSelect =
		{
			[weak self] selection in
			guard let self
			else
			{
				return
			}
			Task
			{
				await self.backend
					.write(["realtime.voice": selection.isEmpty ? NSNull() : selection])
			}
		}
		let section = SettingsPageLayout.section(
			title: "Realtime",
			rows: [SettingsPageLayout.row(
				title: "Voice",
				detail: "Default voice for Codex realtime sessions.",
				control: voice
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
		voice.isEnabled = backend.isConnected && !backend.isBusy && !voices.isEmpty
		let selected = backend.value("realtime.voice") as? String ?? ""
		let choices = [SettingsChoicePicker.Choice(
			id: "",
			title: "Default"
		)] + voices.map
		{
			SettingsChoicePicker.Choice(
				id: $0,
				title: $0.capitalized
			)
		}
		voice.setChoices(
			choices,
			selectedID: selected
		)
		guard backend.isConnected, !backend.isBusy, !requested, window != nil
		else
		{
			return
		}
		requested = true
		loading = Task
		{
			[weak self] in
			guard let self
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
				guard !Task.isCancelled
				else
				{
					return
				}
				guard let catalog = response["voices"] as? [String: Any]
				else
				{
					throw AppServerError.protocolError("Codex returned an invalid voice catalog.")
				}
				let version = backend.value("realtime.version") as? String ?? "v2"
				voices = catalog[version] as? [String] ?? []
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
			loading?.cancel()
			loading = nil
			requested = false
		}
		else
		{
			refresh()
		}
	}
}
