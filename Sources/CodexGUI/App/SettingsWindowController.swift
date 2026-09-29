import AppKit
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController
{
	private let accountLabel = NSTextField(wrappingLabelWithString: "Checking sign-in…")
	private let backendLabel = NSTextField(wrappingLabelWithString: "Locating Codex…")
	private let editorLabel = NSTextField(labelWithString: "System Default")
	private let notificationLabel = NSTextField(
		wrappingLabelWithString: "Checking notification access…"
	)
	private let editorHandoff = EditorHandoff()
	var onLogin: (() -> Void)?
	var onReconnect: (() -> Void)?
	var onShowBackendDetails: (() -> Void)?

	init()
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 460,
				height: 400
			),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false
		)
		window.title = "Settings"
		window.center()
		super.init(window: window)

		configureStatusLabels()
		updateEditorLabel()

		installSettingsSections(in: window.contentView!)
	}

	private func installSettingsSections(in container: NSView)
	{
		let account = makeAccountSection()
		let backend = makeBackendSection()
		let editor = makeEditorSection()
		let notifications = AppKitLayout.verticalStack(
			[AppKitLayout.title("Notifications"), notificationLabel],
			spacing: 5
		)
		let stack = AppKitLayout.verticalStack(
			[account, backend, editor, notifications],
			spacing: 18
		)
		AppKitLayout.pin(
			stack,
			to: container,
			inset: 20
		)
		for section in [account, backend, editor, notifications]
		{
			section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		accountLabel.widthAnchor.constraint(equalTo: account.widthAnchor).isActive = true
		backendLabel.widthAnchor.constraint(equalTo: backend.widthAnchor).isActive = true
		notificationLabel.widthAnchor.constraint(equalTo: notifications.widthAnchor).isActive = true
	}

	private func configureStatusLabels()
	{
		accountLabel.setAccessibilityLabel("Account status")
		backendLabel.setAccessibilityLabel("Codex backend status")
		editorLabel.setAccessibilityLabel("Preferred editor")
		notificationLabel.setAccessibilityLabel("Notification permission and delivery status")
		accountLabel.textColor = .secondaryLabelColor
		backendLabel.textColor = .secondaryLabelColor
		editorLabel.textColor = .secondaryLabelColor
		notificationLabel.textColor = .secondaryLabelColor
	}

	private func makeAccountSection() -> NSStackView
	{
		let signIn = NSButton(
			title: "Sign In…",
			target: self,
			action: #selector(signIn)
		)

		signIn.setAccessibilityLabel("Sign in to Codex in the browser")

		return AppKitLayout.verticalStack(
			[
				AppKitLayout.title("Account"),
				accountLabel,
				signIn,
			],
			spacing: 5
		)
	}

	private func makeBackendSection() -> NSStackView
	{
		let reconnect = NSButton(
			title: "Reconnect",
			target: self,
			action: #selector(reconnect)
		)
		let details = NSButton(
			title: "Backend Details…",
			target: self,
			action: #selector(showBackendDetails)
		)

		reconnect.setAccessibilityLabel("Reconnect to Codex")
		details.setAccessibilityLabel("Show Codex backend diagnostic details")

		return AppKitLayout.verticalStack(
			[
				AppKitLayout.title("Backend"),
				backendLabel,
				AppKitLayout.horizontalStack([reconnect, details]),
			],
			spacing: 5
		)
	}

	private func makeEditorSection() -> NSStackView
	{
		let chooseEditor = NSButton(
			title: "Choose Editor…",
			target: self,
			action: #selector(selectEditor)
		)
		let defaultEditor = NSButton(
			title: "Use System Default",
			target: self,
			action: #selector(useDefaultEditor)
		)

		chooseEditor.setAccessibilityLabel("Choose preferred editor application")
		defaultEditor.setAccessibilityLabel("Use system default editor")

		return AppKitLayout.verticalStack(
			[
				AppKitLayout.title("Editor"),
				editorLabel,
				AppKitLayout.horizontalStack([chooseEditor, defaultEditor]),
			],
			spacing: 5
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func render(_ snapshot: ConversationSnapshot)
	{
		render(WorkspaceStatusPresentation(snapshot))
	}
	func render(_ snapshot: WorkspaceStatusPresentation)
	{
		accountLabel.stringValue = snapshot.accountDescription
		backendLabel.stringValue = snapshot.backendDescription
		accountLabel.toolTip = snapshot.accountDescription
		backendLabel.toolTip = snapshot.backendDescription
		updateEditorLabel()
	}

	func present()
	{
		showWindow(nil)
		window?.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
	}

	func setNotificationStatus(_ message: String)
	{
		notificationLabel.stringValue = message
		notificationLabel.toolTip = message
	}

	private func updateEditorLabel()
	{
		editorLabel.stringValue =
			editorHandoff.preferredApplication.map
				{
					$0.deletingPathExtension().lastPathComponent
				} ?? "System Default"
	}

	@objc private func signIn()
	{
		onLogin?()
	}
	@objc private func reconnect()
	{
		onReconnect?()
	}
	@objc private func showBackendDetails()
	{
		onShowBackendDetails?()
	}

	@objc private func useDefaultEditor()
	{
		editorHandoff.preferredApplication = nil
		updateEditorLabel()
	}

	@objc private func selectEditor()
	{
		guard let window
		else
		{
			return
		}
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [.applicationBundle]
		panel.canChooseDirectories = false
		panel.canChooseFiles = true
		panel.allowsMultipleSelection = false
		panel.directoryURL = URL(fileURLWithPath: "/Applications")
		panel.prompt = "Choose Editor"
		panel.beginSheetModal(for: window)
		{
			[weak self] response in
			guard response == .OK, let url = panel.url
			else
			{
				return
			}
			self?.editorHandoff.preferredApplication = url
			self?.updateEditorLabel()
		}
	}
}
