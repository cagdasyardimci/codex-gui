import AppKit

@MainActor
final class ToolsTabViewController: NSViewController
{
	private typealias Layout = LayoutTokens.Tabs
	private let metrics: LayoutTokens.TabContent

	init(metrics: LayoutTokens.TabContent = LayoutTokens.tabContent)
	{
		precondition(
			metrics.isValid,
			"Invalid tab metrics"
		)
		precondition(
			max(
				metrics.closeControlSize,
				metrics.moreControlSize
			) <= Layout.tabHeight,
			"Tab controls must fit within the tab height"
		)
		self.metrics = metrics
		super.init(
			nibName: nil,
			bundle: nil
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	private var minimumVisibleTabWidth: CGFloat
	{
		let ordinary = metrics.effectiveMinimum(for: .ordinary)
		guard isExpanded
		else
		{
			return ordinary
		}
		let conversation = metrics.effectiveMinimum(for: .conversation)
		return tabCount > 0 ? max(
			ordinary,
			conversation
		) : conversation
	}

	var onCloseLastTab: (() -> Void)?
	var onClosePane: (() -> Void)?
	var onToggleExpanded: (() -> Void)?
	var onToggleSummary: (() -> Void)?
	var onTabSelectionChange: (() -> Void)?
	var onOpenChanges: (() -> Void)?
	var onOpenFiles: (() -> Void)?
	var onFileSelected: ((UUID) -> Void)?
	var onFileCloseRequested: ((UUID) -> Void)?
	var onFileRetainRequested: ((UUID) -> Void)?
	var onFilesPresentationVisible: ((Bool) -> Void)?
	{
		didSet
		{
			onFilesPresentationVisible?(isContentVisible && isFilesSelected)
		}
	}
	var onChangesSelectionChange: (() -> Void)?
	var onChangesTabClosed: (() -> Void)?
	var onSourcesTabClosed: (() -> Void)?
	var onSubagentsTabClosed: (() -> Void)?
	private(set) var tabCount = 0
	private(set) var selectedTabID: UUID?
	private(set) var isConversationSelected = false
	private(set) var changesTabID: UUID?
	private(set) var sourcesTabID: UUID?
	private(set) var subagentsTabID: UUID?
	private(set) var filesLandingTabID: UUID?
	private(set) var fileTabPresentations: [FileToolTabPresentation] = []
	var selectedFileDocumentID: UUID?
	{
		guard !isConversationSelected, let selectedTabID,
				fileTabPresentations.contains(where:
				{
					$0.id == selectedTabID
				})
		else
		{
			return nil
		}
		return selectedTabID
	}
	var isFilesSelected: Bool
	{
		!isConversationSelected && (filesLandingTabID != nil &&
			selectedTabID == filesLandingTabID ||
			selectedFileDocumentID != nil)
	}
	var isChangesSelected: Bool
	{
		!isConversationSelected && selectedTabID == changesTabID && changesTabID != nil
	}
	var isSourcesSelected: Bool
	{
		!isConversationSelected && selectedTabID == sourcesTabID && sourcesTabID != nil
	}
	var isSubagentsSelected: Bool
	{
		!isConversationSelected && selectedTabID == subagentsTabID && subagentsTabID != nil
	}
	private var isExpanded = false
	private var isContentVisible = true
	private var wasFilesPresentationVisible = false
	private var conversationTitle = "New chat"
	private var tabIDs: [UUID] = []
	private let tabStack = NSStackView()
	private let contentHost = NSView()
	private var toolsContent: NSView?
	private var toolsTileSingleColumnConstraints: [NSLayoutConstraint] = []
	private var toolsTileTwoColumnConstraints: [NSLayoutConstraint] = []
	private weak var changesController: NSViewController?
	private weak var sourcesController: NSViewController?
	private weak var subagentsController: NSViewController?
	private weak var filesLandingController: NSViewController?
	private weak var fileDocumentController: NSViewController?
	private var lastFileSelectedID: UUID?
	private let dragOwner = UUID()
	private let sourcesHoverPreview = SourcesTabHoverPreview()
	private let tabScrollView = NSScrollView()
	private lazy var tabBar = makeTabHeader()
	private var tabLeadingConstraint: NSLayoutConstraint?
	private var headerTrailingConstraint: NSLayoutConstraint?
	private var headerControlsWidthConstraint: NSLayoutConstraint?
	private var preferredTabAreaWidth: NSLayoutConstraint?
	private var headerCenterConstraints: [NSLayoutConstraint] = []
	private var toolbarTabOffset: CGFloat = 0
	private var toolbarControlsOffset: CGFloat = 0
	private let controlsSeparator = ToolbarSeparatorView(constrained: false)
	private var expandButton: NSButton?
	private let summaryButton = PinnedSummaryToggleButton(
		title: "",
		target: nil,
		action: nil
	)

	var tabBarView: NSView
	{
		_ = view
		return tabBar
	}

	var minimumTabBarWidth: CGFloat
	{

		return minimumVisibleTabWidth + controlsWidth(expanded: !summaryButton.isHidden)
			+ Layout.addButtonSpacing + Layout.controlSize + Layout.controlSpacing
			+ Layout.headerLeadingInset + Layout.headerTrailingInset
	}

	func alignTabsWithPaneDivider(
		at x: CGFloat,
		expanded: Bool
	)
	{
		let inset = (expanded ? 0 : x) + Layout.headerLeadingInset
		if tabLeadingConstraint?.constant != inset
		{
			tabLeadingConstraint?.constant = inset
		}
	}

	func setToolbarVerticalOffsets(
		tabs: CGFloat,
		controls: CGFloat
	)
	{
		toolbarTabOffset = tabs
		toolbarControlsOffset = controls
		for (index, constraint) in headerCenterConstraints.enumerated()
		{
			constraint.constant = index < 2 ? tabs + LayoutTokens.TabControls
				.tabCenterBias : controls
		}
	}

	func setPaneWidth(_ width: CGFloat)
	{
		controlsSeparator.alphaValue = width <= LayoutTokens.TabControls
			.separatorVisibilityWidth ? 1 : 0
	}

	private static func addTabImage() -> NSImage
	{
		let canvasSize = Layout.iconSize
		let image = NSImage(
			size: NSSize(
				width: canvasSize,
				height: canvasSize
			),
			flipped: false
		)
		{
			_ in
			let path = NSBezierPath()
			path.lineWidth = 1.0508
			path.lineCapStyle = .round
			path.move(to: NSPoint(
				x: 8,
				y: 2.6665
			))
			path.line(to: NSPoint(
				x: 8,
				y: 13.3335
			))
			path.move(to: NSPoint(
				x: 2.6665,
				y: 8
			))
			path.line(to: NSPoint(
				x: 13.3335,
				y: 8
			))
			NSColor.black.setStroke()
			path.stroke()
			return true
		}
		image.isTemplate = true
		return image
	}

	static func paneIcon() -> NSImage
	{
		let image = DesktopIcons.image(
			.sidebarRight,
			size: Layout.paneIconSize.width
		)
		image.size = Layout.paneIconSize
		image.isTemplate = true
		return image
	}

	override func loadView()
	{
		let container = DesktopSurface(AppKitColorTokens.toolsCanvas)
		view = container

		_ = tabBar
		AppKitLayout.pin(
			contentHost,
			to: container,
			inset: 0
		)
		installToolsContent()
		renderTabs()
	}

	private func installToolsContent()
	{
		let toolsContent = makeToolsContent()
		self.toolsContent = toolsContent
		toolsContent.translatesAutoresizingMaskIntoConstraints = false
		contentHost.addSubview(toolsContent)
		let preferredWidth = toolsContent.widthAnchor.constraint(
			equalTo: contentHost.widthAnchor,
			constant: -2 * Layout.contentInset
		)
		preferredWidth.priority = NSLayoutConstraint.Priority(999)
		NSLayoutConstraint.activate([
			toolsContent.leadingAnchor.constraint(
				greaterThanOrEqualTo: contentHost.leadingAnchor,
				constant: Layout.contentInset
			),
			toolsContent.trailingAnchor.constraint(
				lessThanOrEqualTo: contentHost.trailingAnchor,
				constant: -Layout.contentInset
			),
			toolsContent.centerXAnchor.constraint(equalTo: contentHost.centerXAnchor),
			toolsContent.widthAnchor.constraint(
				lessThanOrEqualToConstant: Layout.toolsMaximumContentWidth
			),
			preferredWidth,
			toolsContent.topAnchor.constraint(
				equalTo: contentHost.topAnchor,
				constant: Layout.toolsTopInset
			),
		])
	}

	override func viewWillLayout()
	{
		super.viewWillLayout()
		let availableWidth = min(
			Layout.toolsMaximumContentWidth,
			max(
				0,
				view.bounds.width - 2 * Layout.contentInset
			)
		)
		let twoColumns = availableWidth >= Layout.toolsTwoColumnMinimumWidth
		guard toolsTileTwoColumnConstraints.first?.isActive != twoColumns
		else
		{
			return
		}
		NSLayoutConstraint.deactivate(toolsTileSingleColumnConstraints)
		NSLayoutConstraint.deactivate(toolsTileTwoColumnConstraints)
		NSLayoutConstraint.activate(
			twoColumns ? toolsTileTwoColumnConstraints : toolsTileSingleColumnConstraints
		)
	}

	func showChanges(_ controller: NSViewController)
	{
		guard selectedTabID != nil
		else
		{
			return
		}
		let selectionChanged = !isChangesSelected
		changesTabID = selectFeatureTab(changesTabID)
		_ = view
		installController(
			controller,
			replacing: changesController
		)
		changesController = controller
		renderTabs()
		if selectionChanged
		{
			onTabSelectionChange?()
		}
	}

	func detachChanges()
	{
		guard let changesController, changesController.parent === self
		else
		{
			return
		}
		changesController.view.removeFromSuperview()
		changesController.removeFromParent()
		showSelectedContent()
	}

	func showSources(_ controller: NSViewController)
	{
		sourcesTabID = selectFeatureTab(sourcesTabID)
		_ = view
		installController(
			controller,
			replacing: sourcesController
		)
		sourcesController = controller
		renderTabs()
		onTabSelectionChange?()
		onChangesSelectionChange?()
	}

	func detachSources()
	{
		sourcesHoverPreview.dismiss()
		detachController(sourcesController)
		showSelectedContent()
	}

	func removeSourcesTab()
	{
		removeFeatureTab(sourcesTabID)
	}

	func showSubagents(_ controller: NSViewController)
	{
		subagentsTabID = selectFeatureTab(subagentsTabID)
		_ = view
		installController(
			controller,
			replacing: subagentsController
		)
		subagentsController = controller
		renderTabs()
		onTabSelectionChange?()
		onChangesSelectionChange?()
	}

	func detachSubagents()
	{
		detachController(subagentsController)
		showSelectedContent()
	}

	func removeSubagentsTab()
	{
		removeFeatureTab(subagentsTabID)
	}

	func showFilesLanding(_ controller: NSViewController)
	{
		_ = view
		if !fileTabPresentations.isEmpty
		{
			let target = lastFileSelectedID.flatMap
			{
				id in fileTabPresentations.contains(where:
					{
						$0.id == id
					}) ? id : nil
			} ?? fileTabPresentations[0].id
			selectedTabID = target
			isConversationSelected = false
			lastFileSelectedID = target
			renderTabs()
			onFileSelected?(target)
			onTabSelectionChange?()
			onChangesSelectionChange?()
			return
		}
		filesLandingTabID = selectFeatureTab(filesLandingTabID)
		installController(
			controller,
			replacing: filesLandingController
		)
		filesLandingController = controller
		renderTabs()
		onTabSelectionChange?()
		onChangesSelectionChange?()
	}

	/// Applies a complete runtime snapshot without stealing another tool's focus.
	func updateFileTabs(
		presentations: [FileToolTabPresentation],
		selectedID: UUID?,
		controller: NSViewController
	)
	{
		let wasFilesSelected = isFilesSelected
		let previousSelectedID = selectedTabID
		let previousTabIDs = tabIDs
		let previousSelectedIndex = previousSelectedID.flatMap
		{
			tabIDs.firstIndex(of: $0)
		}
		let hadTabs = !tabIDs.isEmpty
		let oldFileIDs = Set(fileTabPresentations.map(\.id))
		let newFileIDs = Set(presentations.map(\.id))
		let selectedDocumentWasRemoved = previousSelectedID.map
		{
			oldFileIDs.contains($0) && !newFileIDs.contains($0)
		} ?? false
		let selectedWasCleanPreview = fileTabPresentations.contains
		{
			$0.id == previousSelectedID && $0.isPreview && !$0.isDirty
		}
		let selectedIDIsNew = selectedID.map
		{
			newFileIDs.contains($0) && !oldFileIDs.contains($0)
		} ?? false
		let closedSelectedDocument = selectedDocumentWasRemoved &&
			!(selectedWasCleanPreview && selectedIDIsNew)
		let removedIndices = tabIDs.enumerated().compactMap
		{
			index, id in oldFileIDs.contains(id) && !newFileIDs.contains(id) ? index : nil
		}
		let replacementIndex = removedIndices.first
		let landingIndex = filesLandingTabID.flatMap
		{
			tabIDs.firstIndex(of: $0)
		}
		tabIDs.removeAll
		{
			oldFileIDs.contains($0) && !newFileIDs.contains($0)
		}
		if let landing = filesLandingTabID, !presentations.isEmpty
		{
			if let index = tabIDs.firstIndex(of: landing)
			{
				tabIDs.remove(at: index)
			}
			filesLandingTabID = nil
			detachController(filesLandingController)
		}
		var nextReplacementIndex = replacementIndex ?? landingIndex
		for presentation in presentations where !tabIDs.contains(presentation.id)
		{
			let index: Int
			if let nextReplacementIndex
			{
				index = min(
					nextReplacementIndex,
					tabIDs.count
				)
			}
			else if let existingIndex = tabIDs.lastIndex(where:
				{
					newFileIDs.contains($0)
				})
			{
				index = existingIndex + 1
			}
			else
			{
				index = tabIDs.count
			}
			tabIDs.insert(
				presentation.id,
				at: index
			)
			if nextReplacementIndex != nil
			{
				nextReplacementIndex = index + 1
			}
		}
		fileTabPresentations = presentations
		tabCount = tabIDs.count
		if !presentations.isEmpty
		{
			_ = view
			installController(
				controller,
				replacing: fileDocumentController
			)
			fileDocumentController = controller
		}
		else
		{
			detachController(fileDocumentController)
			fileDocumentController = nil
		}
		if wasFilesSelected || !hadTabs
		{
			let adjacentID: UUID? = if let previousSelectedIndex
			{
				previousTabIDs.suffix(from: previousSelectedIndex + 1).first
				{
					tabIDs.contains($0)
				} ?? previousTabIDs.prefix(previousSelectedIndex).reversed().first
				{
					tabIDs.contains($0)
				}
			}
			else
			{
				nil
			}
			let runtimeSelectedID = selectedID.flatMap
			{
				newFileIDs.contains($0) ? $0 : nil
			}
			let survivingSelection = previousSelectedID.flatMap
			{
				tabIDs.contains($0) ? $0 : nil
			}
			selectedTabID = (closedSelectedDocument ? adjacentID : runtimeSelectedID)
				?? survivingSelection ?? adjacentID ?? presentations.first?.id
			if selectedTabID == nil, !tabIDs.isEmpty
			{
				selectedTabID = tabIDs[min(
					replacementIndex ?? 0,
					tabIDs.count - 1
				)]
			}
			lastFileSelectedID = selectedFileDocumentID
		}
		else if let previousSelectedID, !tabIDs.contains(previousSelectedID)
		{
			selectedTabID = tabIDs.first
		}
		renderTabs()
		if wasFilesSelected && closedSelectedDocument, let selectedFileDocumentID
		{
			onFileSelected?(selectedFileDocumentID)
		}
		if hadTabs && tabIDs.isEmpty
		{
			onCloseLastTab?()
		}
		else if wasFilesSelected && previousSelectedID != selectedTabID
		{
			onTabSelectionChange?()
			onChangesSelectionChange?()
		}
	}

	private func selectFeatureTab(_ existingTabID: UUID?) -> UUID
	{
		let occupiedTabIDs = [changesTabID,
								sourcesTabID,
								subagentsTabID,
								filesLandingTabID].compactMap
		{
			$0
		} + fileTabPresentations.map(\.id)
		let tabID: UUID
		if let existingTabID
		{
			tabID = existingTabID
		}
		else if !isConversationSelected, let selectedTabID,
				!occupiedTabIDs.contains(selectedTabID)
		{
			tabID = selectedTabID
		}
		else
		{
			tabID = UUID()
			tabIDs.append(tabID)
			tabCount = tabIDs.count
		}
		selectedTabID = tabID
		isConversationSelected = false
		return tabID
	}

	private func installController(
		_ controller: NSViewController,
		replacing previousController: NSViewController?
	)
	{
		if previousController !== controller
		{
			detachController(previousController)
		}
		guard controller.parent !== self
		else
		{
			return
		}
		controller.view.removeFromSuperview()
		controller.removeFromParent()
		addChild(controller)
		AppKitLayout.pin(
			controller.view,
			to: contentHost,
			inset: 0
		)
	}

	private func detachController(_ controller: NSViewController?)
	{
		guard let controller, controller.parent === self
		else
		{
			return
		}
		(controller as? SubagentsViewController)?.setPresentationVisible(false)
		controller.view.removeFromSuperview()
		controller.removeFromParent()
	}

	private func removeFeatureTab(_ tabID: UUID?)
	{
		guard let tabID, let index = tabIDs.firstIndex(of: tabID)
		else
		{
			return
		}
		removeTab(at: index)
	}

	func openNewTab()
	{
		let wasShowingConversation = isConversationSelected
		let wasShowingFeature = isSourcesSelected || isSubagentsSelected
		isConversationSelected = false
		let tabID = UUID()
		tabIDs.append(tabID)
		tabCount = tabIDs.count
		selectedTabID = tabID

		_ = view
		renderTabs()
		onChangesSelectionChange?()
		if wasShowingConversation || wasShowingFeature
		{
			onTabSelectionChange?()
		}
	}

	func setConversationTitle(_ title: String)
	{
		guard conversationTitle != title
		else
		{
			return
		}
		conversationTitle = title
		if isExpanded
		{
			renderTabs()
		}
	}

	func setExpanded(_ expanded: Bool)
	{
		_ = view
		isExpanded = expanded
		if !expanded
		{
			isConversationSelected = false
		}
		summaryButton.isHidden = !expanded
		headerTrailingConstraint?.constant = -Layout.headerTrailingInset
		headerControlsWidthConstraint?.constant = controlsWidth(expanded: expanded)
		let label = expanded ? "Restore split view" : "Expand tab pane"
		expandButton?.image = DesktopIcons.image(
			expanded ? .collapseSmall : .expand,
			size: Layout.iconSize
		)
		expandButton?.toolTip = label
		expandButton?.setAccessibilityLabel(label)
		renderTabs()
		if !expanded && isChangesSelected
		{
			onChangesSelectionChange?()
		}
	}

	func setSummaryVisible(_ visible: Bool)
	{
		summaryButton.state = visible ? .on : .off
		summaryButton.setAccessibilityValue(visible ? "Visible" : "Hidden")
	}

	func setContentVisible(_ visible: Bool)
	{
		isContentVisible = visible
		showSelectedContent()
	}

	private func configureSummaryButton()
	{
		AppKitControlStyling.styleButton(summaryButton)
		summaryButton.image = PinnedSummaryIcons.image(.toggle)
		summaryButton.imagePosition = .imageOnly
		summaryButton.setButtonType(.toggle)
		summaryButton.target = self
		summaryButton.action = #selector(toggleSummary)
		summaryButton.toolTip = "Toggle pinned summary"
		summaryButton.setAccessibilityLabel("Toggle pinned summary")
		summaryButton.widthAnchor.constraint(equalToConstant: Layout.controlSize).isActive = true
		summaryButton.heightAnchor.constraint(equalToConstant: Layout.controlSize).isActive = true
		summaryButton.isHidden = true
	}

	private func makeTabHeader() -> NSView
	{
		let header = NSView()
		configureTabScrollView()
		configureSummaryButton()
		let addButton = makeIconButton(
			image: Self.addTabImage(),
			label: "Add tab",
			action: #selector(addTab)
		)
		let expandButton = makeIconButton(
			.expand,
			label: "Expand tab pane",
			action: #selector(toggleExpanded)
		)
		self.expandButton = expandButton
		let closePaneButton = makeIconButton(
			image: Self.paneIcon(),
			label: "Close tab pane",
			action: #selector(closePane)
		)

		let controls = AppKitLayout.horizontalStack(
			[controlsSeparator, summaryButton, expandButton, closePaneButton],
			spacing: Layout.controlSpacing
		)
		let controlsWidth = controls.widthAnchor.constraint(
			equalToConstant: controlsWidth(expanded: false)
		)
		// NSStackView may defer removing the hidden summary button's constraints.
		// Keep button sizes and spacing valid until its visibility update completes.
		controlsWidth.priority = NSLayoutConstraint.Priority(999)
		headerControlsWidthConstraint = controlsWidth
		let preferredWidth = tabScrollView.widthAnchor.constraint(equalToConstant: 0)
		preferredWidth.priority = NSLayoutConstraint.Priority(998)
		preferredTabAreaWidth = preferredWidth
		for child in [tabScrollView, addButton, controls]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			header.addSubview(child)
		}
		let trailingConstraint = controls.trailingAnchor.constraint(
			equalTo: header.trailingAnchor,
			constant: -Layout.headerTrailingInset
		)
		headerTrailingConstraint = trailingConstraint
		let leadingConstraint = tabScrollView.leadingAnchor.constraint(
			equalTo: header.leadingAnchor,
			constant: Layout.headerLeadingInset
		)
		// Divider alignment can lag behind the header width during pane transitions.
		leadingConstraint.priority = NSLayoutConstraint.Priority(999)
		tabLeadingConstraint = leadingConstraint
		headerCenterConstraints = [
			tabScrollView.centerYAnchor.constraint(
				equalTo: header.centerYAnchor,
				constant: toolbarTabOffset + LayoutTokens.TabControls.tabCenterBias
			),
			addButton.centerYAnchor.constraint(
				equalTo: header.centerYAnchor,
				constant: toolbarTabOffset + LayoutTokens.TabControls.tabCenterBias
			),
			controls.centerYAnchor.constraint(
				equalTo: header.centerYAnchor,
				constant: toolbarControlsOffset
			),
		]
		NSLayoutConstraint.activate(headerCenterConstraints)
		NSLayoutConstraint.activate([
			header.heightAnchor.constraint(equalToConstant: Layout.headerHeight),
			controlsWidth,
			preferredWidth,
			controlsSeparator.widthAnchor.constraint(equalToConstant: Layout.separatorWidth),
			controlsSeparator.heightAnchor.constraint(equalToConstant: Layout.separatorHeight),
			tabScrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.controlSize),
			tabScrollView.leadingAnchor.constraint(greaterThanOrEqualTo: header.leadingAnchor),
			leadingConstraint,
			tabScrollView.heightAnchor.constraint(equalToConstant: Layout.tabHeight),
			tabScrollView.trailingAnchor.constraint(
				equalTo: addButton.leadingAnchor,
				constant: -Layout.addButtonSpacing
			),
			addButton.trailingAnchor.constraint(
				lessThanOrEqualTo: controls.leadingAnchor,
				constant: -Layout.controlSpacing
			),
			trailingConstraint,
		])
		return header
	}

