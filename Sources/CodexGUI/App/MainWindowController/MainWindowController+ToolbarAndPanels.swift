import AppKit

extension MainWindowController
{
	enum ToolbarItem
	{
		static let navigationControls = NSToolbarItem.Identifier("navigationControls")
		static let trailingControls = NSToolbarItem.Identifier("trailingControls")
		static let toolsSeparator = NSToolbarItem.Identifier("toolsSeparator")
		static let toolsTabBar = NSToolbarItem.Identifier("toolsTabBar")
		static let back = NSToolbarItem.Identifier("back")
		static let forward = NSToolbarItem.Identifier("forward")
		static let sidebarPlaceholder = NSToolbarItem.Identifier("sidebarPlaceholder")
		static let sidebar = NSToolbarItem.Identifier("sidebar")
		static let navigationSeparator = NSToolbarItem.Identifier("navigationSeparator")
		static let projectContext = NSToolbarItem.Identifier("projectContext")
		static let conversationTitle = NSToolbarItem.Identifier("conversationTitle")
		static let openProject = NSToolbarItem.Identifier("openProject")
		static let newChat = NSToolbarItem.Identifier("newChat")
		static let moreOptions = NSToolbarItem.Identifier("moreOptions")
		static let summary = NSToolbarItem.Identifier("pinnedSummary")
		static let summarySeparator = NSToolbarItem.Identifier("summarySeparator")
		static let newTab = NSToolbarItem.Identifier("newTab")
		static let review = NSToolbarItem.Identifier("review")
		static let commandPalette = NSToolbarItem.Identifier("commandPalette")
		static let searchMessages = NSToolbarItem.Identifier("searchMessages")
	}

	private typealias ToolbarLayout = LayoutTokens.Toolbar

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
		statusButton.setAccessibilityIdentifier("workspace-status")
		statusButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
		statusButton.heightAnchor.constraint(equalToConstant: 36).isActive = true

