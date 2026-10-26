import AppKit
import UniformTypeIdentifiers

@MainActor
final class SettingsViewController: NSViewController, NSSearchFieldDelegate
{
	private let search = SettingsSearchField()
	private let personalHeading = AppKitControlStyling.sectionLabel("Personal")
	private let codingHeading = AppKitControlStyling.sectionLabel("Coding")
	private let accountStatus = SettingsPageLayout.status("Checking sign-in…")
	private let backendState = SettingsPageLayout.status("Checking backend…")
	private let editorOpeningService = EditorOpeningService()
	private let pageContainer = NSView()
	private let backendStatus = SettingsPageLayout.status("")
	private var backendBanner: NSStackView?
	private let generalPage = SettingsGeneralPage()
	private let generalButton = SettingsSidebarButton(
		title: "General",
		icon: .settings
	)
	private let notificationsPage = SettingsNotificationsPage()
	private let notificationsButton = SettingsSidebarButton(
		title: "Notifications",
		icon: .notificationBell
	)
	private let connectionsButton = SettingsSidebarButton(
		title: "Connections",
		icon: .globe
	)
	private var connectionsPage: NSView?
	private let accountPage = SettingsAccountPage()
	private let accountButton = SettingsSidebarButton(
		title: "Account",
		icon: .avatarProfile
	)
	private enum Page: String, CaseIterable
	{
		case general = "General"
		case notifications = "Notifications"
		case personalization = "Personalization"
		case voice = "Voice"
		case account = "Account"
		case archivedChats = "Archived chats"
		case usage = "Usage & billing"
		case configuration = "Configuration"
		case browser = "Browser"
		case plugins = "Plugins"
		case hooks = "Hooks"
		case connections = "Connections"
	}
	private static let personalPages: [Page] = [
		.general,
		.notifications,
		.configuration,
		.personalization,
		.voice,
		.account,
		.archivedChats,
		.usage
	]
	private static let codingPages: [Page] = [
		.browser,
		.plugins,
		.hooks,
		.connections
	]
	private let backend: SettingsBackend
	private var backendStart: Task<Void, Never>?
	private var additionalPages: [Page: NSView] = [:]
	private lazy var generalExtras = SettingsGeneralExtrasPage(backend: backend)
	private lazy var additionalButtons: [Page: SettingsSidebarButton] =
	{
		var buttons: [Page: SettingsSidebarButton] = [:]
		for page in Page.allCases where ![.general, .notifications, .account, .connections]
			.contains(page)
		{
			let button = SettingsSidebarButton(
				title: page.rawValue,
				icon: icon(for: page)
			)
			button.target = self
			button.action = #selector(showAdditionalPage(_:))
			buttons[page] = button
		}
		return buttons
	}()
	private var selectedPage: Page = .general
	private var connectionsActive = false
	let remoteAccess = RemoteAccessWindowController()
	var onApplyConfigurationDefaults: (([String: Any], Set<String>) -> Void)?
	var onLogin: (() -> Void)?
	var onReconnect: (() -> Void)?
	var onShowBackendDetails: (() -> Void)?
	var onClose: (() -> Void)?
	var onSelectApprovalMode: ((ApprovalMode) -> Void)?
	var onRequestNotificationAuthorization: (() -> Void)?
	var onRefreshNotificationAuthorization: (() -> Void)?

