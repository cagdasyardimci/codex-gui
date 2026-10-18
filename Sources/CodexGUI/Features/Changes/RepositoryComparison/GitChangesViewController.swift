import AppKit

/// Read-only Git comparison UI. Repository requests and snapshot ownership live in the runtime.
@MainActor
final class GitChangesViewController: NSViewController, NSSearchFieldDelegate
{
	var onSummaryChange: ((GitReviewSummaryProjection?) -> Void)?
	var onClose: (() -> Void)?
	var onShowReportedChanges: (() -> Void)?
	var onToggleExpanded: (() -> Void)?
	{
		didSet
		{
			updateHostControls()
		}
	}
	var onTogglePanel: (() -> Void)?
	{
		didSet
		{
			updateHostControls()
		}
	}
	var isExpanded = true
	{
		didSet
		{
			updateHostControls()
		}
	}
	var showsInternalChangesTab = true
	{
		didSet
		{
			internalChangesTab?.isHidden = !showsInternalChangesTab
		}
	}
	let runtime: GitReviewRuntime
	private let comparisonToolbarView = GitComparisonToolbarView()
	private var scopeButton: NSButton
	{
		comparisonToolbarView.scopeButton
	}
	private var optionsButton: NSButton
	{
		comparisonToolbarView.optionsButton
	}
	private var baseField: NSTextField
	{
		comparisonToolbarView.baseField
	}
	private var targetField: NSTextField
	{
		comparisonToolbarView.targetField
	}
	private var additionsLabel: NSTextField
	{
		comparisonToolbarView.additionsLabel
	}
	private var deletionsLabel: NSTextField
	{
		comparisonToolbarView.deletionsLabel
	}
	private let statusLabel = NSTextField(wrappingLabelWithString: "")
	private let filterField = ViewerSearchField()
	private let tree = ViewerFileTreeView()
	private let navigator = NSView()
	private var navigatorSplit: ViewerNavigatorSplitView?
	private let documentController = GitDiffDocumentController()
	private var treeNodes: [GitDiffTreeRow.ID: GitComparisonTreeNode] = [:]
	private var treeExpansionTasks: [GitDiffTreeRow.ID: Task<Void, Never>] = [:]
	private var lastTreeFileSelection: Data?
	var projectionCache: GitDiffProjectionCache
	{
		documentController.projectionCache
	}
	private var rendering = false
	private var internalChangesTab: NSView?
	private var revisionComparison: NSView?
	{
		comparisonToolbarView.revisionComparison
	}
	private var diffLayoutButton: NSButton?
	{
		comparisonToolbarView.diffLayoutButton
	}
	private var largeComparisonBanner: NSView?
	private let largeComparisonLabel = NSTextField(wrappingLabelWithString: "")
	private var previousFileButton: NSButton?
	private var nextFileButton: NSButton?
	private var navigatorToggle: NSButton?
	{
		comparisonToolbarView.navigatorToggle
	}
	private var fileJumpButton: NSButton?
	{
		comparisonToolbarView.fileJumpButton
	}
	private var refreshButton: NSButton?
	{
		comparisonToolbarView.refreshButton
	}
	private var wordWrapButton: NSButton?
	{
		comparisonToolbarView.wordWrapButton
	}
	private var collapseDiffsButton: NSButton?
	{
		comparisonToolbarView.collapseDiffsButton
	}
	private var fileJumpPopover: NSPopover?
	private var expandHostButton: NSButton?
	private var panelHostButton: NSButton?
	private var usesCompactComparisonToolbar: Bool
	{
		comparisonToolbarView.usesCompactLayout
	}
	private var internalTabWidth: NSLayoutConstraint?
	private var largeComparisonBannerHeight: NSLayoutConstraint?

