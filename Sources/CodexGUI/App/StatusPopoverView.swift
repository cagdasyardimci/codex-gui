import AppKit

@MainActor
final class StatusPopoverView: NSView
{
	var onShowSettings: (() -> Void)?
	var onReconnect: (() -> Void)?
	var onShowBackendDetails: (() -> Void)?

	private let taskLabel = NSTextField(labelWithString: "Ready")
	private let accountLabel = NSTextField(wrappingLabelWithString: "Checking sign-in…")
	private let backendLabel = NSTextField(wrappingLabelWithString: "Locating Codex…")
	private let usageSummary = UsageSummaryView()

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		taskLabel.font = .boldSystemFont(ofSize: 13)
		taskLabel.setAccessibilityLabel("Current task status")
		accountLabel.setAccessibilityLabel("Account status")
		backendLabel.setAccessibilityLabel("Codex backend status")
		accountLabel.textColor = .secondaryLabelColor
		backendLabel.textColor = .secondaryLabelColor
		accountLabel.maximumNumberOfLines = 2
		backendLabel.maximumNumberOfLines = 2

		let reconnectButton = NSButton(
			title: "Reconnect",
			target: self,
			action: #selector(reconnect)
		)
		let backendDetailsButton = NSButton(
			title: "Details…",
			target: self,
			action: #selector(showBackendDetails)
		)
		let settingsButton = NSButton(
			title: "Settings…",
			target: self,
			action: #selector(showSettings)
		)
		reconnectButton.setAccessibilityLabel("Reconnect to Codex")
		backendDetailsButton.setAccessibilityLabel("Show Codex backend diagnostic details")
		settingsButton.setAccessibilityLabel("Open Codex GUI settings")

		let actionButtons = AppKitLayout.horizontalStack(
			[reconnectButton, backendDetailsButton, settingsButton],
			spacing: 6
		)
		let stack = AppKitLayout.verticalStack(
			[
				taskLabel,
				accountLabel,
				backendLabel,
				usageSummary,
				actionButtons,
			],
			spacing: 9
		)

		AppKitLayout.pin(
			stack,
			to: self,
			inset: 14
		)
		for control in [accountLabel, backendLabel, usageSummary, actionButtons]
		{
			control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func render(_ snapshot: ConversationSnapshot)
	{
		render(WorkspaceStatusPresentation(snapshot))
	}
	func render(_ presentation: WorkspaceStatusPresentation)
	{
		taskLabel.stringValue = presentation.executionState.title
		accountLabel.stringValue = presentation.accountDescription
		backendLabel.stringValue = presentation.backendDescription
		accountLabel.toolTip = presentation.accountDescription
		backendLabel.toolTip = presentation.backendDescription
		usageSummary.render(presentation.usage)
	}

	@objc private func reconnect()
	{
		onReconnect?()
	}
	@objc private func showBackendDetails()
	{
		onShowBackendDetails?()
	}
	@objc private func showSettings()
	{
		onShowSettings?()
	}
}