	init(backend: SettingsBackend = SettingsBackend())
	{
		self.backend = backend
		super.init(
			nibName: nil,
			bundle: nil
		)
		view = SettingsSurfaceView(color: AppKitColorTokens.canvas)

		configureStatusLabels()
		updateEditorLabel()

		generalPage.onChooseEditor =
		{
			[weak self] in self?.selectEditor()
		}
		generalPage.onUseSystemDefault =
		{
			[weak self] in self?.useDefaultEditor()
		}
		generalPage.onSelectEditorApplication =
		{
			[weak self] application in
			self?.editorOpeningService.preferredApplication = application
			self?.updateEditorLabel()
		}
		generalPage.onSelectApprovalMode =
		{
			[weak self] mode in
			self?.onSelectApprovalMode?(mode)
		}
		let requestAuthorization: () -> Void =
		{
			[weak self] in self?.onRequestNotificationAuthorization?()
		}
		let refreshAuthorization: () -> Void =
		{
			[weak self] in self?.onRefreshNotificationAuthorization?()
		}
		generalPage.notificationControls.onRequestAuthorization = requestAuthorization
		generalPage.notificationControls.onRefreshAuthorization = refreshAuthorization
		notificationsPage.onRequestAuthorization = requestAuthorization
		notificationsPage.onRefreshAuthorization = refreshAuthorization
		generalPage.setAdditionalSettings(generalExtras)
		generalPage.setAdditionalSettings(makeAppStatusSection())
		backend.onChange =
		{
			[weak self] in self?.refreshBackendPage()
		}
		backend.onDidSave =
		{
			[weak self] edits in
			guard let self
			else
			{
				return
			}
			let keys = Set(edits.keys)
			let defaultsKeys: Set<String> = ["approval_policy",
												"sandbox_mode",
												"sandbox_workspace_write.network_access",
												"service_tier"]
			if !keys.isDisjoint(with: defaultsKeys)
			{
				onApplyConfigurationDefaults?(backend.config, keys)
			}
		}
		installSettingsShell(in: view)
		selectPage(.general)
	}