	private func controlsWidth(expanded: Bool) -> CGFloat
	{
		let count: CGFloat = expanded ? 3 : 2
		return Layout.separatorWidth + count * (Layout.controlSize + Layout.controlSpacing)
	}

	private func configureTabScrollView()
	{
		tabStack.orientation = .horizontal
		tabStack.alignment = .centerY
		tabStack.spacing = Layout.tabSpacing
		tabStack.translatesAutoresizingMaskIntoConstraints = false

		tabScrollView.drawsBackground = false
		// A legacy scroller would consume 17 points of this fixed-height tab strip.
		// Wheel scrolling and revealing the selected tab still use the clip view.
		tabScrollView.hasHorizontalScroller = false
		tabScrollView.hasVerticalScroller = false
		tabScrollView.horizontalScrollElasticity = .allowed
		tabScrollView.documentView = tabStack
		tabStack.heightAnchor.constraint(equalTo: tabScrollView.contentView.heightAnchor)
			.isActive = true
		tabScrollView.setAccessibilityLabel("Tools tabs")
	}

	private func makeToolsContent() -> NSStackView
	{
		let heading = ToolsHeadingTextField(labelWithString: "Tools")
		heading.font = AppKitFontResolver.font(TypographyTokens.Controls.toolsHeading)
		heading.textColor = AppKitColorTokens.primaryText
		let changesTile = makeToolTile(
			title: "Changes",
			image: ToolsPaneIcons.changes(size: Layout.toolTileIconSize),
			shortcut: ToolsChangesShortcut.label,
			key: ToolsChangesShortcut.key,
			modifiers: ToolsChangesShortcut.modifiers,
			action: #selector(openChanges)
		)
		let filesTile = makeToolTile(
			title: "Files",
			image: ToolsPaneIcons.files(size: Layout.toolTileIconSize),
			shortcut: "⌘P",
			key: "p",
			modifiers: [.command],
			action: #selector(openFiles)
		)
		let tiles = NSView()
		changesTile.translatesAutoresizingMaskIntoConstraints = false
		filesTile.translatesAutoresizingMaskIntoConstraints = false
		tiles.addSubview(changesTile)
		tiles.addSubview(filesTile)
		NSLayoutConstraint.activate([
			changesTile.leadingAnchor.constraint(equalTo: tiles.leadingAnchor),
			changesTile.topAnchor.constraint(equalTo: tiles.topAnchor),
		])
		toolsTileSingleColumnConstraints = [
			changesTile.trailingAnchor.constraint(equalTo: tiles.trailingAnchor),
			filesTile.leadingAnchor.constraint(equalTo: tiles.leadingAnchor),
			filesTile.trailingAnchor.constraint(equalTo: tiles.trailingAnchor),
			filesTile.topAnchor.constraint(
				equalTo: changesTile.bottomAnchor,
				constant: 8
			),
			filesTile.bottomAnchor.constraint(equalTo: tiles.bottomAnchor),
		]
		toolsTileTwoColumnConstraints = [
			changesTile.widthAnchor.constraint(equalTo: filesTile.widthAnchor),
			filesTile.leadingAnchor.constraint(
				equalTo: changesTile.trailingAnchor,
				constant: Layout.toolColumnSpacing
			),
			filesTile.trailingAnchor.constraint(equalTo: tiles.trailingAnchor),
			filesTile.topAnchor.constraint(equalTo: tiles.topAnchor),
			filesTile.bottomAnchor.constraint(equalTo: tiles.bottomAnchor),
			changesTile.bottomAnchor.constraint(equalTo: tiles.bottomAnchor),
		]
		NSLayoutConstraint.activate(toolsTileSingleColumnConstraints)
		let content = AppKitLayout.verticalStack(
			[heading, tiles],
			spacing: Layout.toolsSectionGap
		)
		tiles.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
		return content
	}

