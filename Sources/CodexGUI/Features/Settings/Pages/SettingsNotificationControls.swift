import AppKit
import UniformTypeIdentifiers

/// Shared notification controls for General and the dedicated Notifications page.
@MainActor
final class SettingsNotificationControls: NSView
{
	var onRequestAuthorization: (() -> Void)?
	var onRefreshAuthorization: (() -> Void)?
	private let preferences: TaskNotificationPreferences
	private let soundLibrary: TaskNotificationSoundLibrary
	private var authorization = TaskNotificationAuthorization.checking
	private var soundTask: Task<Void, Never>?
	private var preview: NSSound?
	private let completion = SettingsChoicePicker(choices: [
		TaskNotificationPreferences.CompletionMode.never,
		.whenUnfocused,
		.always,
	].map
	{
		.init(
			id: $0.rawValue,
			title: $0.title
		)
	})
	private let permission = RemoteConnectionsSwitch()
	private let question = RemoteConnectionsSwitch()
	private let sound = SettingsChoicePicker(choices: [])
	private let authorizationButton = SettingsNotificationAuthorizationButton(
		title: "Open System Settings",
		presentation: .secondary
	)
	private var authorizationRow: SettingsControlRow!

	init(
		preferences: TaskNotificationPreferences = TaskNotificationPreferences(),
		soundLibrary: TaskNotificationSoundLibrary = TaskNotificationSoundLibrary()
	)
	{
		self.preferences = preferences
		self.soundLibrary = soundLibrary
		super.init(frame: .zero)
		completion.onSelect =
		{
			[weak self] id in
			guard let self, authorization.allowsConfiguration,
					let mode = TaskNotificationPreferences.CompletionMode(rawValue: id)
			else
			{
				return
			}
			preferences.completionMode = mode
			refreshPreferences()
		}
		sound.onSelect =
		{
			[weak self] id in self?.selectSound(id)
		}
		completion.setAccessibilityLabel("Turn completion notifications")
		sound.setAccessibilityLabel("Notification sound")
		sound.toolTip = "Classic uses the macOS Sosumi alert sound."
		for toggle in [permission, question]
		{
			toggle.target = self
			toggle.action = #selector(preferencesChanged(_:))
		}
		permission.setAccessibilityLabel("Enable permission notifications")
		question.setAccessibilityLabel("Enable question notifications")
		authorizationButton.target = self
		authorizationButton.action = #selector(openAuthorizationSettings)
		authorizationRow = SettingsPageLayout.row(
			title: "",
			detail: "",
			control: authorizationButton
		)
		let rows = [
			authorizationRow!,
			SettingsPageLayout.row(
				title: "Turn completion notifications",
				detail: "Set when Codex alerts you that it's finished",
				control: completion
			),
			SettingsPageLayout.row(
				title: "Enable permission notifications",
				detail: "Show alerts when permissions are required",
				control: permission
			),
			SettingsPageLayout.row(
				title: "Enable question notifications",
				detail: "Show alerts when input is needed to continue",
				control: question
			),
			SettingsPageLayout.row(
				title: "Notification sound",
				detail: "Sound for task completion, permission requests, and questions",
				control: sound
			),
		]
		AppKitLayout.pin(
			SettingsPageLayout.card(rows: rows),
			to: self,
			inset: 0
		)
		refreshPreferences()
		setAuthorization(.checking)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func setNotificationStatus(_ message: String)
	{
		_ = message
	}

	func setAuthorization(_ state: TaskNotificationAuthorization)
	{
		authorization = state
		authorizationRow
			.isHidden = state == .authorized || state == .checking || state == .unavailable
		for control in [completion, permission, question, sound]
		{
			control.isEnabled = state.allowsConfiguration
		}
		authorizationButton.title = state == .notDetermined
			? "Allow Notifications" : "Open System Settings"
		authorizationButton.setAccessibilityLabel(authorizationButton.title)
		authorizationButton.isEnabled = state == .denied || state == .notDetermined
		switch state
		{
		case .denied:
			authorizationRow.setTitle("Notifications are off")
			authorizationRow.setDetail(
				"Turn on notifications in System Settings to use the options below"
			)
		case .notDetermined:
			authorizationRow.setTitle("Allow notifications")
			authorizationRow.setDetail("Allow Codex to send notifications "
				+ "to use the options below")
		case .checking:
			authorizationRow.setTitle("")
			authorizationRow.setDetail("")
		case .unavailable:
			authorizationRow.setTitle("")
			authorizationRow.setDetail("")
		case .authorized: break
		}
		if !state.allowsConfiguration
		{
			soundTask?.cancel()
			preview?.stop()
		}
	}

	func refreshPreferences()
	{
		completion.select(id: preferences.completionMode.rawValue)
		permission.state = preferences.permissionAlerts ? .on : .off
		question.state = preferences.questionAlerts ? .on : .off
		var choices = TaskNotificationSound.allCases.filter
		{
			$0 != .custom
		}.map
		{
			SettingsChoicePicker.Choice(
				id: $0.rawValue,
				title: $0.title
			)
		}
		if preferences.customSoundFilename != nil
		{
			choices.append(.init(
				id: "custom",
				title: "Custom sound"
			))
		}
		choices.append(.init(
			id: "choose-custom",
			title: "Choose custom sound…"
		))
		sound.setChoices(
			choices,
			selectedID: preferences.sound.rawValue
		)
	}

	@objc private func preferencesChanged(_ sender: NSControl)
	{
		guard authorization.allowsConfiguration
		else
		{
			refreshPreferences(); return
		}
		if sender === permission
		{
			preferences.permissionAlerts = permission.state == .on
		}
		else if sender === question
		{
			preferences.questionAlerts = question.state == .on
		}
	}

	@objc private func openAuthorizationSettings()
	{
		if authorization == .notDetermined
		{
			onRequestAuthorization?(); return
		}
		guard let url =
			URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
		else
		{
			return
		}
		NSWorkspace.shared.open(url)
	}

	private func selectSound(_ id: String)
	{
		guard authorization.allowsConfiguration
		else
		{
			return
		}
		if id == "choose-custom"
		{
			chooseCustomSound(); return
		}
		guard let selection = TaskNotificationSound(rawValue: id)
		else
		{
			return
		}
		if selection == .custom
		{
			guard soundLibrary.fileURL(
				for: selection,
				customFilename: preferences.customSoundFilename
			) != nil
			else
			{
				return
			}
			soundTask?.cancel()
			preferences.sound = .custom
			refreshPreferences()
			return
		}
		prepareSound(selection)
	}

	private func chooseCustomSound()
	{
		guard let window
		else
		{
			return
		}
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [UTType.wav, .aiff, .init(filenameExtension: "caf")!]
		panel.canChooseDirectories = false
		panel.allowsMultipleSelection = false
		panel.prompt = "Choose Sound"
		panel.message = "Choose a WAV, AIFF, or CAF sound shorter than 30 seconds."
		panel.beginSheetModal(for: window)
		{
			[weak self] response in
			guard response == .OK, let self, self.window === window,
					authorization.allowsConfiguration, let url = panel.url
			else
			{
				return
			}
			prepareSound(
				.custom,
				file: url
			)
		}
	}

	private func prepareSound(
		_ selection: TaskNotificationSound,
		file: URL? = nil
	)
	{
		soundTask?.cancel()
		preview?.stop()
		soundTask = Task
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			do
			{
				let filename = try await soundLibrary.prepare(
					selection,
					customFile: file
				)
				guard !Task.isCancelled, authorization.allowsConfiguration
				else
				{
					return
				}
				if selection == .custom
				{
					preferences.customSoundFilename = filename
				}
				preferences.sound = selection
				refreshPreferences()
				if let url = soundLibrary.fileURL(
					for: selection,
					customFilename: preferences.customSoundFilename
				)
				{
					preview = NSSound(
						contentsOf: url,
						byReference: true
					)
					preview?.play()
				}
			}
			catch
			{
				guard !Task.isCancelled
				else
				{
					return
				}
				refreshPreferences()
				guard let window
				else
				{
					return
				}
				let alert = NSAlert()
				alert.messageText = "Could not use notification sound"
				alert.informativeText = error.localizedDescription
				_ = await alert.beginSheetModal(for: window)
			}
		}
	}
}

@MainActor
private final class SettingsNotificationAuthorizationButton: RemoteConnectionsButton
{
	override func draw(_ dirtyRect: NSRect)
	{
		super.draw(dirtyRect)
		AppKitColorTokens.settingsSelectorEdge.setStroke()
		let edge = AppKitShapePath.roundedRect(
			bounds.insetBy(
				dx: 0.5,
				dy: 0.5
			),
			radius: 12.5,
			curve: ShapeTokens.Connections.curve
		)
		edge.lineWidth = 1
		edge.stroke()
	}

	override var intrinsicContentSize: NSSize
	{
		var size = super.intrinsicContentSize
		size.height = 28
		return size
	}
}
