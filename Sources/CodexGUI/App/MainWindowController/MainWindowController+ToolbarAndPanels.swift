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
		static let review = NSToolbarItem.Identifier("review")
		static let projectContext = NSToolbarItem.Identifier("projectContext")
		static let commandPalette = NSToolbarItem.Identifier("commandPalette")
		static let searchMessages = NSToolbarItem.Identifier("searchMessages")
		static let status = NSToolbarItem.Identifier("status")
	}

	func configureToolbarControls()
	{
		statusButton.target = self
		statusButton.action = #selector(showStatus)
		DesktopTheme.styleButton(
			statusButton,
			symbol: "circle.fill"
		)
		statusButton.image = NSImage(
			systemSymbolName: "circle.fill",
			accessibilityDescription: nil
		)?
			.withSymbolConfiguration(NSImage.SymbolConfiguration(
				pointSize: 6,
				weight: .regular
			))
		statusButton.font = .systemFont(ofSize: 11)
		statusButton.setAccessibilityLabel("Open account and backend status")
		AppKitLayout.compressHorizontally(statusButton)
		statusButton.widthAnchor.constraint(equalToConstant: 105).isActive = true
		statusButton.heightAnchor.constraint(equalToConstant: 26).isActive = true

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
			ToolbarItem.review,
			ToolbarItem.projectContext,
			ToolbarItem.commandPalette,
			ToolbarItem.searchMessages,
			ToolbarItem.status,
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
			ToolbarItem.status,
			ToolbarItem.searchMessages,
			ToolbarItem.commandPalette,
			ToolbarItem.review,
			ToolbarItem.projectContext,
		]
	}

	func toolbar(
		_ toolbar: NSToolbar,
		itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
		willBeInsertedIntoToolbar flag: Bool
	) -> NSToolbarItem?
	{
		if itemIdentifier == ToolbarItem.navigationSeparator,
			let split = window?.contentViewController as? NSSplitViewController
		{
			return NSTrackingSeparatorToolbarItem(
				identifier: itemIdentifier,
				splitView: split.splitView,
				dividerIndex: 0
			)
		}
		let item = NSToolbarItem(itemIdentifier: itemIdentifier)
		switch itemIdentifier
		{
		case ToolbarItem.sidebar:
			item.label = "Sidebar"
			item.image = NSImage(
				systemSymbolName: "sidebar.left",
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
			item.image = NSImage(
				systemSymbolName: "folder",
				accessibilityDescription: "Open project"
			)
			item.target = self
			item.action = #selector(openProjectPicker)
		case ToolbarItem.newChat:
			item.label = "New Chat"
			item.image = NSImage(
				systemSymbolName: "plus",
				accessibilityDescription: "New chat"
			)
			item.target = self
			item.action = #selector(newChat)
		case ToolbarItem.review:
			item.label = "Changes"
			item.image = NSImage(
				systemSymbolName: "doc.text.magnifyingglass",
				accessibilityDescription: "Toggle changes"
			)
			item.target = self
			item.action = #selector(toggleReview)
		case ToolbarItem.projectContext:
			item.label = "Context"
			item.image = NSImage(
				systemSymbolName: "pin",
				accessibilityDescription: "Project context"
			)
			item.target = self
			item.action = #selector(showProjectContext)
		case ToolbarItem.commandPalette:
			item.label = "Commands"
			item.image = NSImage(
				systemSymbolName: "command",
				accessibilityDescription: "Command palette"
			)
			item.target = self
			item.action = #selector(showCommandPalette)
		case ToolbarItem.searchMessages:
			item.label = "Search Messages"
			item.image = NSImage(
				systemSymbolName: "text.magnifyingglass",
				accessibilityDescription: "Search message contents"
			)
			item.target = self
			item.action = #selector(showMessageSearch)
		case ToolbarItem.status:
			item.label = "Status"
			item.view = statusButton
		default:
			return nil
		}
		item.toolTip = item.label
		return item
	}

	static func statusColor(_ state: ExecutionState) -> NSColor
	{
		switch state
		{
		case .running, .completed: .systemGreen
		case .awaitingApproval, .awaitingAnswer, .stopping: .systemOrange
		case .failed: .systemRed
		case .ready, .stopped, .disconnected: .secondaryLabelColor
		}
	}

	@objc private func openProjectPicker()
	{
		navigation.onOpenProject?()
	}
	@objc private func newChat()
	{
		dispatchCurrent(.newChat)
	}
	@objc func showProjectContext()
	{
		paneController.setReviewCollapsed(false)
		inspector.show(.projectContext)
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
				title: "Project Context",
				detail: "Inspect reusable context",
				destination: .action("context")
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
			case .action("context"): self.showProjectContext()
			case .action("search"): self.showMessageSearch()
			case .action("changes"):
				self.paneController.setReviewCollapsed(false)
				self.inspector.show(.changes)
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

	@objc private func showStatus()
	{
		let controller = NSViewController()
		controller.view = statusView
		let popover = NSPopover()
		popover.contentViewController = controller
		popover.contentSize = NSSize(
			width: 330,
			height: 215
		)
		popover.behavior = .transient
		statusPopover = popover
		popover.show(
			relativeTo: statusButton.bounds,
			of: statusButton,
			preferredEdge: .maxY
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
		paneController.toggleReview()
	}
}
