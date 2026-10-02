import AppKit

extension MainWindowController
{
	private enum ToolbarItem
	{
		static let sidebar = NSToolbarItem.Identifier("sidebar")
		static let navigationSeparator = NSToolbarItem.Identifier("navigationSeparator")
		static let conversationTitle = NSToolbarItem.Identifier("conversationTitle")
		static let openProject = NSToolbarItem.Identifier("openProject")
		static let newChat = NSToolbarItem.Identifier("newChat")
		static let summary = NSToolbarItem.Identifier("pinnedSummary")
		static let review = NSToolbarItem.Identifier("review")
		static let commandPalette = NSToolbarItem.Identifier("commandPalette")
		static let searchMessages = NSToolbarItem.Identifier("searchMessages")
	}

	func configureToolbarControls()
	{
		statusButton.target = self
		statusButton.action = #selector(showStatus)
		statusButton.bezelStyle = .inline
		statusButton.isBordered = false
		statusButton.image = DesktopIcons.image(
			.user,
			size: 18
		)
		statusButton.imagePosition = .imageOnly
		statusButton.contentTintColor = .labelColor
		statusButton.setAccessibilityLabel("Open account and backend status")
		statusButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
		statusButton.heightAnchor.constraint(equalToConstant: 32).isActive = true

		titleLabel.font = .systemFont(
			ofSize: 13,
			weight: .regular
		)
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		titleLabel.setAccessibilityLabel("Conversation title")
		titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true

		titlePill.addSubview(titleLabel)
		titlePill.translatesAutoresizingMaskIntoConstraints = false
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		titlePill.setAccessibilityElement(false)
		NSLayoutConstraint.activate([
			titleLabel.leadingAnchor.constraint(
				equalTo: titlePill.leadingAnchor,
				constant: 12
			),
			titleLabel.trailingAnchor.constraint(
				equalTo: titlePill.trailingAnchor,
				constant: -12
			),
			titleLabel.centerYAnchor.constraint(equalTo: titlePill.centerYAnchor),
			titlePill.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
			titlePill.widthAnchor.constraint(lessThanOrEqualToConstant: 304),
			titlePill.heightAnchor.constraint(equalToConstant: 32),
		])
	}

	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
	{
		[
			ToolbarItem.sidebar,
			ToolbarItem.navigationSeparator,
			ToolbarItem.conversationTitle,
			ToolbarItem.openProject,
			ToolbarItem.newChat,
			ToolbarItem.summary,
			ToolbarItem.review,
			ToolbarItem.commandPalette,
			ToolbarItem.searchMessages,
			.flexibleSpace,
		]
	}

	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
	{
		[
			ToolbarItem.sidebar,
			ToolbarItem.navigationSeparator,
			ToolbarItem.conversationTitle,
			ToolbarItem.newChat,
			.flexibleSpace,
			ToolbarItem.searchMessages,
			ToolbarItem.commandPalette,
			ToolbarItem.summary,
			ToolbarItem.review,
		]
	}

	func toolbar(
		_ toolbar: NSToolbar,
		itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
		willBeInsertedIntoToolbar flag: Bool
	) -> NSToolbarItem?
	{
		if itemIdentifier == ToolbarItem.navigationSeparator
		{
			return NSTrackingSeparatorToolbarItem(
				identifier: itemIdentifier,
				splitView: paneController.split.splitView,
				dividerIndex: 0
			)
		}
		let item = NSToolbarItem(itemIdentifier: itemIdentifier)
		switch itemIdentifier
		{
		case ToolbarItem.sidebar:
			item.label = "Sidebar"
			item.image = DesktopIcons.image(
				.sidebar,
				accessibilityDescription: "Toggle sidebar"
			)
			item.target = self
			item.action = #selector(toggleSidebar)
		case ToolbarItem.conversationTitle:
			item.label = "Conversation"
			item.view = titlePill
			item.visibilityPriority = .low
		case ToolbarItem.openProject:
			item.label = "Open Project"
			item.image = DesktopIcons.image(
				.folder,
				accessibilityDescription: "Open project"
			)
			item.target = self
			item.action = #selector(openProjectPicker)
		case ToolbarItem.newChat:
			item.label = "New Chat"
			item.image = DesktopIcons.image(
				.plus,
				accessibilityDescription: "New chat"
			)
			item.target = self
			item.action = #selector(newChat)
		case ToolbarItem.summary:
			item.label = "Toggle pinned summary"
			summaryToggleButton.target = self
			summaryToggleButton.action = #selector(togglePinnedSummary)
			summaryToggleButton.setButtonType(.toggle)
			summaryToggleButton.bezelStyle = .texturedRounded
			summaryToggleButton.isBordered = false
			summaryToggleButton.contentTintColor = .labelColor
			summaryToggleButton.image = PinnedSummaryIcons.image(
				.toggle,
				size: 16,
				accessibilityDescription: "Toggle pinned summary"
			)
			summaryToggleButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
			summaryToggleButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
			summaryToggleButton.toolTip = "Toggle pinned summary"
			summaryToggleButton.setAccessibilityLabel("Toggle pinned summary")
			item.view = summaryToggleButton
		case ToolbarItem.review:
			item.label = "Changes"
			item.image = DesktopIcons.image(
				.fileDocument,
				accessibilityDescription: "Toggle changes"
			)
			item.target = self
			item.action = #selector(toggleReview)
		case ToolbarItem.commandPalette:
			item.label = "Commands"
			item.image = DesktopIcons.image(
				.keyboardShortcut,
				accessibilityDescription: "Command palette"
			)
			item.target = self
			item.action = #selector(showCommandPalette)
		case ToolbarItem.searchMessages:
			item.label = "Search Messages"
			item.image = DesktopIcons.image(
				.search,
				accessibilityDescription: "Search message contents"
			)
			item.target = self
			item.action = #selector(showMessageSearch)
		default:
			return nil
		}
		item.toolTip = item.label
		return item
	}

