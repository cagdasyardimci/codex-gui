import AppKit

/// Compact account menu. Backend diagnostics remain in Settings.
@MainActor
final class StatusPopoverView: NSView
{
	var onShowUsage: (() -> Void)?
	var onShowSettings: (() -> Void)?
	var onReconnect: (() -> Void)?
	var onShowBackendDetails: (() -> Void)?
	var onLogout: (() -> Void)?

	private typealias Layout = LayoutTokens.AccountMenu
	private let accountLabel = NSTextField(labelWithString: "Checking sign-in…")
	private let planLabel = NSTextField(labelWithString: "")
	private let avatar = AccountAvatarText.Label(labelWithString: "")
	private let usageRow = AccountMenuRow(
		title: "Usage",
		icon: .speedometerLatencySpeed
	)
	private let settingsRow = AccountMenuRow(
		title: "Settings",
		icon: .settings
	)
	private let logoutRow = AccountMenuRow(
		title: "Log out",
		icon: .logout
	)
	var onHoverRow: ((Int) -> Void)?
	var menuButtons: [NSButton]
	{
		[usageRow, settingsRow, logoutRow]
	}

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		accountLabel.font = AppKitFontResolver.font(TypographyTokens.AccountMenu.row)
		accountLabel.lineBreakMode = .byTruncatingTail
		accountLabel.setAccessibilityLabel("Account identity")
		planLabel.font = AppKitFontResolver.font(TypographyTokens.AccountMenu.subtitle)
		planLabel.textColor = .tertiaryLabelColor
		planLabel.setAccessibilityLabel("Account plan")
		avatar.font = .systemFont(ofSize: 7)
		avatar.alignment = .center
		avatar.textColor = .white
		avatar.wantsLayer = true
		avatar.layer?.backgroundColor = AppKitColorTokens.accountAvatar.cgColor
		avatar.layer?.cornerRadius = 9
		let identity = AppKitLayout.verticalStack(
			[accountLabel, planLabel],
			spacing: 0
		)
		let profile = AppKitLayout.horizontalStack(
			[avatar, identity],
			spacing: Layout.iconSpacing
		)
		profile.alignment = .centerY
		let profileContainer = NSView()
		installCentered(
			profile,
			in: profileContainer
		)
		avatar.widthAnchor.constraint(equalToConstant: Layout.avatarSize).isActive = true
		avatar.heightAnchor.constraint(equalToConstant: Layout.avatarSize).isActive = true
		profileContainer.heightAnchor.constraint(equalToConstant: Layout.profileHeight)
			.isActive = true

		for (index, row) in [usageRow, settingsRow, logoutRow].enumerated()
		{
			row.onHover =
			{
				[weak self] in self?.onHoverRow?(index)
			}
		}

		usageRow.target = self
		usageRow.action = #selector(showUsage)
		settingsRow.target = self
		settingsRow.action = #selector(showSettings)
		settingsRow.suffix = "⌘,"
		logoutRow.target = self
		logoutRow.action = #selector(logout)
		let topSeparator = separator()
		let bottomSeparator = separator()
		let stack = AppKitLayout.verticalStack(
			[
				profileContainer,
				topSeparator,
				usageRow,
				settingsRow,
				bottomSeparator,
				logoutRow,
			],
			spacing: 0
		)
		AppKitLayout.pin(
			stack,
			to: self,
			inset: 0
		)
		for row in [
			profileContainer,
			topSeparator,
			usageRow,
			settingsRow,
			bottomSeparator,
			logoutRow
		]
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	private func installCentered(
		_ content: NSView,
		in container: NSView
	)
	{
		container.addSubview(content)
		content.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			content.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: Layout.horizontalInset
			),
			content.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -Layout.horizontalInset
			),
			content.centerYAnchor.constraint(equalTo: container.centerYAnchor),
		])
	}

	private func separator() -> NSView
	{
		let container = NSView()
		let line = NSBox()
		line.boxType = .separator
		container.addSubview(line)
		line.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			container.heightAnchor.constraint(equalToConstant: Layout.separatorHeight),
			line.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: Layout.horizontalInset
			),
			line.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -Layout.horizontalInset
			),
			line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
		])
		return container
	}

	func highlightMenuItem(_ index: Int?)
	{
		for (rowIndex, row) in [usageRow, settingsRow, logoutRow].enumerated()
		{
			row.menuHighlighted = rowIndex == index
		}
	}

	func render(_ snapshot: ConversationSnapshot)
	{
		render(WorkspaceStatusPresentation(snapshot))
	}

	func render(_ presentation: WorkspaceStatusPresentation)
	{
		let account = presentation.accountStatus
		accountLabel.stringValue = account?.email ?? presentation.accountDescription
		accountLabel.toolTip = presentation.accountDescription
		let plan = account?.planType ?? presentation.usage.limits?.rateLimits.planType
		planLabel.stringValue = presentation.accountActionError.map
		{
			"Could not log out: \($0)"
		}
		?? plan?.capitalized ?? ""
		planLabel.toolTip = planLabel.stringValue
		planLabel.textColor = presentation
			.accountActionError == nil ? .tertiaryLabelColor : .systemRed
		planLabel.isHidden = plan == nil && presentation.accountActionError == nil
		avatar.stringValue = account?.email.map
		{
			String($0.prefix(2)).uppercased()
		} ?? ""
		usageRow.suffix = Self.remainingUsage(presentation.usage)
		logoutRow.isEnabled = presentation.canLogOut && !presentation.accountActionPending
	}

	static func remainingUsage(_ presentation: UsagePresentation) -> String
	{
		guard let primary = presentation.limits?.rateLimits.primary
		else
		{
			return "Unavailable"
		}
		let remaining = max(
			0,
			min(
				100,
				100 - Int(primary.usedPercent.rounded())
			)
		)
		return "\(remaining)% left" + (presentation.isStale ? " · stale" : "")
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

	@objc private func showUsage()
	{
		onShowUsage?()
	}

	@objc private func showSettings()
	{
		onShowSettings?()
	}
	@objc private func logout()
	{
		onLogout?()
	}
}

/// Maps account actions to the shared menu item UI.
@MainActor
private final class AccountMenuRow: DesktopMenuRow
{
	init(
		title: String,
		icon: DesktopIcon
	)
	{
		super.init(
			content: Content(
				title: title,
				icon: DesktopIcons.image(icon),
				suffixStyle: title == "Settings" ? .shortcut : .metadata
			)
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