	init(runtime: GitReviewRuntime = GitReviewRuntime())
	{
		self.runtime = runtime
		super.init(
			nibName: nil,
			bundle: nil
		)
		runtime.onChange =
		{
			[weak self] state in
			self?.render(state)
			self?.onSummaryChange?(state.summaryProjection)
		}
		documentController.onExpandGap =
		{
			[weak self] id in self?.runtime.expandGap(id)
		}
		documentController.onNeedsRender =
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			self.render(self.runtime.state)
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func activate(
		owner: FeaturePresentationOwner,
		lastTurnID: String? = nil,
		baselineRevision: Int = 0,
		baselineFailure: GitComparisonFailure? = nil
	)
	{
		_ = view
		runtime.activate(
			owner: owner,
			lastTurnID: lastTurnID,
			baselineRevision: baselineRevision,
			baselineFailure: baselineFailure
		)
	}

	func updateOwner(
		_ owner: FeaturePresentationOwner,
		lastTurnID: String? = nil,
		baselineRevision: Int = 0,
		baselineFailure: GitComparisonFailure? = nil
	)
	{
		guard runtime.state.isOpen
		else
		{
			return
		}
		runtime.activate(
			owner: owner,
			lastTurnID: lastTurnID,
			baselineRevision: baselineRevision,
			baselineFailure: baselineFailure
		)
	}

	@discardableResult
	func selectFile(
		snapshotID: String,
		fileID: String,
		owner: FeaturePresentationOwner
	) -> Bool
	{
		guard runtime.state.isOpen, runtime.state.owner == owner,
				runtime.state.snapshot?.id == snapshotID, !runtime.state.isStale,
				runtime.state.snapshot?.files.contains(where:
				{
					$0.id.utf8.elementsEqual(fileID.utf8)
				}) == true
		else
		{
			return false
		}
		runtime.selectFile(fileID)
		documentController.scrollToFile(fileID)
		return true
	}

	func close()
	{
		for task in treeExpansionTasks.values
		{
			task.cancel()
		}
		treeExpansionTasks.removeAll()
		runtime.close()
	}

	override func loadView()
	{
		let surface = DesktopSurface(AppKitColorTokens.canvas)
		view = surface
		let tab = makeInternalChangesTab()
		internalChangesTab = tab
		tab.isHidden = !showsInternalChangesTab
		let toolbarScroll = makeComparisonToolbarScrollView()
		AppKitLayout.compressHorizontally(statusLabel)
		statusLabel.font = .systemFont(ofSize: 11)
		statusLabel.textColor = .secondaryLabelColor
		statusLabel.setAccessibilityLabel("Git comparison status")
		let banner = makeLargeComparisonBanner()
		largeComparisonBanner = banner
		banner.isHidden = true
		configureNavigator()
		addChild(documentController)
		let contentScroll = documentController.view
		let body = ViewerNavigatorSplitView(
			document: contentScroll,
			navigator: navigator
		)
		navigatorSplit = body
		body
			.onNavigatorVisibilityChanged =
			{
				[weak self] _ in
				self?.updateNavigatorToggleAppearance()
			}
		updateNavigatorToggleAppearance()

		statusLabel.isHidden = true
		let layout = NSStackView(views: [tab, toolbarScroll, statusLabel, banner, body])
		layout.orientation = .vertical
		layout.alignment = .leading
		layout.spacing = 0
		AppKitLayout.pin(
			layout,
			to: surface,
			inset: 0
		)
		for row in [tab, toolbarScroll, statusLabel, banner, body]
		{
			row.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true
		}
		body.bottomAnchor.constraint(equalTo: layout.bottomAnchor).isActive = true

		render(runtime.state)
	}

	override func viewDidLayout()
	{
		super.viewDidLayout()
		updateComparisonToolbarLayout()
	}

	private func makeComparisonToolbarScrollView() -> NSScrollView
	{
		let toolbar = makeComparisonToolbar()
		let toolbarScroll = NSScrollView()
		toolbarScroll.hasHorizontalScroller = true
		toolbarScroll.autohidesScrollers = true
		toolbarScroll.drawsBackground = false
		toolbar.translatesAutoresizingMaskIntoConstraints = false
		toolbarScroll.documentView = toolbar
		NSLayoutConstraint.activate([
			toolbarScroll.heightAnchor.constraint(equalToConstant: 48),
			toolbar.widthAnchor
				.constraint(greaterThanOrEqualTo: toolbarScroll.contentView.widthAnchor),
			toolbar.heightAnchor.constraint(equalTo: toolbarScroll.contentView.heightAnchor),
		])
		return toolbarScroll
	}

	private func makeInternalChangesTab() -> NSView
	{
		let title = NSTextField(labelWithString: "Changes")
		title.font = .systemFont(ofSize: 14)
		let titleIcon = NSImageView(image: PinnedSummaryIcons.image(.changes))
		titleIcon.contentTintColor = .labelColor
		titleIcon.setAccessibilityElement(false)
		let close = referenceButton(
			"Close Changes",
			image: DesktopIcons.image(.xXsCrossed),
			action: #selector(closePanel)
		)
		let tab = ViewerToolbarGroup(
			AppKitLayout.horizontalStack(
				[titleIcon, title, GitReviewControls.spacer(), close],
				spacing: 8
			),
			radius: 9,
			verticalInset: 2
		)
		let tabWidth = tab.widthAnchor.constraint(equalToConstant: 240)
		tabWidth.isActive = true
		internalTabWidth = tabWidth
		let plus = referenceButton(
			"New review tab unavailable",
			image: PinnedSummaryIcons.image(.plus),
			action: nil
		)
		plus.isEnabled = false
		plus.toolTip = "New review tab unavailable: reference action has not been defined"
		let expand = referenceButton(
			"Expand Changes",
			image: GitReviewReferenceIcons.image(.expand),
			action: #selector(toggleExpandedHost)
		)
		expandHostButton = expand
		let panel = referenceButton(
			"Toggle conversation panel",
			image: GitReviewReferenceIcons.image(.panel),
			action: #selector(toggleHostPanel)
		)
		panelHostButton = panel
		let row = AppKitLayout.horizontalStack(
			[tab, plus, GitReviewControls.spacer(), expand, panel],
			spacing: 12
		)
		updateHostControls()
		return row
	}

	private func makeComparisonToolbar() -> NSStackView
	{
		comparisonToolbarView.configure(
			target: self,
			actions: GitComparisonToolbarView.Actions(
				scope: #selector(showScopeMenu),
				revisions: #selector(changeRevisions),
				revisionMenu: #selector(showRevisionMenu),
				displayMenu: #selector(showDisplayMenu),
				fileJump: #selector(showFileJumpPopover),
				refresh: #selector(refreshComparison),
				wordWrap: #selector(toggleWordWrap),
				collapseAll: #selector(toggleAllDiffs),
				diffLayout: #selector(switchDiffLayout),
				navigator: #selector(toggleNavigator)
			)
		)
		updateDiffLayoutButton()
		updateWordWrapButton()
		return comparisonToolbarView
	}

	private func updateComparisonToolbarLayout()
	{
		guard let narrow = comparisonToolbarView.updateLayout(for: view.bounds.width)
		else
		{
			return
		}
		internalTabWidth?.constant = narrow ? 220 : 240
		largeComparisonBannerHeight?.constant = narrow ? 76 : 64
	}

	@objc private func switchDiffLayout()
	{
		documentController.switchLayout()
		updateDiffLayoutButton()
		view.needsLayout = true
	}

	private func updateDiffLayoutButton()
	{
		let tooltip: String
		switch documentController.layoutPreference
		{
		case .automatic: tooltip = "Auto diff: switch to unified diff"
		case .unified: tooltip = "Switch to split diff"
		case .split: tooltip = "Switch to auto diff"
		}
		diffLayoutButton?.toolTip = tooltip
		diffLayoutButton?.setAccessibilityValue(documentController.layoutPreference.rawValue)
		diffLayoutButton?.image = GitReviewReferenceIcons.image(
			documentController.layoutPreference == .unified ? .unifiedDisplayMode : .displayMode
		)
	}

	private func makeLargeComparisonBanner() -> NSView
	{
		let icon = NSImageView(image: GitReviewReferenceIcons.image(
			.info,
			size: 18
		))
		icon.contentTintColor = .systemBlue
		icon.setAccessibilityElement(false)
		largeComparisonLabel.font = .systemFont(ofSize: 14)
		largeComparisonLabel.lineBreakMode = .byWordWrapping
		largeComparisonLabel.maximumNumberOfLines = 2
		largeComparisonLabel.cell?.usesSingleLineMode = false
		largeComparisonLabel.cell?.wraps = true
		largeComparisonLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let previous = referenceButton(
			"Previous changed file",
			image: DesktopIcons.image(.chevronLeft),
			action: #selector(previousFile)
		)
		let next = referenceButton(
			"Next changed file",
			image: DesktopIcons.image(.chevronRight),
			action: #selector(nextFile)
		)
		previousFileButton = previous
		nextFileButton = next
		let row = AppKitLayout.horizontalStack(
			[icon, largeComparisonLabel, GitReviewControls.spacer(), previous, next],
			spacing: 12
		)
		let banner = ViewerToolbarGroup(
			row,
			radius: 20
		)
		let bannerHeight = banner.heightAnchor.constraint(equalToConstant: 64)
		bannerHeight.isActive = true
		largeComparisonBannerHeight = bannerHeight
		banner.setAccessibilityLabel("Large Git comparison")
		banner.toolTip = "Proposed large comparison threshold: 20 files or 2,000 changed lines"
		return banner
	}

	private func referenceButton(
		_ title: String,
		image: NSImage,
		action: Selector?
	) -> NSButton
	{
		GitReviewControls.referenceButton(
			title,
			image: image,
			target: self,
			action: action
		)
	}

	private func configureNavigator()
	{
		filterField.delegate = self
		filterField.setAccessibilityLabel("Filter changed files by path")
		tree.setAccessibilityLabel("Changed-file tree")
		tree.children =
		{
			($0 as? GitComparisonTreeNode)?.children ?? []
		}
		tree.isExpandable =
		{
			($0 as? GitComparisonTreeNode)?.row.isDirectory == true
		}
		tree.presentation =
		{
			[weak self] item in
			guard let node = item as? GitComparisonTreeNode
			else
			{
				return ViewerFileTreePresentation(
					name: "",
					path: "",
					icon: nil
				)
			}
			return self?.treePresentation(node.row) ?? ViewerFileTreePresentation(
				name: node.row.name,
				path: node.row.path,
				icon: nil
			)
		}
		tree.onActivate =
		{
			[weak self] item, _ in self?.selectTreeFile(item)
		}
		tree.onSelectionChanged =
		{
			[weak self] item in
			guard let self, !self.rendering, let item
			else
			{
				return
			}
			self.selectTreeFile(item)
		}
		tree.onDidExpand =
		{
			[weak self] item in self?.scheduleTreeExpansion(
				item,
				expanded: true
			)
		}
		tree
			.onDidCollapse =
			{
				[weak self] item in
				self?.scheduleTreeExpansion(
					item,
					expanded: false
				)
			}
		tree.onContextMenu =
		{
			[weak self] item in
			guard let self, let node = item as? GitComparisonTreeNode,
					let fileID = node.row.fileID, let snapshot = self.runtime.state.snapshot,
					let file = snapshot.files.first(where:
					{
						$0.id.utf8.elementsEqual(fileID.utf8)
					})
			else
			{
				return nil
			}
			return self.documentController.makeFileActionsMenu(
				file: file,
				snapshot: snapshot
			)
		}
		let surface = ViewerFileNavigatorView(
			filterField: filterField,
			tree: tree
		)
		AppKitLayout.pin(
			surface,
			to: navigator,
			inset: 0
		)
	}

	private func render(_ state: GitReviewState)
	{
		guard isViewLoaded
		else
		{
			return
		}
		documentController.updateLayout(for: state)
		updateDiffLayoutButton()
		let previousStatus = statusLabel.stringValue
		rendering = true
		defer
		{
			rendering = false
			if previousStatus != statusLabel.stringValue
			{
				scopeButton.setAccessibilityHelp(statusLabel.stringValue)
				NSAccessibility.post(
					element: scopeButton,
					notification: .valueChanged
				)
			}
		}
		let current = updateComparisonControls(state)
		updateStatusLabel(state)
		statusLabel.isHidden = state.failure == nil && state.pendingRequest == nil
			&& !(state.snapshot?.files.isEmpty ?? true)

		guard let snapshot = state.snapshot
		else
		{
			documentController.render(
				state: state,
				presentation: nil,
				selectedFileID: nil,
				usesSingleFile: false
			)
			largeComparisonBanner?.isHidden = true
			treeNodes.removeAll()
			tree.rootItems = []
			tree.reloadTree()
			return
		}
		let usesSingleFile = GitReviewDesignLayout.isLarge(snapshot)
		let displayedFileID = usesSingleFile
			? state.selectedFileID ?? snapshot.files.first?.id : nil
		updateLargeComparison(
			snapshot,
			selectedFileID: displayedFileID,
			current: current
		)
		let presentation = GitDiffPresentation(
			snapshot: snapshot,
			options: state.options
		)
		renderTree(
			presentation: presentation,
			state: state,
			displayedFileID: displayedFileID
		)
		if tree.rootItems.isEmpty && !state.filter.isEmpty
		{
			statusLabel.stringValue += " · No matching filtered files."
			statusLabel.isHidden = false
		}

		documentController.render(
			state: state,
			presentation: presentation,
			selectedFileID: displayedFileID,
			usesSingleFile: usesSingleFile
		)
		updateCollapseDiffsButton(snapshot)
	}

	private func updateComparisonControls(_ state: GitReviewState) -> Bool
	{
		scopeButton.title = state.scope.rawValue
		scopeButton.setAccessibilityLabel("Comparison scope: \(state.scope.rawValue)")
		let requiresRefs = state.scope == .branch || state.scope == .committed
		if revisionComparison?.isHidden != !requiresRefs
		{
			revisionComparison?.isHidden = !requiresRefs
		}
		let revisions = displayedRevisions(state)
		if !requiresRefs || baseField.currentEditor() == nil
		{
			baseField.stringValue = revisions.base
		}
		if !requiresRefs || targetField.currentEditor() == nil
		{
			targetField.stringValue = revisions.target
		}
		baseField.toolTip = revisions.base
		targetField.toolTip = revisions.target
		baseField.setAccessibilityLabel("Base revision: \(revisions.base)")
		targetField.setAccessibilityLabel("Target revision: \(revisions.target)")
		baseField.isEnabled = requiresRefs
		targetField.isEnabled = requiresRefs
		filterField.stringValue = state.filter
		let current = state.snapshot != nil && !state.isStale && state.pendingRequest == nil
		fileJumpButton?.isEnabled = current && !(state.snapshot?.files.isEmpty ?? true)
		let additionCount = (state.snapshot?.additions ?? 0)
			.formatted(.number.locale(Locale(identifier: "en_US")))
		additionsLabel.stringValue = current ? "+\(additionCount)" : "—"
		let deletionCount = (state.snapshot?.deletions ?? 0)
			.formatted(.number.locale(Locale(identifier: "en_US")))
		deletionsLabel.stringValue = current ? "-\(deletionCount)" : "—"
		return current
	}

	private func updateStatusLabel(_ state: GitReviewState)
	{
		if let failure = state.failure
		{
			statusLabel.stringValue = failure.message + " Refresh to retry." +
				(state.isStale ? " Previous snapshot shown below (stale)." : "")
		}
		else if state.pendingRequest != nil
		{
			if state.isStale
			{
				statusLabel.stringValue =
					"Loading comparison · previous snapshot shown below (stale)"
			}
			else
			{
				statusLabel.stringValue = "Loading comparison…"
			}
		}
		else if let snapshot = state.snapshot
		{
			let hasDisplayFilters = state.options.ignoreWhitespace || state.options.ignoreImports
			if snapshot.files.isEmpty
			{
				statusLabel.stringValue = "No changes in this comparison."
			}
			else
			{
				statusLabel.stringValue = "\(snapshot.files.count) changed files · "
					+ "\(snapshot.resolvedBase) → \(snapshot.resolvedTarget) · raw textual totals"
					+ (hasDisplayFilters ? " · display filters active" : "")
			}
		}
		else
		{
			statusLabel.stringValue = "Select a workspace to inspect Git changes."
		}
		if state.scope == .lastTurn
		{
			if state.snapshot?.usesReportedEditFallback == true
			{
				statusLabel.stringValue += " · " + GitReportedTurnComparison.fallbackMessage
			}
			statusLabel.stringValue += " · " + GitReportedTurnComparison.coverageMessage
		}
		else if let owner = state.owner?.runtimeOwner?.owner, case .source = owner
		{
			statusLabel.stringValue += " · shared checkout; changes include all chats"
		}
		if let selectionMessage = state.selectionMessage
		{
			statusLabel.stringValue += " " + selectionMessage
		}
	}

	private func displayedRevisions(_ state: GitReviewState) -> (base: String, target: String)
	{
		switch state.scope
		{
		case .uncommitted: ("HEAD", "Tracked working tree")
		case .unstaged: ("Index", "Tracked working tree")
		case .staged: ("HEAD", "Index")
		case .branch, .committed: (state.baseRevision, state.targetRevision)
		case .lastTurn: ("Before selected turn edits", "Recorded task edits")
		}
	}

	private func renderTree(
		presentation: GitDiffPresentation,
		state: GitReviewState,
		displayedFileID: String?
	)
	{
		let priorSelection = tree.selectedItem as? GitComparisonTreeNode
		let priorScroll = tree.enclosingScrollView?.contentView.bounds.origin
		var directories: Set<Data> = []
		for file in presentation.snapshot.files
		{
			var parent = (file.path as NSString).deletingLastPathComponent
			while !parent.isEmpty
			{
				directories.insert(Data(parent.utf8))
				parent = (parent as NSString).deletingLastPathComponent
			}
		}
		let rows = presentation.treeRows(
			filter: state.filter,
			expandedDirectories: directories
		)
		var next: [GitDiffTreeRow.ID: GitComparisonTreeNode] = [:]
		for row in rows
		{
			let node = treeNodes[row.id] ?? GitComparisonTreeNode(row)
			node.row = row
			node.children = []
			next[row.id] = node
		}
		var roots: [NSObject] = []
		for row in rows
		{
			guard let node = next[row.id]
			else
			{
				continue
			}
			if let directory = next[row.parentID]
			{
				directory.children.append(node)
			}
			else
			{
				roots.append(node)
			}
		}
		treeNodes = next
		tree.rootItems = roots
		tree.reloadTree()
		for row in rows where row.isDirectory
		{
			guard let node = next[row.id]
			else
			{
				continue
			}
			if !state.filter.isEmpty || state.expandedDirectories
				.contains(Data(row.path.utf8))
			{
				tree.expandItem(node)
			}
			else
			{
				tree.collapseItem(node)
			}
		}
		let selectedID = (state.selectedFileID ?? displayedFileID).map
		{
			Data($0.utf8)
		}
		let selected: GitComparisonTreeNode?
		if lastTreeFileSelection == selectedID, let priorSelection,
			priorSelection.row.isDirectory, next[priorSelection.row.id] === priorSelection
		{
			selected = priorSelection
		}
		else
		{
			selected = next.values.first
			{
				$0.row.fileID.map
				{
					Data($0.utf8)
				} == selectedID && selectedID != nil
			}
		}
		lastTreeFileSelection = selectedID
		let selectedRow = selected.map
		{
			tree.row(forItem: $0)
		} ?? -1
		if selectedRow >= 0
		{
			tree.selectRowIndexes(
				IndexSet(integer: selectedRow),
				byExtendingSelection: false
			)
		}
		else
		{
			tree.deselectAll(nil)
		}
		if let priorScroll
		{
			tree.enclosingScrollView?.contentView.scroll(to: priorScroll)
		}
	}

	private func treePresentation(_ row: GitDiffTreeRow) -> ViewerFileTreePresentation
	{
		var accessories: [NSView] = []
		if let id = row.fileID,
			let file = runtime.state.snapshot?.files.first(where:
			{
				$0.id.utf8.elementsEqual(id.utf8)
			})
		{
			if file.additions > 0
			{
				let plus = NSTextField(labelWithString: "+\(file.additions)")
				plus.textColor = .systemGreen
				accessories.append(plus)
			}
			if file.deletions > 0
			{
				let minus = NSTextField(labelWithString: "-\(file.deletions)")
				minus.textColor = .systemRed
				accessories.append(minus)
			}
		}
		return ViewerFileTreePresentation(
			name: row.name,
			path: row.path,
			icon: row.isDirectory ? nil : WorkspaceFileIcon
				.image(relativePath: row.path),
			accessories: accessories,
			accessibilityLabel: (row
				.isDirectory ? "Directory " : "Changed file ") + row.path
		)
	}

	private func selectTreeFile(_ item: NSObject)
	{
		guard !rendering, let id = (item as? GitComparisonTreeNode)?.row.fileID
		else
		{
			return
		}
		if runtime.state.selectedFileID.map(
			{
				Data($0.utf8)
			}
		) != Data(id.utf8)
		{
			runtime.selectFile(id)
		}
		documentController.scrollToFile(id)
	}

	private func scheduleTreeExpansion(
		_ item: NSObject,
		expanded: Bool
	)
	{
		guard !rendering, let node = item as? GitComparisonTreeNode,
				let snapshot = runtime.state.snapshot
		else
		{
			return
		}
		let path = node.row.path
		let identity = node.row.id
		treeExpansionTasks[identity]?.cancel()
		let owner = runtime.state.owner
		// Runtime publication reloads the outline; let native expansion finish first.
		treeExpansionTasks[identity] = Task
		{
			@MainActor [weak self, weak node] in
			guard let self, let node, !Task.isCancelled
			else
			{
				return
			}
			self.treeExpansionTasks[identity] = nil
			let isCurrentSnapshot = self.runtime.state.snapshot?.id == snapshot.id
			guard self.runtime.state.isOpen, self.runtime.state.owner == owner,
					isCurrentSnapshot, self.treeNodes[identity] === node,
					self.tree.isItemExpanded(node) == expanded
			else
			{
				return
			}
			if self.runtime.state.expandedDirectories.contains(Data(path.utf8)) != expanded
			{
				self.runtime.toggleDirectory(path)
			}
		}
	}

	func controlTextDidChange(_ notification: Notification)
	{
		guard !rendering, notification.object as? NSSearchField === filterField
		else
		{
			return
		}
		runtime.setFilter(filterField.stringValue)
	}

	@objc private func showReportedChanges()
	{
		onShowReportedChanges?()
	}
	@objc private func closePanel()
	{
		close()
		onClose?()
	}
	@objc private func refreshComparison()
	{
		runtime.reload()
	}
	@objc private func toggleNavigator()
	{
		guard let navigatorSplit
		else
		{
			return
		}
		navigatorSplit.setNavigatorVisible(!navigatorSplit.isNavigatorVisible)
	}

	private func updateNavigatorToggleAppearance()
	{
		let visible = navigatorSplit?.isNavigatorVisible == true
		navigatorToggle?.contentTintColor = visible ? .systemBlue : .secondaryLabelColor
		navigatorToggle?.setAccessibilityValue(visible ? "Visible" : "Hidden")
	}

	private func updateLargeComparison(
		_ snapshot: GitComparisonSnapshot,
		selectedFileID: String?,
		current: Bool
	)
	{
		let large = GitReviewDesignLayout.isLarge(snapshot)
		largeComparisonBanner?.isHidden = !large
		largeComparisonLabel.stringValue = "This diff is large, showing one file at a time"
		let index = snapshot.files.firstIndex
		{
			Data($0.id.utf8) == selectedFileID.map
			{
				Data($0.utf8)
			}
		} ?? 0
		previousFileButton?.isEnabled = current && index > 0
		nextFileButton?.isEnabled = current && index + 1 < snapshot.files.count
		largeComparisonBanner?.setAccessibilityValue("File \(index + 1) of \(snapshot.files.count)")
	}

	@objc private func previousFile()
	{
		navigateFile(offset: -1)
	}
	@objc private func nextFile()
	{
		navigateFile(offset: 1)
	}

	private func navigateFile(offset: Int)
	{
		let state = runtime.state
		let selectedIdentity = (state.selectedFileID ?? state.snapshot?.files.first?.id).map
		{
			Data($0.utf8)
		}
		guard let snapshot = state.snapshot, let owner = state.owner,
				state.pendingRequest == nil,
				let index = snapshot.files.firstIndex(where:
				{
					Data($0.id.utf8) == selectedIdentity
				})
		else
		{
			return
		}
		let destination = index + offset
		guard snapshot.files.indices.contains(destination)
		else
		{
			return
		}
		_ = selectFile(
			snapshotID: snapshot.id,
			fileID: snapshot.files[destination].id,
			owner: owner
		)
	}

	@objc private func showFileJumpPopover()
	{
		let state = runtime.state
		guard let snapshot = state.snapshot, let owner = state.owner,
				state.pendingRequest == nil, !state.isStale,
				let fileJumpButton
		else
		{
			return
		}
		let popover = NSPopover()
		popover.behavior = .transient
		popover.contentSize = NSSize(
			width: 380,
			height: 350
		)
		let controller =
			GitFileJumpPopoverController(index: GitFileJumpIndex(files: snapshot.files))
		controller.onSelect =
		{
			[weak self, weak popover] id in
			guard let self
			else
			{
				return
			}
			_ = self.selectFile(
				snapshotID: snapshot.id,
				fileID: id,
				owner: owner
			)
			popover?.close()
		}
		controller.onCancel =
		{
			[weak popover] in popover?.close()
		}
		popover.contentViewController = controller
		fileJumpPopover?.close()
		fileJumpPopover = popover
		popover.show(
			relativeTo: fileJumpButton.bounds,
			of: fileJumpButton,
			preferredEdge: .maxY
		)
		controller.focusSearch()
	}

	@objc private func toggleWordWrap()
	{
		documentController.toggleWordWrap()
		updateWordWrapButton()
	}

	private func updateWordWrapButton()
	{
		wordWrapButton?.setAccessibilityLabel(
			documentController.wrapsCode ? "Stop wrapping code lines" : "Wrap code lines"
		)
		wordWrapButton?.toolTip = documentController.wrapsCode
			? "Stop wrapping code lines" : "Wrap code lines"
		wordWrapButton?.setAccessibilityValue(documentController.wrapsCode ? "On" : "Off")
	}

	@objc private func toggleAllDiffs()
	{
		documentController.toggleAllDiffs()
	}

	private func updateCollapseDiffsButton(_ snapshot: GitComparisonSnapshot)
	{
		let title = documentController.collapseAllMode ? "Expand all diffs" : "Collapse all diffs"
		collapseDiffsButton?.setAccessibilityLabel(title)
		collapseDiffsButton?.toolTip = title
		collapseDiffsButton?.isEnabled = !snapshot.files.isEmpty
	}

	@objc private func toggleExpandedHost()
	{
		onToggleExpanded?()
	}
	@objc private func toggleHostPanel()
	{
		onTogglePanel?()
	}

	private func updateHostControls()
	{
		let label = isExpanded ? "Show conversation beside Changes" : "Expand Changes"
		expandHostButton?.toolTip = label
		expandHostButton?.setAccessibilityLabel(label)
		expandHostButton?.isEnabled = onToggleExpanded != nil
		panelHostButton?.isEnabled = onTogglePanel != nil
	}

	@objc private func changeRevisions()
	{
		runtime.setRevisions(
			base: baseField.stringValue,
			target: targetField.stringValue
		)
	}
	@objc private func showRevisionMenu()
	{
		let menu = NSMenu()
		menu.autoenablesItems = false
		for (title, tag) in [("Edit base revision…", 0), ("Edit target revision…", 1)]
		{
			let item = NSMenuItem(
				title: title,
				action: #selector(editRevisionField(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.tag = tag
			item.isEnabled = baseField.isEnabled
			menu.addItem(item)
		}
		menu.popUp(
			positioning: nil,
			at: NSPoint(
				x: targetField.bounds.maxX,
				y: targetField.bounds.maxY
			),
			in: targetField
		)
	}

	@objc private func editRevisionField(_ sender: NSMenuItem)
	{
		view.window?.makeFirstResponder(sender.tag == 0 ? baseField : targetField)
	}

	@objc private func showScopeMenu()
	{
		let menu = NSMenu()
		for scope in GitComparisonScope.allCases
		{
			if scope == .uncommitted || scope == .committed
			{
				menu.addItem(.separator())
			}
			let item = NSMenuItem(
				title: scope.rawValue,
				action: #selector(selectScope(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.representedObject = scope.rawValue
			item.state = scope == runtime.state.scope ? .on : .off
			if scope == .committed
			{
				item.action = nil
				let submenu = NSMenu(title: "Committed")
				for (title, tag) in [("HEAD parent → HEAD", 0), ("Custom revision pair…", 1)]
				{
					let child = NSMenuItem(
						title: title,
						action: #selector(selectCommitted(_:)),
						keyEquivalent: ""
					)
					child.target = self
					child.tag = tag
					submenu.addItem(child)
				}
				item.submenu = submenu
			}
			menu.addItem(item)
		}
		menu.popUp(
			positioning: nil,
			at: NSPoint(
				x: 0,
				y: scopeButton.bounds.maxY
			),
			in: scopeButton
		)
		view.window?.makeFirstResponder(scopeButton)
	}

	@objc private func selectScope(_ sender: NSMenuItem)
	{
		guard let value = sender.representedObject as? String,
				let scope = GitComparisonScope(rawValue: value)
		else
		{
			return
		}
		runtime.selectScope(scope)
	}

	@objc private func selectCommitted(_ sender: NSMenuItem)
	{
		if sender.tag == 0
		{
			runtime.setRevisions(
				base: "HEAD^",
				target: "HEAD"
			)
		}
		runtime.selectScope(.committed)
		if sender.tag == 1
		{
			view.window?.makeFirstResponder(baseField)
		}
	}

	func makeDiffDisplayMenu() -> NSMenu
	{
		let menu = NSMenu()
		menu.autoenablesItems = false
		let reported = NSMenuItem(
			title: "Open reported turn changes",
			action: #selector(showReportedChanges),
			keyEquivalent: ""
		)
		reported.target = self
		reported.isEnabled = onShowReportedChanges != nil
		let options = runtime.state.options
		let checks = [
			options.loadFullFiles,
			false,
			options.showWordDiffs,
			options.ignoreWhitespace,
			options.ignoreImports,
			false
		]
		for (index, title) in [
			"Load full files",
			"Rich preview",
			"Word diffs",
			"Hide white space",
			"Hide imports",
			"Copy git apply command"
		].enumerated()
		{
			let item = NSMenuItem(
				title: title,
				action: #selector(selectDisplayOption(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.tag = index
			item.state = checks[index] ? .on : .off
			switch index
			{
			case 0: item.image = DesktopIcons.image(.fileBlank)
			case 1: item.image = DesktopIcons.image(.imageSquare)
			case 2: item.image = PinnedSummaryIcons.image(.changes)
			case 3: item.image = DesktopIcons.image(.eye)
			case 4: item.image = DesktopIcons.image(.cube)
			case 5: item.image = DesktopIcons.image(.clipboard)
			default: break
			}
			if index == 1
			{
				item.isEnabled = false
				item.toolTip = "Rich preview unavailable; showing read-only source."
			}
			if index == 5
			{
				item.isEnabled = runtime.state.copyCommand != nil
				item.toolTip = "Copy the exact unfiltered snapshot as "
					+ "a base64-decoding git apply command. "
					+ "Binary comparisons are unavailable. This never executes the command."
			}
			menu.addItem(item)
		}
		menu.addItem(.separator())
		menu.addItem(reported)
		if usesCompactComparisonToolbar
		{
			menu.addItem(.separator())
			for (title, action, enabled, state) in [
				(
					"Refresh comparison",
					#selector(refreshComparison),
					true,
					NSControl.StateValue.off
				),
				(
					documentController.wrapsCode ? "Stop wrapping code lines" : "Wrap code lines",
					#selector(toggleWordWrap),
					true,
					documentController.wrapsCode ? .on : .off
				),
				(
					documentController.collapseAllMode ? "Expand all diffs" : "Collapse all diffs",
					#selector(toggleAllDiffs),
					!(runtime.state.snapshot?.files.isEmpty ?? true),
					documentController.collapseAllMode ? .on : .off
				),
				("Switch diff layout", #selector(switchDiffLayout), true, .off),
			]
			{
				let item = NSMenuItem(
					title: title,
					action: action,
					keyEquivalent: ""
				)
				item.target = self
				item.isEnabled = enabled
				item.state = state
				menu.addItem(item)
			}
		}
		return menu
	}

	@objc private func showDisplayMenu()
	{
		makeDiffDisplayMenu().popUp(
			positioning: nil,
			at: NSPoint(
				x: 0,
				y: optionsButton.bounds.maxY
			),
			in: optionsButton
		)
		view.window?.makeFirstResponder(optionsButton)
	}

	@objc private func selectDisplayOption(_ sender: NSMenuItem)
	{
		var options = runtime.state.options
		switch sender.tag
		{
		case 0: options.loadFullFiles.toggle()
		case 2: options.showWordDiffs.toggle()
		case 3: options.ignoreWhitespace.toggle()
		case 4: options.ignoreImports.toggle()
		case 5:
			guard let command = runtime.state.copyCommand
			else
			{
				return
			}
			NSPasteboard.general.clearContents()
			let copied = NSPasteboard.general.setString(
				command,
				forType: .string
			)
			if copied
			{
				statusLabel.stringValue = "Copied git apply command "
					+ "for the unfiltered snapshot."
			}
			else
			{
				statusLabel.stringValue = "Clipboard copy failed."
			}
			return
		default: return
		}
		runtime.setOptions(options)
	}

}

@MainActor
private final class GitComparisonTreeNode: NSObject
{
	var row: GitDiffTreeRow
	var children: [NSObject] = []
	init(_ row: GitDiffTreeRow)
	{
		self.row = row
	}
}