	@objc private func openProjectPicker()
	{
		navigation.onOpenProject?()
	}
	@objc private func newChat()
	{
		dispatchCurrent(.newChat)
	}

	@objc func showCommandPalette()
	{
		guard let window, let snapshot = latestSnapshot
		else
		{
			return
		}
		var commands = snapshot.recentProjects.map
		{
			PaletteCommand(
				title: $0.lastPathComponent,
				detail: $0.path,
				destination: .project($0)
			)
		}
		commands += snapshot.threads.map
		{
			PaletteCommand(
				title: $0.name ?? $0.preview ?? $0.id,
				detail: "Conversation · \($0.id)",
				destination: .conversation($0.id)
			)
		}
		commands += [
			PaletteCommand(
				title: "New Chat",
				detail: "Start a conversation",
				destination: .action("new")
			),
			PaletteCommand(
				title: "Search Messages",
				detail: "Search loaded conversation contents",
				destination: .action("search")
			),
			PaletteCommand(
				title: "Changes",
				detail: "Inspect the selected turn's changes",
				destination: .action("changes")
			),
		]
		let target = WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		)
		commandPalette.onChoose =
		{
			[weak self] destination in
			guard let self
			else
			{
				return
			}
			switch destination
			{
			case .project(let url): target.dispatch(.openProject(url))
			case .conversation(let id): target.dispatch(.selectThread(id))
			case .action("new"): target.dispatch(.newChat)
			case .action("search"): self.showMessageSearch()
			case .action("changes"):
				self.openCurrentChanges()
			case .action: break
			}
		}
		commandPalette.present(
			in: window,
			commands: commands
		)
	}

	@objc func showMessageSearch()
	{
		guard let window
		else
		{
			return
		}
		messageSearch.present(in: window)
	}

	func showSettings()
	{
		settings.present()
	}
	func setNotificationStatus(_ message: String)
	{
		settings.setNotificationStatus(message)
	}

	@objc func showStatus()
	{
		let controller = NSViewController()
		controller.view = statusView
		let popover = NSPopover()
		popover.contentViewController = controller
		popover.contentSize = NSSize(
			width: 380,
			height: 320
		)
		popover.behavior = .transient
		statusPopover = popover
		popover.show(
			relativeTo: statusButton.bounds,
			of: statusButton,
			preferredEdge: .maxX
		)
	}

	func showBackendDetails()
	{
		guard let hostWindow = settings.window?.isVisible == true ? settings.window : window
		else
		{
			return
		}
		let report = WorkspaceSelectors(
			model: currentStore.model,
			now: Date()
		)
		.backendDiagnosticsReport
		let alert = NSAlert()
		alert.messageText = "Backend Details"
		alert.informativeText =
			"Common credentials are redacted, but secrets may remain. Review before sharing."
		alert.accessoryView = BackendDetailsView(report: report)
		alert.addButton(withTitle: "Close")
		alert.addButton(withTitle: "Copy Details")
		alert.beginSheetModal(for: hostWindow)
		{
			response in
			guard response == .alertSecondButtonReturn
			else
			{
				return
			}
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(
				report,
				forType: .string
			)
		}
	}

	@objc private func toggleSidebar()
	{
		paneController.toggleSidebar()
	}

	@objc private func toggleReview()
	{
		openCurrentChanges(toggleIfShowing: true)
	}
}