	private func installSettingsShell(in container: NSView)
	{
		let sidebar = SettingsSurfaceView(color: AppKitColorTokens.settingsSidebarSurface)
		sidebar.showsTrailingSeparator = true
		let page = SettingsSurfaceView(color: AppKitColorTokens.canvas)
		let title = NSTextField(labelWithString: "Settings")
		title.font = AppKitFontResolver.font(TypographyTokens.Settings.heading)
		title.textColor = AppKitColorTokens.settingsPrimaryText
		for heading in [personalHeading, codingHeading]
		{
			heading.font = AppKitFontResolver.font(TypographyTokens.Settings.section)
			heading.textColor = AppKitColorTokens.settingsTertiaryText
		}
		generalButton.target = self
		generalButton.action = #selector(showGeneral)
		notificationsButton.target = self
		notificationsButton.action = #selector(showNotifications)
		accountButton.target = self
		accountButton.action = #selector(showAccount)
		connectionsButton.target = self
		connectionsButton.action = #selector(showRemoteAccess)
		let headingRows = [personalHeading, codingHeading].map
		{
			heading in
			let row = NSView()
			heading.translatesAutoresizingMaskIntoConstraints = false
			row.addSubview(heading)
			NSLayoutConstraint.activate([
				heading.leadingAnchor.constraint(
					equalTo: row.leadingAnchor,
					constant: 8
				),
				heading.topAnchor.constraint(equalTo: row.topAnchor),
				heading.bottomAnchor.constraint(equalTo: row.bottomAnchor),
				row.heightAnchor.constraint(equalToConstant: 21),
			])
			return row
		}
		let sections = AppKitLayout.verticalStack(
			[headingRows[0]] + Self.personalPages.map(button(for:))
				+ [headingRows[1]] + Self.codingPages.map(button(for:)),
			spacing: 1
		)
		sections.setCustomSpacing(
			16,
			after: button(for: .usage)
		)
		let sidebarScroll = NSScrollView()
		sidebarScroll.hasVerticalScroller = true
		sidebarScroll.autohidesScrollers = true
		sidebarScroll.drawsBackground = false
		sidebarScroll.contentView.drawsBackground = false
		let sidebarDocument = DesktopFlippedView()
		sidebarDocument.translatesAutoresizingMaskIntoConstraints = false
		sidebarScroll.documentView = sidebarDocument
		sections.translatesAutoresizingMaskIntoConstraints = false
		sidebarDocument.addSubview(sections)
		NSLayoutConstraint.activate([
			sidebarDocument.widthAnchor.constraint(equalTo: sidebarScroll.contentView.widthAnchor),
			sections.leadingAnchor.constraint(equalTo: sidebarDocument.leadingAnchor),
			sections.trailingAnchor.constraint(equalTo: sidebarDocument.trailingAnchor),
			sections.topAnchor.constraint(equalTo: sidebarDocument.topAnchor),
			sections.bottomAnchor.constraint(
				equalTo: sidebarDocument.bottomAnchor,
				constant: -16
			),
		])
		search.setAccessibilityLabel("Search settings")
		search.delegate = self
		for view in [sidebar, page]
		{
			view.translatesAutoresizingMaskIntoConstraints = false
			container.addSubview(view)
		}
		for view in [title, search, sidebarScroll]
		{
			view.translatesAutoresizingMaskIntoConstraints = false
			sidebar.addSubview(view)
		}
		backendStatus.setActions([.init(
			title: "Reload",
			accessibilityLabel: "Reload Codex settings"
		)
		{
			[weak self] in self?.reloadSettings()
		}])
		let banner = NSStackView(views: [backendStatus])
		banner.orientation = .horizontal
		banner.spacing = 12
		banner.edgeInsets = NSEdgeInsets(
			top: 8,
			left: 20,
			bottom: 8,
			right: 20
		)
		backendBanner = banner
		let pageStack = AppKitLayout.verticalStack(
			[banner, pageContainer],
			spacing: 0
		)
		for child in [banner, pageContainer]
		{
			child.widthAnchor.constraint(equalTo: pageStack.widthAnchor).isActive = true
		}
		pageStack.translatesAutoresizingMaskIntoConstraints = false
		page.addSubview(pageStack)
		NSLayoutConstraint.activate([
			sidebar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			sidebar.topAnchor.constraint(equalTo: container.topAnchor),
			sidebar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
			sidebar.widthAnchor.constraint(equalToConstant: LayoutTokens.Settings.sidebarWidth),
			page.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
			page.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			page.topAnchor.constraint(equalTo: container.topAnchor),
			page.bottomAnchor.constraint(equalTo: container.bottomAnchor),
			title.leadingAnchor.constraint(
				equalTo: sidebar.leadingAnchor,
				constant: 16
			),
			title.topAnchor.constraint(
				equalTo: sidebar.topAnchor,
				constant: 14
			),
			sidebarScroll.leadingAnchor.constraint(
				equalTo: sidebar.leadingAnchor,
				constant: LayoutTokens.Settings.sidebarGutter
			),
			sidebarScroll.trailingAnchor.constraint(
				equalTo: sidebar.trailingAnchor,
				constant: -LayoutTokens.Settings.sidebarGutter
			),
			search.leadingAnchor.constraint(
				equalTo: sidebar.leadingAnchor,
				constant: 8
			),
			search.trailingAnchor.constraint(
				equalTo: sidebar.trailingAnchor,
				constant: -8
			),
			search.topAnchor.constraint(
				equalTo: sidebar.topAnchor,
				constant: LayoutTokens.Settings.headerHeight
			),
			search.heightAnchor.constraint(equalToConstant: LayoutTokens.Settings.searchHeight),
			sidebarScroll.topAnchor.constraint(
				equalTo: search.bottomAnchor,
				constant: 16
			),
		])
		sidebarScroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor).isActive = true
		AppKitLayout.pin(
			pageStack,
			to: page,
			inset: 0
		)
		for button in Page.allCases.map(button(for:))
		{
			button.widthAnchor.constraint(equalTo: sections.widthAnchor).isActive = true
			button.heightAnchor.constraint(equalToConstant: LayoutTokens.Settings.sidebarRowHeight)
				.isActive = true
		}
		for row in headingRows
		{
			row.widthAnchor.constraint(equalTo: sections.widthAnchor).isActive = true
			sections.setCustomSpacing(
				8.5,
				after: row
			)
		}
	}

	private func selectPage(_ page: Page)
	{
		if selectedPage == .connections && page != .connections
		{
			endConnectionsPresentation()
		}
		selectedPage = page
		for (candidate, button) in additionalButtons
		{
			button.isSelected = candidate == page
		}
		generalButton.isSelected = page == .general
		notificationsButton.isSelected = page == .notifications
		accountButton.isSelected = page == .account
		connectionsButton.isSelected = page == .connections
		for view in pageContainer.subviews
		{
			view.removeFromSuperview()
		}
		let content: NSView
		if page == .connections
		{
			if connectionsPage == nil
			{
				connectionsPage = remoteAccess.window?.contentView
				remoteAccess.window?.contentView = nil
			}
			guard let connectionsPage
			else
			{
				return
			}
			content = connectionsPage
		}
		else
		{
			switch page
			{
			case .account: content = accountPage
			case .notifications:
				notificationsPage.refreshPreferences()
				content = notificationsPage
			case .general, .connections:
				generalPage.notificationControls.refreshPreferences()
				content = generalPage
			default:
				content = additionalPage(for: page)
			}
			if page == .general || page == .notifications
			{
				onRefreshNotificationAuthorization?()
			}
		}
		AppKitLayout.pin(
			content,
			to: pageContainer,
			inset: 0
		)
		refreshBackendPage()
		if page == .connections && view.window?.isVisible == true
		{
			beginConnectionsPresentation()
		}
	}

	private func beginConnectionsPresentation()
	{
		guard !connectionsActive
		else
		{
			return
		}
		connectionsActive = true
		remoteAccess.beginPresentation()
	}

	private func endConnectionsPresentation()
	{
		guard connectionsActive
		else
		{
			return
		}
		connectionsActive = false
		remoteAccess.endPresentation()
	}

	func presentConnections()
	{
		selectPage(.connections)
	}

	func showUsage()
	{
		search.stringValue = ""
		controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
		selectPage(.usage)
	}

	func endPresentation()
	{
		endConnectionsPresentation()
		backendStart?.cancel()
		backendStart = nil
		(additionalPages[.plugins] as? SettingsPluginsPage)?.resetForEndPresentation()
		backend.stop()
	}

	@objc private func closeSettings()
	{
		onClose?()
	}

	func controlTextDidChange(_ notification: Notification)
	{
		let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		for page in Page.allCases
		{
			let terms = page.rawValue + " " + searchTerms(for: page)
			button(for: page).isHidden = !query.isEmpty
				&& !terms.localizedCaseInsensitiveContains(query)
		}
		let personalHidden = Self.personalPages.allSatisfy
		{
			button(for: $0).isHidden
		}
		let codingHidden = Self.codingPages.allSatisfy
		{
			button(for: $0).isHidden
		}
		personalHeading.superview?.isHidden = personalHidden
		codingHeading.superview?.isHidden = codingHidden
	}

	@objc private func showAccount()
	{
		selectPage(.account)
	}

	@objc private func showNotifications()
	{
		selectPage(.notifications)
	}

	@objc private func showGeneral()
	{
		selectPage(.general)
	}

	private func configureStatusLabels()
	{
		accountStatus.messageLabel.setAccessibilityLabel("Account status")
		accountStatus.messageLabel.maximumNumberOfLines = 1
		accountStatus.messageLabel.lineBreakMode = .byTruncatingTail
		accountStatus.messageLabel.setContentCompressionResistancePriority(
			.defaultHigh,
			for: .horizontal
		)
		accountStatus.messageLabel.superview?.setContentCompressionResistancePriority(
			.defaultHigh,
			for: .horizontal
		)
	}

	func renderPermissions(
		mode: ApprovalMode,
		enabled: Bool,
		configurationDefaults: RunConfigurationDefaults? = nil
	)
	{
		generalPage.renderPermissions(
			mode: mode,
			enabled: enabled,
			configurationDefaults: configurationDefaults
		)
	}

	private func makeAppStatusSection() -> NSView
	{
		accountStatus.setActions([.init(title: "Sign In…")
			{
				[weak self] in self?.signIn()
			}])
		backendState.setActions([
			.init(title: "Reconnect")
			{
				[weak self] in self?.reconnect()
			},
			.init(title: "Details")
			{
				[weak self] in self?.showBackendDetails()
			}
		])
		return SettingsPageLayout.section(
			title: "App",
			rows: [
				SettingsPageLayout.row(
					title: "Account",
					detail: nil,
					control: accountStatus
				),
				SettingsPageLayout.row(
					title: "Backend",
					detail: nil,
					control: backendState
				),
			]
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
		accountPage.render(snapshot)
		accountStatus.setMessage(snapshot.accountDescription)
		accountStatus.messageLabel.toolTip = snapshot.accountDescription
		backendState.setMessage(snapshot.backendDescription)
		backendState.messageLabel.toolTip = snapshot.backendDescription
		updateEditorLabel()
	}

	func present()
	{
		search.stringValue = ""
		controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
		selectPage(.general)
		backendStart?.cancel()
		backendStart = Task
		{
			[weak self] in await self?.backend.start()
		}
		view.window?.makeFirstResponder(search)
	}

	func setNotificationAuthorization(_ state: TaskNotificationAuthorization)
	{
		generalPage.notificationControls.setAuthorization(state)
		notificationsPage.setNotificationAuthorization(state)
	}

	func setNotificationStatus(_ message: String)
	{
		generalPage.setNotificationStatus(message)
		notificationsPage.setNotificationStatus(message)
	}

	private func updateEditorLabel()
	{
		generalPage.setEditor(application: editorOpeningService.preferredApplication)
	}

	@objc private func signIn()
	{
		onLogin?()
	}
	@objc private func reconnect()
	{
		onReconnect?()
	}
	@objc private func showRemoteAccess()
	{
		presentConnections()
	}
	@objc private func showBackendDetails()
	{
		onShowBackendDetails?()
	}

	@objc private func useDefaultEditor()
	{
		editorOpeningService.preferredApplication = nil
		updateEditorLabel()
	}

	@objc private func selectEditor()
	{
		guard let window = view.window
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
			self?.editorOpeningService.preferredApplication = url
			self?.updateEditorLabel()
		}
	}
}

