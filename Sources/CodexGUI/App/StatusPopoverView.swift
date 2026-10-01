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
	private let contextLabel = NSTextField(wrappingLabelWithString: "")

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		configureStatusLabels()

		let actionButtons = makeActionButtons()

		installStatusContent(actionButtons: actionButtons)
	}

	private func configureStatusLabels()
	{
		taskLabel.font = .boldSystemFont(ofSize: 13)
		taskLabel.setAccessibilityLabel("Current task status")
		accountLabel.setAccessibilityLabel("Account status")
		backendLabel.setAccessibilityLabel("Codex backend status")
		accountLabel.textColor = .secondaryLabelColor
		backendLabel.textColor = .secondaryLabelColor
		accountLabel.maximumNumberOfLines = 2
		backendLabel.maximumNumberOfLines = 2
		contextLabel.font = .systemFont(ofSize: 12)
		contextLabel.textColor = .secondaryLabelColor
		contextLabel.setAccessibilityLabel("Selected conversation status and token usage")
	}

	private func makeActionButtons() -> NSStackView
	{
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
		return actionButtons
	}

	private func installStatusContent(actionButtons: NSStackView)
	{
		let stack = AppKitLayout.verticalStack(
			[
				taskLabel,
				accountLabel,
				backendLabel,
				contextLabel,
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
		for control in [accountLabel, backendLabel, contextLabel, usageSummary, actionButtons]
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
		contextLabel.stringValue = Self.conversationDetails(presentation)
		contextLabel.toolTip = contextLabel.stringValue
		usageSummary.render(presentation.usage)
	}

	static func conversationDetails(_ presentation: WorkspaceStatusPresentation) -> String
	{
		var lines: [String] = []
		if let status = presentation.threadStatus
		{
			let statusTitles = ["active": "Active",
								"idle": "Idle",
								"notLoaded": "Not loaded",
								"systemError": "System error"]
			let flagTitles = ["waitingOnApproval": "waiting for approval",
								"waitingOnUserInput": "waiting for input"]
			let activeFlags = status.activeFlags.map
			{
				flagTitles[$0] ?? $0
			}
			.joined(separator: ", ")
			let flags = activeFlags.isEmpty ? "" : " (\(activeFlags))"
			let title = statusTitles[status.type] ?? status.type
			lines.append("Conversation status: \(title)\(flags)")
		}
		else
		{
			lines.append("Conversation status: unavailable")
		}
		if let usage = presentation.threadTokenUsage
		{
			lines.append("Last request input: \(usage.last.inputTokens) tokens "
				+ "(\(usage.last.cachedInputTokens) cached)")
			if let window = usage.modelContextWindow, window > 0
			{
				lines.append("Model context window: \(window) tokens")
			}
			else
			{
				lines.append("Model context window: unavailable")
			}
			lines.append("Conversation total usage: \(usage.total.totalTokens) tokens")
		}
		else
		{
			lines.append("Last request input: unavailable")
			lines.append("Model context window: unavailable")
			lines.append("Conversation total usage: unavailable")
		}
		lines.append("Current context occupancy: not reported")
		return lines.joined(separator: "\n")
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