	private func makeToolTile(
		title: String,
		image: NSImage,
		shortcut: String,
		key: String,
		modifiers: NSEvent.ModifierFlags,
		action: Selector
	) -> NSView
	{
		let tile = NSView()
		let button = ToolsTileButton(
			title: title,
			target: nil,
			action: nil
		)
		button.cell = ToolsTileButtonCell(
			textCell: title,
			shortcut: shortcut
		)
		AppKitControlStyling.styleButton(button)
		button.cornerRadius = ShapeTokens.TabControls.toolTileRadius
		button.font = AppKitFontResolver.font(TypographyTokens.Controls.toolsTile)
		button.contentTintColor = AppKitColorTokens.primaryText

		button.alignment = .left
		button.image = image
		button.imagePosition = .imageLeading
		button.target = self
		button.action = action
		button.keyEquivalent = key
		button.keyEquivalentModifierMask = modifiers
		button.setAccessibilityLabel(title)
		AppKitLayout.pin(
			button,
			to: tile,
			inset: 0
		)
		tile.heightAnchor.constraint(equalToConstant: Layout.toolTileHeight).isActive = true
		return tile
	}

	private func renderTabs()
	{
		let restoreTabFocus = tabBar.window?.firstResponder is ToolsTabSelectionButton
		showSelectedContent()
		let visibleTabCount = tabCount + (isExpanded ? 1 : 0)
		preferredTabAreaWidth?.constant = CGFloat(visibleTabCount) * metrics.maximumWidth
			+ CGFloat(max(
				0,
				visibleTabCount - 1
			)) * Layout.tabSpacing

		let selectedTab = rebuildTabViews()
		revealSelectedTab(selectedTab)
		if restoreTabFocus,
			let selectedButton = selectedTab?.subviews.compactMap(
			{
				$0 as? ToolsTabSelectionButton
			}
			)
			.first
		{
			tabBar.window?.makeFirstResponder(selectedButton)
		}
	}