		configureToolbarTitle()
		configureSummaryToggle()
		toolsToolbar.configureOpenButton(
			target: self,
			action: #selector(toggleToolsPane),
			controlSize: ToolbarLayout.controlSize
		)
	}

	private func configureToolbarTitle()
	{
		configureTitleLabel()

		let projectIcon = makeProjectContextIcon()
		titleContainer.addSubview(projectIcon)
		titleContainer.addSubview(titleLabel)
		titleContainer.translatesAutoresizingMaskIntoConstraints = false
		projectIcon.translatesAutoresizingMaskIntoConstraints = false
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		titleContainer.setAccessibilityElement(false)
		titleContainer.clipsToBounds = false
		NSLayoutConstraint.activate([
			projectIcon.leadingAnchor.constraint(
				equalTo: titleContainer.leadingAnchor,
				constant: -2
			),
			projectIcon.centerYAnchor.constraint(
				equalTo: titleContainer.centerYAnchor,
				constant: 2
			),
			titleLabel.leadingAnchor.constraint(
				equalTo: projectIcon.trailingAnchor,
				constant: ToolbarLayout.titleSpacing
			),
			titleLabel.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor),
			titleLabel.centerYAnchor.constraint(
				equalTo: titleContainer.centerYAnchor,
				constant: 1.5
			),
			titleContainer.widthAnchor.constraint(
				lessThanOrEqualToConstant: ToolbarLayout.controlSize + ToolbarLayout.titleSpacing
					+ ToolbarLayout.maximumTitleWidth
			),
			titleContainer.heightAnchor.constraint(equalToConstant: ToolbarLayout.rowHeight),
		])
	}

	private func configureTitleLabel()
	{
		titleLabel.font = AppKitFontResolver.font(TypographyTokens.Toolbar.title)
		titleLabel.isBordered = false
		titleLabel.isBezeled = false
		titleLabel.drawsBackground = false
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		titleLabel.setAccessibilityLabel("Conversation title")
		titleLabel.widthAnchor.constraint(
			lessThanOrEqualToConstant: ToolbarLayout.maximumTitleWidth
		).isActive = true
	}

	func updateNavigationToolbarSeparator()
	{
		guard let window,
				titleContainer.window === window,
				window.toolbar?.isVisible == true,
				let navigationView = paneController.split.splitView.subviews.first
		else
		{
			navigationToolbarSeparator.isHidden = true
			return
		}

		let toolbarView = titleContainer
		let splitView = paneController.split.splitView
		let dividerPosition = NSPoint(
			x: navigationView.frame.maxX + splitView.dividerThickness / 2,
			y: splitView.bounds.midY
		)
		let dividerInToolbar = splitView.convert(
			dividerPosition,
			to: toolbarView
		)
		let separatorFrame = ToolbarSeparatorView.frame(
			dividerPosition: dividerInToolbar,
			hostBounds: toolbarView.bounds,
			backingScale: window.backingScaleFactor
		)
		// Keep the marker in our toolbar view and pass dragging through to the native separator.
		if navigationToolbarSeparator.superview !== toolbarView
		{
			toolbarView.addSubview(navigationToolbarSeparator)
		}
		if navigationToolbarSeparator.frame != separatorFrame
		{
			navigationToolbarSeparator.frame = separatorFrame
		}
		let isHidden = paneController.split.splitViewItems[0].isCollapsed || titleContainer.isHidden
		if navigationToolbarSeparator.isHidden != isHidden
		{
			navigationToolbarSeparator.isHidden = isHidden
		}
	}

	private func configureSummaryToggle()
	{
		summaryToggleButton.target = self
		summaryToggleButton.action = #selector(togglePinnedSummary)
		summaryToggleButton.setButtonType(.toggle)
		summaryToggleButton.bezelStyle = .texturedRounded
		summaryToggleButton.isBordered = false
		summaryToggleButton.contentTintColor = AppKitColorTokens.secondaryText
		summaryToggleButton.image = PinnedSummaryIcons.image(
			.toggle,
			size: 15,
			accessibilityDescription: "Toggle pinned summary"
		)
		summaryToggleButton.imagePosition = .imageOnly
		summaryToggleButton.widthAnchor.constraint(
			equalToConstant: ToolbarLayout.controlSize
		).isActive = true
		summaryToggleButton.heightAnchor.constraint(
			equalToConstant: ToolbarLayout.controlSize
		).isActive = true
		summaryToggleButton.toolTip = "Toggle pinned summary"
		summaryToggleButton.setAccessibilityLabel("Toggle pinned summary")
	}

	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
	{
		[
			ToolbarItem.navigationControls,
			ToolbarItem.trailingControls,
			ToolbarItem.toolsSeparator,
			ToolbarItem.toolsTabBar,
			ToolbarItem.back,
			ToolbarItem.forward,
			ToolbarItem.sidebarPlaceholder,
			ToolbarItem.sidebar,
			ToolbarItem.navigationSeparator,
			ToolbarItem.projectContext,
			ToolbarItem.conversationTitle,
			ToolbarItem.openProject,
			ToolbarItem.newChat,
			ToolbarItem.moreOptions,
			ToolbarItem.summary,
			ToolbarItem.summarySeparator,
			ToolbarItem.newTab,
			ToolbarItem.review,
			ToolbarItem.commandPalette,
			ToolbarItem.searchMessages,
			.flexibleSpace,
		]
	}

	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
	{
		[
			ToolbarItem.navigationControls,
			ToolbarItem.navigationSeparator,
			ToolbarItem.conversationTitle,
			.flexibleSpace,
			ToolbarItem.trailingControls,
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
		if itemIdentifier == ToolbarItem.toolsSeparator
		{
			return NSTrackingSeparatorToolbarItem(
				identifier: itemIdentifier,
				splitView: paneController.split.splitView,
				dividerIndex: 1
			)
		}
		let item = NSToolbarItem(itemIdentifier: itemIdentifier)
		switch itemIdentifier
		{
		case ToolbarItem.toolsTabBar:
			toolsToolbar.configureTabBarItem(
				item,
				paneController: paneController,
				inspector: inspector
			)
		case ToolbarItem.navigationControls:
			item.label = "Navigation"
			item.view = makeNavigationControls()
		case ToolbarItem.trailingControls:
			item.label = "Conversation controls"
			item.view = makeTrailingControls()
		case ToolbarItem.back:
			return makeDisabledToolbarItem(
				identifier: itemIdentifier,
				image: DesktopIcons.image(
					.arrowLeft,
					size: 16
				),
				label: "Back"
			)
		case ToolbarItem.forward:
			return makeDisabledToolbarItem(
				identifier: itemIdentifier,
				image: DesktopIcons.image(
					.arrowRight,
					size: 16
				),
				label: "Forward"
			)
		case ToolbarItem.sidebarPlaceholder:
			return makeDisabledToolbarItem(
				identifier: itemIdentifier,
				image: DesktopIcons.image(.sidebar),
				label: "Toggle sidebar"
			)
		case ToolbarItem.sidebar:
			item.label = "Toggle projects navigation"
			let button = makeToolbarButton(
				image: DesktopIcons.image(.sidebar),
				label: item.label
			)
			button.target = self
			button.action = #selector(toggleSidebar)
			item.view = button
		case ToolbarItem.projectContext:
			item.label = "Project context"
			item.view = makeProjectContextIcon()
		case ToolbarItem.conversationTitle:
			item.label = "Conversation"
			item.view = titleContainer
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
			item.view = summaryToggleButton
		case ToolbarItem.moreOptions:
			return makeDisabledToolbarItem(
				identifier: itemIdentifier,
				image: PinnedSummaryIcons.image(.ellipsis),
				label: "More options"
			)
		case ToolbarItem.summarySeparator:
			item.label = "Separator"
			item.view = ToolbarSeparatorView()
		case ToolbarItem.newTab:
			item.label = "New tab"
			item.view = toolsToolbar.openButton
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
		item.isBordered = false
		item.toolTip = item.label
		return item
	}

	private func makeProjectContextIcon() -> NSImageView
	{
		let imageView = NSImageView()
		imageView.image = DesktopIcons.image(
			.folder,
			size: 15
		)
		imageView.image?.size = NSSize(
			width: 15,
			height: 16
		)
		imageView.contentTintColor = .labelColor
		imageView.setAccessibilityLabel("Project context")
		imageView.widthAnchor.constraint(equalToConstant: ToolbarLayout.controlSize).isActive = true
		imageView.heightAnchor.constraint(equalToConstant: ToolbarLayout.controlSize)
			.isActive = true
		return imageView
	}

	private func makeNavigationControls() -> NSView
	{
		// Preserve the removed New chat control's space so other toolbar items stay fixed.
		let trailingSpace = NSView()
		trailingSpace.setAccessibilityElement(false)
		trailingSpace.widthAnchor.constraint(equalToConstant: ToolbarLayout.controlSize)
			.isActive = true
		trailingSpace.heightAnchor.constraint(equalToConstant: ToolbarLayout.controlSize)
			.isActive = true
		let sidebarButton = makeToolbarButton(
			image: DesktopIcons.image(.sidebar),
			label: "Toggle sidebar"
		)
		sidebarButton.target = self
		sidebarButton.action = #selector(toggleSidebar)
		return makeToolbarControlStack(
			[
				makeToolbarButton(
					image: DesktopIcons.image(
						.arrowLeftLg,
						size: 16
					),
					label: "Back",
					isEnabled: false
				),
				makeToolbarButton(
					image: DesktopIcons.image(
						.arrowRightLg,
						size: 16
					),
					label: "Forward",
					isEnabled: false
				),
				sidebarButton,
				trailingSpace,
			],
			leadingInset: -1,
			trailingInset: -2
		)
	}

	private func makeTrailingControls() -> NSView
	{
		makeToolbarControlStack(
			[
				makeToolbarButton(
					image: PinnedSummaryIcons.image(.ellipsis),
					label: "More options",
					isEnabled: false
				),
				summaryToggleButton,
				toolsToolbar.closedSeparator,
				toolsToolbar.openButton,
			],
			leadingInset: 3,
			trailingInset: -3
		)
	}

	func updateToolsToolbarControls(allowDuringExpansion: Bool = false)
	{
		guard let toolbar = window?.toolbar
		else
		{
			return
		}
		toolsToolbar.update(
			toolbar: toolbar,
			window: window,
			paneController: paneController,
			inspector: inspector,
			defaultIdentifiers: toolbarDefaultItemIdentifiers(toolbar),
			allowDuringExpansion: allowDuringExpansion
		)
	}

	func configureToolsPaneClosing()
	{
		paneController.onToolsExpansionLayoutChanged =
		{
			[weak self] in
			self?.updateToolsToolbarControls(allowDuringExpansion: true)
			self?.window?.layoutIfNeeded()
		}
		paneController.onToolsExpansionFinished =
		{
			[weak self] in
			self?.updateToolsToolbarControls()
			self?.presentPendingFileSearch()
		}
		inspector.toolsTabs.onToggleSummary =
		{
			[weak self] in self?.togglePinnedSummary()
		}
		inspector.toolsTabs.onToggleExpanded =
		{
			[weak self] in self?.toggleToolsExpanded()
		}
		inspector.toolsTabs.onOpenChanges =
		{
			[weak self] in self?.openChangesToolTab()
		}
		inspector.onToolChangesSelected =
		{
			[weak self] in self?.openCurrentChangesInToolTab()
		}
		inspector.onToolsClose =
		{
			[weak self] hasContent in
			guard let self
			else
			{
				return
			}
			self.paneController.setReviewCollapsed(!hasContent)
			self.updateToolsToolbarControls()
		}
	}

	@objc private func toggleToolsExpanded()
	{
		paneController.toggleToolsExpanded()
		updateToolsToolbarControls()
	}

	@objc private func toggleToolsPane()
	{
		configureToolsPaneClosing()
		if inspector.isShowingTools, !paneController.split.splitViewItems[2].isCollapsed
		{
			inspector.closeToolsPane()
		}
		else
		{
			paneController.openToolsPane()
		}
		updateToolsToolbarControls()
	}

	func openChangesToolTab(scope: GitComparisonScope? = nil)
	{
		configureToolsPaneClosing()
		if !inspector.isShowingTools || paneController.isReviewCollapsed
		{
			paneController.openToolsPane
			{
				openCurrentChangesInToolTab(scope: scope)
			}
		}
		else
		{
			openCurrentChangesInToolTab(scope: scope)
		}
		updateToolsToolbarControls()
	}

	private func makeToolbarControlStack(
		_ controls: [NSView],
		leadingInset: CGFloat,
		trailingInset: CGFloat
	) -> NSView
	{
		let stack = NSStackView(views: controls)
		stack.orientation = .horizontal
		stack.alignment = .centerY
		stack.spacing = ToolbarLayout.controlSpacing
		stack.setAccessibilityElement(false)
		stack.setContentHuggingPriority(
			.required,
			for: .horizontal
		)
		let host = NSView()
		host.setAccessibilityElement(false)
		stack.translatesAutoresizingMaskIntoConstraints = false
		host.addSubview(stack)
		NSLayoutConstraint.activate([
			host.heightAnchor.constraint(equalToConstant: ToolbarLayout.rowHeight),
			stack.heightAnchor.constraint(equalToConstant: ToolbarLayout.rowHeight),
			stack.leadingAnchor.constraint(
				equalTo: host.leadingAnchor,
				constant: leadingInset
			),
			stack.trailingAnchor.constraint(
				equalTo: host.trailingAnchor,
				constant: -trailingInset
			),
			stack.centerYAnchor.constraint(
				equalTo: host.centerYAnchor,
				constant: 2
			),
		])
		return host
	}

	private func makeDisabledToolbarItem(
		identifier: NSToolbarItem.Identifier,
		image: NSImage,
		label: String
	) -> NSToolbarItem
	{
		let item = NSToolbarItem(itemIdentifier: identifier)
		item.label = label
		item.toolTip = label
		item.view = makeToolbarButton(
			image: image,
			label: label,
			isEnabled: false
		)
		item.isBordered = false
		item.autovalidates = false
		item.isEnabled = false
		return item
	}

	private func makeToolbarButton(
		image: NSImage,
		label: String,
		isEnabled: Bool = true
	) -> NSButton
	{
		let button = DesktopHoverButton(
			title: "",
			target: nil,
			action: nil
		)
		button.bezelStyle = .inline
		button.isBordered = false
		button.image = image
		button.imagePosition = .imageOnly
		button.contentTintColor = AppKitColorTokens.secondaryText
		button.cornerRadius = ShapeTokens.Toolbar.controlRadius
		button.isEnabled = isEnabled
		button.toolTip = label
		button.setAccessibilityLabel(label)
		button.widthAnchor.constraint(equalToConstant: ToolbarLayout.controlSize).isActive = true
		button.heightAnchor.constraint(equalToConstant: ToolbarLayout.controlSize).isActive = true
		return button
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
		guard let window, window.attachedSheet == nil, let snapshot = latestSnapshot
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
				title: $0.displayTitle,
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
				detail: "Compare repository changes without editing Git state",
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
			guard let self, target.accepts(.search(""))
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
				guard target.accepts(.loadEarlierTurns)
				else
				{
					return
				}
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