extension SettingsViewController
{
	private func icon(for page: Page) -> DesktopIcon
	{
		switch page
		{
		case .personalization: .brain
		case .voice: .voice
		case .archivedChats: .archive
		case .usage: .analytics
		case .browser: .globe
		case .plugins: .pluginPuzzle
		case .hooks: .code
		default: .settings
		}
	}

	private func button(for page: Page) -> SettingsSidebarButton
	{
		switch page
		{
		case .general: generalButton
		case .notifications: notificationsButton
		case .account: accountButton
		case .connections: connectionsButton
		default: additionalButtons[page]!
		}
	}

	@objc private func showAdditionalPage(_ sender: NSButton)
	{
		guard let page = additionalButtons.first(where:
			{
				$0.value === sender
			})?.key
		else
		{
			return
		}
		selectPage(page)
	}

	private func additionalPage(for page: Page) -> NSView
	{
		if let existing = additionalPages[page]
		{
			return existing
		}
		let result: NSView
		switch page
		{
		case .configuration: result = SettingsConfigurationPage(backend: backend)
		case .personalization: result = SettingsPersonalizationPage(backend: backend)
		case .browser: result = SettingsBrowserPage(backend: backend)
		case .plugins: result = SettingsPluginsPage(backend: backend)
		case .hooks: result = SettingsHooksPage(backend: backend)
		case .archivedChats: result = SettingsArchivedChatsPage(backend: backend)
		case .usage: result = SettingsUsagePage(backend: backend)
		case .voice: result = SettingsVoicePage(backend: backend)
		default: return generalPage
		}
		additionalPages[page] = result
		return result
	}