	private func rebuildTabViews() -> NSView?
	{
		sourcesHoverPreview.dismiss()
		for tab in tabStack.arrangedSubviews
		{
			tabStack.removeArrangedSubview(tab)
			tab.removeFromSuperview()
		}
		let visibleTabCount = tabCount + (isExpanded ? 1 : 0)
		var selectedTab: NSView?
		if isExpanded
		{
			let tab = makeConversationTab()
			addTabView(
				tab,
				visibleTabCount: visibleTabCount
			)
			if isConversationSelected
			{
				selectedTab = tab
			}
		}
		for (index, tabID) in tabIDs.enumerated()
		{
			let selected = !isConversationSelected && tabID == selectedTabID
			let tab = makeTab(
				at: index,
				id: tabID,
				selected: selected
			)
			addTabView(
				tab,
				visibleTabCount: visibleTabCount
			)
			if selected
			{
				selectedTab = tab
			}
		}
		return selectedTab
	}

	private func revealSelectedTab(_ selectedTab: NSView?)
	{
		if tabBar.superview != nil, tabBar.bounds.width > 0
		{
			tabBar.layoutSubtreeIfNeeded()
			if let selectedTab
			{
				tabStack.scrollToVisible(selectedTab.frame)
			}
		}
	}

	private func showSelectedContent()
	{
		toolsContent?.isHidden = isChangesSelected || isSourcesSelected ||
			isSubagentsSelected || isConversationSelected || isFilesSelected
		if let changesController, changesController.parent === self
		{
			changesController.view.isHidden = !isChangesSelected
		}
		if let subagentsController, subagentsController.parent === self
		{
			subagentsController.view.isHidden = !isSubagentsSelected
			(subagentsController as? SubagentsViewController)?
				.setPresentationVisible(isContentVisible && isSubagentsSelected)
		}

		if let sourcesController, sourcesController.parent === self
		{
			sourcesController.view.isHidden = !isSourcesSelected
			if isSourcesSelected
			{
				(sourcesController as? ConversationSourcesViewController)?.prepareForDisplay()
			}
		}
		if let filesLandingController, filesLandingController.parent === self
		{
			filesLandingController.view.isHidden = !isFilesSelected ||
				selectedFileDocumentID != nil
		}
		if let fileDocumentController, fileDocumentController.parent === self
		{
			fileDocumentController.view.isHidden = selectedFileDocumentID == nil
		}
		let filesVisible = isContentVisible && isFilesSelected
		if filesVisible != wasFilesPresentationVisible
		{
			wasFilesPresentationVisible = filesVisible
			onFilesPresentationVisible?(filesVisible)
		}
	}

