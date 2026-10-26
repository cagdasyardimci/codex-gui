import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate
{
	private let sourceStore = WorkspaceStoreFactory.makeSource(
		dependencies: WorkspaceStoreDependencies(
			previewPreparer: ConversationMarkdownPreviewPreparer()
		)
	)
	private lazy var coordinator = TaskWorkspaceCoordinator(sourceStore: sourceStore)
	private let notifications = TaskNotificationCoordinator()
	private var mainWindowController: MainWindowController?
	private var waitingToQuit = false
	private var finalizingQuit = false
	private var pendingQuit: WorkspaceQuitRequest?

	func applicationDidFinishLaunching(_ notification: Notification)
	{
		createMenu()

		let controller = MainWindowController(
			store: sourceStore,
			onOpenProject:
			{
				[weak self] in self?.openProject()
			},
			onInsertPath:
			{
				[weak self] in self?.insertPath()
			},
			layoutStore: WindowLayoutStore(),
			coordinator: coordinator
		)
		mainWindowController = controller
		configureNotificationCallbacks(controller: controller)

		controller.showWindow(nil)
		NSApp.activate(ignoringOtherApps: true)

		configureCoordinatorCallbacks(controller: controller)

		coordinator.start()
	}

	func applicationDidBecomeActive(_ notification: Notification)
	{
		notifications.refreshAuthorizationStatus()
	}

	private func configureNotificationCallbacks(controller: MainWindowController)
	{
		controller.settings.onRequestNotificationAuthorization =
		{
			[weak self] in self?.notifications.requestAuthorization()
		}
		controller.settings.onRefreshNotificationAuthorization =
		{
			[weak self] in self?.notifications.refreshAuthorizationStatus()
		}
		notifications.onAuthorizationChange =
		{
			[weak controller] state in controller?.settings.setNotificationAuthorization(state)
		}
		notifications.onStatusChange =
		{
			[weak controller] message in
			controller?.setNotificationStatus(message)
		}
		notifications.onOpenOwnedThread =
		{
			[weak self] id, owner in self?.coordinator.selectThread(
				id,
				owner: owner
			)
		}
		notifications.onOpenThread =
		{
			[weak self] id in self?.coordinator.selectThread(id)
		}
		coordinator
			.onTaskSnapshot =
			{
				[weak self] snapshot in self?.notifications.observe(snapshot)
			}
	}

	private func configureCoordinatorCallbacks(controller: MainWindowController)
	{
		coordinator.onPresentationCommand =
		{
			[weak controller] command in
			if case .slashCommand = command
			{
				controller?.handlePresentationCommand(command)
			}
			if case .openSignIn(let url) = command
			{
				NSWorkspace.shared.open(url)
			}
		}
		coordinator.onQuitCompleted =
		{
			[weak self] request, approved in
			guard let self, self.waitingToQuit, self.pendingQuit == request
			else
			{
				return
			}
			if approved
			{
				guard !self.finalizingQuit
				else
				{
					return
				}
				self.finalizingQuit = true
				Task
				{
					[weak self] in
					guard let self, self.waitingToQuit, self.pendingQuit == request
					else
					{
						return
					}
					let filesSettled = await self.mainWindowController?
						.settleFileWritesForClosing() ?? true
					self.waitingToQuit = false
					self.finalizingQuit = false
					self.pendingQuit = nil
					NSApp.reply(toApplicationShouldTerminate: filesSettled)
				}
			}
			else
			{
				self.waitingToQuit = false
				self.finalizingQuit = false
				self.pendingQuit = nil
				NSApp.reply(toApplicationShouldTerminate: false)
			}
		}
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool
	{
		true
	}

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
	{
		guard !waitingToQuit
		else
		{
			return .terminateLater
		}
		waitingToQuit = true
		coordinator.onConfirmQuit =
		{
			[weak self] request in
			guard let self
			else
			{
				return
			}
			let confirmation = DesktopNativeConfirmation(
				title: "Codex is working",
				message: "Stop all running tasks before quitting, or keep the app open.",
				confirmTitle: "Stop Tasks and Quit",
				cancelTitle: "Keep App Open"
			)
			self.coordinator.confirmQuit(
				request,
				approved: confirmation.runModal()
			)
		}
		Task
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			let mayQuit = await self.mainWindowController?.settleFileWritesForClosing() ?? true
			guard mayQuit
			else
			{
				self.waitingToQuit = false
				NSApp.reply(toApplicationShouldTerminate: false)
				return
			}
			self.pendingQuit = self.coordinator.requestQuit()
		}
		return .terminateLater
	}

	func applicationWillTerminate(_ notification: Notification)
	{
		mainWindowController?.saveLayout()
		coordinator.shutdown()
	}

	private func createMenu()
	{
		let mainMenu = NSMenu()
		mainMenu.addItem(makeApplicationMenuItem())
		mainMenu.addItem(makeFileMenuItem())
		mainMenu.addItem(makeEditMenuItem())
		mainMenu.addItem(makeViewMenuItem())
		mainMenu.addItem(makeWindowMenuItem())
		mainMenu.addItem(makeHelpMenuItem())

		NSApp.mainMenu = mainMenu
	}

	private func makeApplicationMenuItem() -> NSMenuItem
	{
		let appItem = NSMenuItem()
		let appMenu = NSMenu()
		appMenu.addItem(
			withTitle: "Settings…",
			action: #selector(showSettings),
			keyEquivalent: ","
		).target = self
		appMenu.addItem(.separator())
		appMenu.addItem(
			withTitle: "Quit Codex GUI",
			action: #selector(NSApplication.terminate(_:)),
			keyEquivalent: "q"
		)
		appItem.submenu = appMenu
		return appItem
	}

	private func makeFileMenuItem() -> NSMenuItem
	{
		let fileItem = NSMenuItem()
		let fileMenu = NSMenu(title: "File")
		fileMenu.addItem(
			withTitle: "Open Project…",
			action: #selector(openProject),
			keyEquivalent: "o"
		)
		.target = self
		fileMenu.addItem(
			withTitle: "New Chat",
			action: #selector(newChat),
			keyEquivalent: "n"
		)
		.target = self
		let newTaskItem = fileMenu.addItem(
			withTitle: "New Task Checkout…",
			action: #selector(createTask),
			keyEquivalent: "n"
		)
		newTaskItem.keyEquivalentModifierMask = [.command, .shift]
		newTaskItem.target = self
		fileMenu.addItem(
			withTitle: "Refresh Conversations",
			action: #selector(refreshConversations),
			keyEquivalent: "r"
		).target = self
		fileMenu.addItem(
			withTitle: "Reconnect",
			action: #selector(reconnect),
			keyEquivalent: "k"
		)
		.target = self
		fileItem.submenu = fileMenu
		return fileItem
	}

	private func makeEditMenuItem() -> NSMenuItem
	{
		let editItem = NSMenuItem()
		let editMenu = NSMenu(title: "Edit")
		editMenu.addItem(
			withTitle: "Undo",
			action: Selector(("undo:")),
			keyEquivalent: "z"
		)
		let redoItem = editMenu.addItem(
			withTitle: "Redo",
			action: Selector(("redo:")),
			keyEquivalent: "z"
		)
		redoItem.keyEquivalentModifierMask = [.command, .shift]
		editMenu.addItem(.separator())
		editMenu.addItem(
			withTitle: "Cut",
			action: #selector(NSText.cut(_:)),
			keyEquivalent: "x"
		)
		editMenu.addItem(
			withTitle: "Copy",
			action: #selector(NSText.copy(_:)),
			keyEquivalent: "c"
		)
		editMenu.addItem(
			withTitle: "Paste",
			action: #selector(NSText.paste(_:)),
			keyEquivalent: "v"
		)
		editMenu.addItem(
			withTitle: "Select All",
			action: #selector(NSText.selectAll(_:)),
			keyEquivalent: "a"
		)
		editMenu.addItem(.separator())
		editMenu.addItem(
			withTitle: "Find",
			action: #selector(findConversation),
			keyEquivalent: "f"
		).target = self
		let messageSearch = editMenu.addItem(
			withTitle: "Search Messages",
			action: #selector(searchMessages),
			keyEquivalent: "f"
		)
		messageSearch.keyEquivalentModifierMask = [.command, .shift]
		messageSearch.target = self
		fileMenuShortcut(in: editMenu)
		let commandPaletteItem = editMenu.addItem(
			withTitle: "Command Palette",
			action: #selector(showCommandPalette),
			keyEquivalent: "p"
		)
		commandPaletteItem.keyEquivalentModifierMask = [.command, .shift]
		commandPaletteItem.target = self
		editItem.submenu = editMenu
		return editItem
	}

	private func fileMenuShortcut(in menu: NSMenu)
	{
		let quickOpen = menu.addItem(
			withTitle: "Open File Quickly",
			action: #selector(showFileQuickOpen),
			keyEquivalent: "p"
		)
		quickOpen.target = self
	}

	private func makeViewMenuItem() -> NSMenuItem
	{
		let viewItem = NSMenuItem()
		let viewMenu = NSMenu(title: "View")
		let toolbarItem = viewMenu.addItem(
			withTitle: "Show Toolbar",
			action: #selector(NSWindow.toggleToolbarShown(_:)),
			keyEquivalent: "t"
		)
		toolbarItem.keyEquivalentModifierMask = [.command, .option]
		viewItem.submenu = viewMenu
		return viewItem
	}

	private func makeWindowMenuItem() -> NSMenuItem
	{
		let windowItem = NSMenuItem()
		let windowMenu = NSMenu(title: "Window")
		windowMenu.addItem(
			withTitle: "Minimize",
			action: #selector(NSWindow.performMiniaturize(_:)),
			keyEquivalent: "m"
		)
		windowMenu.addItem(
			withTitle: "Zoom",
			action: #selector(NSWindow.performZoom(_:)),
			keyEquivalent: ""
		)
		windowMenu.addItem(.separator())
		windowMenu.addItem(
			withTitle: "Bring All to Front",
			action: #selector(NSApplication.arrangeInFront(_:)),
			keyEquivalent: ""
		)
		NSApp.windowsMenu = windowMenu
		windowItem.submenu = windowMenu
		return windowItem
	}

	private func makeHelpMenuItem() -> NSMenuItem
	{
		let helpItem = NSMenuItem()
		let helpMenu = NSMenu(title: "Help")
		helpMenu.addItem(
			withTitle: "Search Commands…",
			action: #selector(showCommandPalette),
			keyEquivalent: ""
		).target = self
		NSApp.helpMenu = helpMenu
		helpItem.submenu = helpMenu
		return helpItem
	}

	@objc private func openProject()
	{
		let target = selectedTarget()
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.allowsMultipleSelection = false
		panel.prompt = "Open Repository"
		panel.directoryURL = coordinator.sourceProjectURL
		if panel.runModal() == .OK, let url = panel.url, target.accepts(.newChat)
		{
			target.dispatch(.openProject(url))
		}
	}

	@objc private func insertPath()
	{
		let target = selectedTarget()
		guard let projectPath = target.reference.workspace.canonicalCheckoutPath
		else
		{
			return
		}
		let project = URL(fileURLWithPath: projectPath)
		let panel = NSOpenPanel()
		panel.canChooseDirectories = false
		panel.canChooseFiles = true
		panel.allowsMultipleSelection = false
		panel.prompt = "Insert Path"
		panel.directoryURL = project
		guard panel.runModal() == .OK, let url = panel.url,
				target.accepts(.editDraft(""))
		else
		{
			return
		}
		let canonicalProject = project.standardizedFileURL.resolvingSymlinksInPath()
		let canonicalFile = url.standardizedFileURL.resolvingSymlinksInPath()
		let path: String
		if canonicalFile.path.hasPrefix(canonicalProject.path + "/")
		{
			path = String(canonicalFile.path.dropFirst(canonicalProject.path.count + 1))
		}
		else
		{
			path = canonicalFile.path
		}
		mainWindowController?.insertPath(
			path,
			target: target
		)
	}

	@objc private func newChat()
	{
		selectedTarget().dispatch(.newChat)
	}
	@objc private func createTask()
	{
		mainWindowController?.createTask()
	}
	@objc private func findConversation()
	{
		if mainWindowController?.shouldRouteFindToFiles == true
		{
			mainWindowController?.findInCurrentFile()
		}
		else
		{
			mainWindowController?.focusSearch()
		}
	}
	@objc private func searchMessages()
	{
		if mainWindowController?.shouldRouteFindToFiles == true
		{
			mainWindowController?.showFileContentSearch()
		}
		else
		{
			mainWindowController?.showMessageSearch()
		}
	}
	@objc private func showFileQuickOpen()
	{
		mainWindowController?.showFileQuickOpen()
	}
	@objc private func showCommandPalette()
	{
		mainWindowController?.showCommandPalette()
	}
	@objc private func refreshConversations()
	{
		selectedTarget().dispatch(.refreshThreads)
	}
	private func selectedTarget() -> WorkspaceIntentTarget
	{
		WorkspaceIntentTarget(
			store: coordinator.selectedStore,
			snapshot: coordinator.currentSnapshot,
			coordinator: coordinator
		)
	}
	@objc private func reconnect()
	{
		selectedTarget().dispatch(.reconnect)
	}

	@objc private func showSettings()
	{
		mainWindowController?.showSettings()
	}
}