	@objc private func reloadSettings()
	{
		Task
		{
			[weak self] in await self?.backend.reload()
		}
	}

	private func refreshBackendPage()
	{
		let messages = [backend.status, backend.featureStatus].filter
		{
			!$0.isEmpty
		}
		backendStatus.stringValue = messages.joined(separator: "\n")
		backendBanner?.isHidden = selectedPage == .connections || messages.isEmpty
		generalExtras.refresh()
		guard let page = additionalPages[selectedPage]
		else
		{
			return
		}
		switch page
		{
		case let page as SettingsConfigurationPage: page.refresh()
		case let page as SettingsPersonalizationPage: page.refresh()
		case let page as SettingsBrowserPage: page.refresh()
		case let page as SettingsPluginsPage: page.refresh()
		case let page as SettingsHooksPage: page.refresh()
		case let page as SettingsArchivedChatsPage: page.refresh()
		case let page as SettingsUsagePage: page.refresh()
		case let page as SettingsVoicePage: page.refresh()
		default: break
		}
	}

	private func searchTerms(for page: Page) -> String
	{
		switch page
		{
		case .general: "speed compression permissions editor notifications"
		case .configuration:
			"approval sandbox network web search output detail reasoning summary "
				+ "dependencies experimental features"
		case .personalization: "memories instructions AGENTS tool assisted"
		case .browser: "history websites site settings access downloads uploads site tools CDP"
		case .plugins: "MCP servers skills marketplace authentication"
		case .usage: "billing credits limits reset tokens activity profile"
		case .voice: "realtime audio microphone"
		default: ""
		}
	}
}