	private func addTabView(
		_ tab: NSView,
		visibleTabCount: Int
	)
	{
		tabStack.addArrangedSubview(tab)
		let availableWidth = tab.widthAnchor.constraint(
			equalTo: tabScrollView.contentView.widthAnchor,
			multiplier: 1 / CGFloat(visibleTabCount),
			constant: -Layout.tabSpacing * CGFloat(visibleTabCount - 1)
				/ CGFloat(visibleTabCount)
		)
		availableWidth.priority = .defaultHigh
		NSLayoutConstraint.activate([
			availableWidth,
			tab.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumVisibleTabWidth),
			tab.widthAnchor.constraint(lessThanOrEqualToConstant: metrics.maximumWidth),
		])
	}

	private func makeConversationTab() -> NSView
	{
		let selectButton = ToolsTabSelectionButton(
			title: conversationTitle,
			target: self,
			action: #selector(selectConversation)
		)
		selectButton.cell = ToolsTabSelectionButtonCell(textCell: conversationTitle)
		selectButton.target = self
		selectButton.action = #selector(selectConversation)
		AppKitControlStyling.styleButton(
			selectButton,
			prominent: isConversationSelected
		)
		selectButton.image = DesktopIcons.image(.chat)
		selectButton.imagePosition = .imageLeading
		selectButton.alignment = .left
		selectButton.font = AppKitFontResolver.font(TypographyTokens.Controls.tab)
		selectButton.cell?.lineBreakMode = .byTruncatingTail
		selectButton.toolTip = conversationTitle
		selectButton.setAccessibilityLabel("Chat: " + conversationTitle)
		selectButton.setAccessibilityValue(isConversationSelected ? "Selected" : "Not selected")
		selectButton.onNavigate =
		{
			[weak self] keyCode in
			self?.navigateTabs(
				from: nil,
				keyCode: keyCode
			) ?? false
		}
		let moreButton = makeIconButton(
			.dotsHorizontal,
			size: metrics.moreControlSize,
			label: "Chat options",
			action: nil
		)
		moreButton.isEnabled = false
		return makeTabSurface(
			selectButton,
			trailingButton: moreButton,
			selected: isConversationSelected
		)
	}

	private func makeTab(
		at index: Int,
		id: UUID,
		selected: Bool
	) -> NSView
	{
		let isChanges = id == changesTabID
		let isSources = id == sourcesTabID
		let isSubagents = id == subagentsTabID
		let isFilesLanding = id == filesLandingTabID
		let file = fileTabPresentations.first
		{
			$0.id == id
		}
		let title = isChanges ? "Changes" :
			isSources ? "Sources" : isSubagents ? "Subagents" :
			isFilesLanding ? "Files" : file?.title ?? "New tab"
		let displayTitle = file?.isDirty == true ? title + " •" : title
		let selectButton = ToolsTabSelectionButton(
			title: displayTitle,
			target: self,
			action: #selector(selectTab(_:))
		)
		let selectionCell = ToolsTabSelectionButtonCell(textCell: displayTitle)
		selectionCell.documentTitleGap = file == nil ? 0 : 5
		selectButton.cell = selectionCell
		selectButton.target = self
		selectButton.action = #selector(selectTab(_:))
		AppKitControlStyling.styleButton(
			selectButton,
			prominent: selected
		)
		selectButton.alignment = .left
		if isChanges
		{
			selectButton.image = ToolsPaneIcons.changes(size: Layout.iconSize)
			selectButton.imagePosition = .imageLeading
		}
		else if isSources
		{
			selectButton.image = DesktopIcons.image(
				.addSources,
				size: Layout.iconSize
			)
			selectButton.imagePosition = .imageLeading
		}
		else if isSubagents
		{
			selectButton.image = NSImage(
				systemSymbolName: "person.2",
				accessibilityDescription: "Subagents"
			)
			selectButton.imagePosition = .imageLeading
		}
		else if isFilesLanding
		{
			selectButton.image = ToolsPaneIcons.files(size: Layout.iconSize)
			selectButton.imagePosition = .imageLeading
		}
		else if let file
		{
			let type = WorkspaceFileTypePresentation(relativePath: file.path)
			if type.symbol == "swift" || WorkspaceFileIcon.asset(
				for: type,
				relativePath: file.path
			) == .fileCode
			{
				selectButton.image = DesktopIcons.image(
					.code,
					size: Layout.iconSize,
					accessibilityDescription: type.description
				)
			}
			else
			{
				selectButton.image = WorkspaceFileIcon.image(
					for: type,
					relativePath: file.path,
					size: Layout.iconSize
				)
			}
			selectButton.imagePosition = .imageLeading
		}

		selectButton.font = AppKitFontResolver.font(
			TypographyTokens.Controls.tab,
			italic: file?.isPreview == true
		)

		if let file
		{
			selectButton.toolTip = file.path
		}
		selectButton.tag = index
		selectButton.setAccessibilityLabel("\(title) \(index + 1)")
		selectButton.setAccessibilityValue(selected ? "Selected" : "Not selected")
		selectButton.draggedID = id
		selectButton.dragOwner = dragOwner
		if file?.isPreview == true
		{
			selectButton.onDoubleClick =
			{
				[weak self] in
				self?.onFileRetainRequested?(id)
			}
		}
		selectButton.onNavigate =
		{
			[weak self] keyCode in
			self?.navigateTabs(
				from: id,
				keyCode: keyCode
			) ?? false
		}
		let closeButton = makeIconButton(
			.x,
			size: metrics.closeControlSize,
			role: .close,
			imageSize: Layout.closeIconSize,
			label: "Close tab \(index + 1)",
			action: #selector(closeTab(_:))
		)
		closeButton.tag = index
		let tab = makeTabSurface(
			selectButton,
			trailingButton: closeButton,
			selected: selected
		)
		if let surface = tab as? ToolsTabSurface
		{
			surface.dragOwner = dragOwner
			surface.menu = makeTabMenu(
				for: id,
				at: index
			)
			selectButton.menu = surface.menu
			closeButton.menu = surface.menu
			surface.onDrop =
			{
				[weak self] draggedID, before in
				self?.moveTab(
					draggedID,
					nextTo: id,
					before: before
				)
			}
			if file != nil && !selected
			{
				closeButton.alphaValue = 0
				surface.onHoverChange =
				{
					hovered in
					closeButton.alphaValue = hovered ? 1 : 0
				}
			}
		}
		if isSources, let surface = tab as? ToolsTabSurface
		{
			surface.onHoverChange =
			{
				[weak self, weak surface] hovered in
				guard let self
				else
				{
					return
				}
				if hovered, let surface,
					let controller = self.sourcesController as? ConversationSourcesViewController,
					controller.parent === self
				{
					self.sourcesHoverPreview.show(
						sources: controller.sources,
						below: surface
					)
				}
				else
				{
					self.sourcesHoverPreview.dismiss()
				}
			}
		}
		return tab
	}

	private func makeTabSurface(
		_ selectButton: NSButton,
		trailingButton: NSButton,
		selected: Bool
	) -> NSView
	{
		selectButton.contentTintColor = selected ? AppKitColorTokens.primaryText : AppKitColorTokens
			.secondaryText
		let tab = ToolsTabSurface(isSelected: selected)
		for child in [selectButton, trailingButton]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			tab.addSubview(child)
		}

		NSLayoutConstraint.activate([
			tab.heightAnchor.constraint(equalToConstant: Layout.tabHeight),
			selectButton.leadingAnchor.constraint(
				equalTo: tab.leadingAnchor,
				constant: metrics.leadingInset
			),
			selectButton.topAnchor.constraint(equalTo: tab.topAnchor),
			selectButton.bottomAnchor.constraint(equalTo: tab.bottomAnchor),
			selectButton.trailingAnchor.constraint(equalTo: trailingButton.leadingAnchor),
			trailingButton.centerYAnchor.constraint(equalTo: tab.centerYAnchor),
			trailingButton.trailingAnchor.constraint(
				equalTo: tab.trailingAnchor,
				constant: -metrics.trailingInset
			),
		])
		return tab
	}

	private func makeTabMenu(
		for id: UUID,
		at _: Int
	) -> NSMenu
	{
		let menu = NSMenu()
		for (title, action) in [
			("Close", #selector(closeMenuTab(_:))),
			("Close Others", #selector(closeOtherMenuTabs(_:))),
			("Close to Right", #selector(closeRightMenuTabs(_:))),
		]
		{
			let item = NSMenuItem(
				title: title,
				action: action,
				keyEquivalent: ""
			)
			item.target = self
			item.representedObject = id
			menu.addItem(item)
		}
		if fileTabPresentations.contains(where:
			{
				$0.id == id && $0.isPreview
			})
		{
			menu.addItem(.separator())
			let item = NSMenuItem(
				title: "Keep Open",
				action: #selector(retainMenuFile(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.representedObject = id
			menu.addItem(item)
		}
		return menu
	}

	@objc private func closeMenuTab(_ sender: NSMenuItem)
	{
		guard let id = sender.representedObject as? UUID
		else
		{
			return
		}
		closeTabID(id)
	}

	@objc private func closeOtherMenuTabs(_ sender: NSMenuItem)
	{
		guard let id = sender.representedObject as? UUID
		else
		{
			return
		}
		for other in tabIDs.filter(
			{
				$0 != id
			}
		)
		{
			closeTabID(other)
		}
	}

	@objc private func closeRightMenuTabs(_ sender: NSMenuItem)
	{
		guard let id = sender.representedObject as? UUID,
				let index = tabIDs.firstIndex(of: id)
		else
		{
			return
		}
		for other in Array(tabIDs.suffix(from: index + 1))
		{
			closeTabID(other)
		}
	}

	@objc private func retainMenuFile(_ sender: NSMenuItem)
	{
		guard let id = sender.representedObject as? UUID,
				fileTabPresentations.contains(where:
				{
					$0.id == id && $0.isPreview
				})
		else
		{
			return
		}
		onFileRetainRequested?(id)
	}

	private func closeTabID(_ id: UUID)
	{
		guard let index = tabIDs.firstIndex(of: id)
		else
		{
			return
		}
		removeTab(at: index)
	}

	private func moveTab(
		_ id: UUID,
		nextTo destination: UUID,
		before: Bool
	)
	{
		guard id != destination, let sourceIndex = tabIDs.firstIndex(of: id),
				tabIDs.contains(destination)
		else
		{
			return
		}
		tabIDs.remove(at: sourceIndex)
		guard let targetIndex = tabIDs.firstIndex(of: destination)
		else
		{
			return
		}
		tabIDs.insert(
			id,
			at: targetIndex + (before ? 0 : 1)
		)
		renderTabs()
	}

	private func makeIconButton(
		_ icon: DesktopIcon,
		size: CGFloat = Layout.controlSize,
		role: ShapeTokens.TabControls.Role = .standard,
		imageSize: CGFloat = Layout.iconSize,
		label: String,
		action: Selector?
	) -> NSButton
	{
		makeIconButton(
			image: DesktopIcons.image(
				icon,
				size: imageSize
			),
			size: size,
			role: role,
			label: label,
			action: action
		)
	}

	private func makeIconButton(
		image: NSImage,
		size: CGFloat = Layout.controlSize,
		role: ShapeTokens.TabControls.Role = .standard,
		label: String,
		action: Selector?
	) -> NSButton
	{
		let button = DesktopHoverButton(
			title: "",
			target: self,
			action: action
		)
		AppKitControlStyling.styleButton(button)
		button.image = image
		button.imagePosition = .imageOnly
		button.toolTip = label
		button.setAccessibilityLabel(label)
		button.cornerRadius = ShapeTokens.TabControls.radius(for: role)
		button.cornerCurve = ShapeTokens.TabControls.cornerCurve
		button.contentTintColor = AppKitColorTokens.secondaryText
		button.widthAnchor.constraint(equalToConstant: size).isActive = true
		button.heightAnchor.constraint(equalToConstant: size).isActive = true
		return button
	}

	@objc private func addTab()
	{
		openNewTab()
	}

	@objc private func openChanges()
	{
		onOpenChanges?()
	}

	@objc private func openFiles()
	{
		onOpenFiles?()
	}

	@objc private func closePane()
	{
		onClosePane?()
	}

	@objc private func toggleSummary()
	{
		onToggleSummary?()
	}

	@objc private func toggleExpanded()
	{
		onToggleExpanded?()
	}

	@objc private func selectTab(_ sender: NSButton)
	{
		guard tabIDs.indices.contains(sender.tag)
		else
		{
			return
		}
		selectTabID(tabIDs[sender.tag])
	}

	private func selectTabID(_ id: UUID)
	{
		guard tabIDs.contains(id)
		else
		{
			return
		}
		selectedTabID = id
		isConversationSelected = false
		if let selectedFileDocumentID
		{
			lastFileSelectedID = selectedFileDocumentID
		}
		renderTabs()
		if let selectedFileDocumentID
		{
			onFileSelected?(selectedFileDocumentID)
		}
		onTabSelectionChange?()
		onChangesSelectionChange?()
	}

	private func navigateTabs(
		from id: UUID?,
		keyCode: UInt16
	) -> Bool
	{
		let ordered: [UUID?] = (isExpanded ? [nil] : []) + tabIDs.map(Optional.some)
		guard !ordered.isEmpty, let current = ordered.firstIndex(where:
			{
				$0 == id
			})
		else
		{
			return false
		}
		let target: Int
		switch keyCode
		{
		case 123: target = max(
				0,
				current - 1
			)
		case 124: target = min(
				ordered.count - 1,
				current + 1
			)
		case 115: target = 0
		case 119: target = ordered.count - 1
		default: return false
		}
		if let id = ordered[target]
		{
			selectTabID(id)
		}
		else
		{
			selectConversation()
		}
		return true
	}

	@objc private func selectConversation()
	{
		guard isExpanded
		else
		{
			return
		}
		isConversationSelected = true
		renderTabs()
		onTabSelectionChange?()
		onChangesSelectionChange?()
	}

	@objc private func closeTab(_ sender: NSButton)
	{
		removeTab(at: sender.tag)
	}

	private func removeTab(at index: Int)
	{
		guard tabIDs.indices.contains(index)
		else
		{
			return
		}
		let targetID = tabIDs[index]
		if fileTabPresentations.contains(where:
			{
				$0.id == targetID
			})
		{
			onFileCloseRequested?(targetID)
			return
		}
		let removedTabID = tabIDs.remove(at: index)
		if removedTabID == filesLandingTabID
		{
			filesLandingTabID = nil
			detachController(filesLandingController)
		}
		let removedSources = removedTabID == sourcesTabID
		if removedSources
		{
			sourcesTabID = nil
			detachSources()
		}
		let removedSubagents = removedTabID == subagentsTabID
		if removedSubagents
		{
			subagentsTabID = nil
			detachSubagents()
		}

		if removedTabID == changesTabID
		{
			changesTabID = nil
			onChangesTabClosed?()
		}
		tabCount = tabIDs.count
		if removedTabID == selectedTabID
		{
			selectedTabID = tabIDs.isEmpty ? nil : tabIDs[min(
				index,
				tabIDs.count - 1
			)]
		}
		renderTabs()
		if removedSources
		{
			onSourcesTabClosed?()
		}
		if removedSubagents
		{
			onSubagentsTabClosed?()
		}

		onChangesSelectionChange?()
		if tabIDs.isEmpty
		{
			onCloseLastTab?()
		}
		else
		{
			onTabSelectionChange?()
		}
	}
}

@MainActor
private final class ToolsTabSelectionButtonCell: NSButtonCell
{
	var documentTitleGap: CGFloat = 0

	override func titleRect(forBounds rect: NSRect) -> NSRect
	{
		let title = super.titleRect(forBounds: rect)
		return NSRect(
			x: title.minX + documentTitleGap,
			y: title.minY,
			width: max(
				0,
				title.width - documentTitleGap
			),
			height: title.height
		)
	}

	override func drawTitle(
		_ title: NSAttributedString,
		withFrame frame: NSRect,
		in controlView: NSView
	) -> NSRect
	{
		DesktopTextRendering.withFontSmoothingDisabled
		{
			super.drawTitle(
				title,
				withFrame: frame,
				in: controlView
			)
		}
	}
}

@MainActor
private final class ToolsHeadingTextField: NSTextField
{
	override func draw(_ dirtyRect: NSRect)
	{
		DesktopTextRendering.withFontSmoothingDisabled
		{
			super.draw(dirtyRect)
		}
	}
}

private enum ToolsChangesShortcut
{
	static let key = "g"
	static let modifiers: NSEvent.ModifierFlags = [.control, .shift]
	static let label = "⌃⇧G"
}

@MainActor
private final class ToolsTileButtonCell: NSButtonCell
{
	private let shortcut: String

	init(
		textCell: String,
		shortcut: String
	)
	{
		self.shortcut = shortcut
		super.init(textCell: textCell)
	}

	required init(coder: NSCoder)
	{
		fatalError("ToolsTileButtonCell is created in code")
	}

	private func shortcutTitle(in view: NSView) -> NSAttributedString
	{
		let color = NSColor(cgColor: AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.toolsTileIcon,
			for: view
		)) ?? AppKitColorTokens.toolsTileIcon
		return NSAttributedString(
			string: shortcut,
			attributes: [
				.font: AppKitFontResolver.font(TypographyTokens.Controls.toolsShortcut),
				.foregroundColor: color,
			]
		)
	}

	private func shortcutRect(forBounds rect: NSRect) -> NSRect
	{
		let title = NSAttributedString(
			string: shortcut,
			attributes: [.font: AppKitFontResolver.font(TypographyTokens.Controls.toolsShortcut)]
		)
		let width = title.size().width + 2 * LayoutTokens.Tabs.toolShortcutHorizontalInset
		return NSRect(
			x: rect.maxX - LayoutTokens.Tabs.toolTileInset - width,
			y: rect.midY - LayoutTokens.Tabs.toolShortcutHeight / 2,
			width: width,
			height: LayoutTokens.Tabs.toolShortcutHeight
		)
	}

	override func drawInterior(
		withFrame frame: NSRect,
		in controlView: NSView
	)
	{
		DesktopTextRendering.withFontSmoothingDisabled
		{
			super.drawInterior(
				withFrame: frame,
				in: controlView
			)
			let badge = shortcutRect(forBounds: frame)
			AppKitColorTokens.toolsShortcut.setFill()
			NSBezierPath(
				roundedRect: badge,
				xRadius: ShapeTokens.TabControls.toolShortcutRadius,
				yRadius: ShapeTokens.TabControls.toolShortcutRadius
			).fill()
			let text = shortcutTitle(in: controlView)
			text.draw(in: NSRect(
				x: badge.minX + LayoutTokens.Tabs.toolShortcutHorizontalInset,
				y: badge.midY - text.size().height / 2,
				width: text.size().width,
				height: text.size().height
			))
		}
	}

	override func drawImage(
		_ image: NSImage,
		withFrame frame: NSRect,
		in controlView: NSView
	)
	{
		guard (controlView as? NSControl)?.isEnabled != false
		else
		{
			// Keep AppKit's existing disabled artwork and title treatment.
			super.drawImage(
				image,
				withFrame: frame,
				in: controlView
			)
			return
		}
		DesktopIcons.draw(
			image,
			in: frame,
			tint: AppKitColorTokens.toolsTileIcon
		)
	}

	override func imageRect(forBounds rect: NSRect) -> NSRect
	{
		NSRect(
			x: rect.minX + LayoutTokens.Tabs.toolTileInset,
			y: rect.midY - LayoutTokens.Tabs.toolTileIconSize / 2,
			width: LayoutTokens.Tabs.toolTileIconSize,
			height: LayoutTokens.Tabs.toolTileIconSize
		)
	}
	override func titleRect(forBounds rect: NSRect) -> NSRect
	{
		let leading = LayoutTokens.Tabs.toolTileInset + LayoutTokens.Tabs
			.toolTileIconSize + LayoutTokens.Tabs.toolTileIconGap
		var title = super.titleRect(forBounds: rect)
		title.origin.x = rect.minX + leading
		title.size.width = max(
			0,
			shortcutRect(forBounds: rect).minX - LayoutTokens.Tabs.toolTileIconGap
				- title.minX
		)
		return title
	}
}

@MainActor
private final class ToolsTileButton: DesktopAttributedTitleButton
{
	var cornerRadius = ShapeTokens.TabControls.toolTileRadius
	private var isHovered = false
	private var tracking: NSTrackingArea?

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let tracking
		{
			removeTrackingArea(tracking)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		tracking = area
	}

	override func mouseEntered(with event: NSEvent)
	{
		isHovered = true
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent)
	{
		isHovered = false
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		let fill = isEnabled && isHovered
			? AppKitColorTokens.rowHighlight : AppKitColorTokens.toolsTile
		fill.setFill()
		AppKitShapePath.roundedRect(
			bounds,
			radius: cornerRadius,
			curve: ShapeTokens.TabControls.cornerCurve
		).fill()
		super.draw(dirtyRect)
	}
}
