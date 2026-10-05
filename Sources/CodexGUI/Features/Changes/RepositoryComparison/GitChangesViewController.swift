import AppKit

/// Read-only Git comparison UI. Repository requests and snapshot ownership live in the runtime.
@MainActor
final class GitChangesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
	NSSearchFieldDelegate
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
	private let filterField = NSSearchField()
	private let tree = GitChangesTreeView()
	private let navigator = NSView()
	private let navigatorHost = NSView()
	private var navigatorDivider: NSView?
	private var navigatorTransition: GitNavigatorTransition?
	private var navigatorRequestedVisible: Bool?
	private var contentScroll = NSScrollView()
	private let sections = GitChangesSectionsView()
	private var treeRows: [GitDiffTreeRow] = []
	private var fileSections: [Data: GitDiffFileSectionView] = [:]
	private var fileSectionKeys: [Data: GitDiffFileSectionKey] = [:]
	private(set) var projectionCache = GitDiffProjectionCache()
	private var renderedSnapshotID: String?
	private var renderedOwner: FeaturePresentationOwner?
	private var renderedOptions: GitDiffPresentationOptions?
	private var rendering = false
	private var navigatorHidden = false
	private var internalChangesTab: NSView?
	private var revisionComparison: NSView?
	{
		comparisonToolbarView.revisionComparison
	}
	private var diffLayoutButton: NSButton?
	{
		comparisonToolbarView.diffLayoutButton
	}
	private var diffLayoutPreference = GitDiffLayoutPreference.automatic
	private var diffLayoutOwner: FeaturePresentationOwner?
	private var renderedComparisonScope: GitComparisonScope?
	private var diffViews: [GitAdaptiveDiffView] = []
	private var largeComparisonBanner: NSView?
	private let largeComparisonLabel = NSTextField(wrappingLabelWithString: "")
	private var previousFileButton: NSButton?
	private var nextFileButton: NSButton?
	private var renderedSelectedFileID: String?
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
	private var wrapsCode = false
	private var collapsedFileIDs: Set<String> = []
	private var collapseAllMode = false
	private var collapseSnapshotID: String?
	private var collapseOwner: FeaturePresentationOwner?
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
					$0.id == fileID
				}) == true
		else
		{
			return false
		}
		runtime.selectFile(fileID)
		scrollToFile(fileID)
		return true
	}

	func close()
	{
		runtime.close()
	}

	override func loadView()
	{
		let surface = DesktopSurface(DesktopTheme.canvas)
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
		configureDiffSectionsScrolling()
		let rule = DesktopSurface(DesktopTheme.paneDivider)
		navigatorDivider = rule
		rule.widthAnchor.constraint(equalToConstant: 1).isActive = true
		navigatorHost.wantsLayer = true
		navigatorHost.layer?.masksToBounds = true
		navigatorHost.addSubview(navigator)
		navigator.translatesAutoresizingMaskIntoConstraints = false
		let navigatorWidth = navigatorHost.widthAnchor.constraint(equalToConstant: 220)
		NSLayoutConstraint.activate([
			navigatorWidth,
			navigator.leadingAnchor.constraint(equalTo: navigatorHost.leadingAnchor),
			navigator.topAnchor.constraint(equalTo: navigatorHost.topAnchor),
			navigator.bottomAnchor.constraint(equalTo: navigatorHost.bottomAnchor),
			navigator.widthAnchor.constraint(equalToConstant: 220),
		])
		let body = AppKitLayout.horizontalStack(
			[contentScroll, rule, navigatorHost],
			spacing: 0
		)
		body.alignment = .top
		contentScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
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
		NSLayoutConstraint.activate([
			body.bottomAnchor.constraint(equalTo: layout.bottomAnchor),
			contentScroll.heightAnchor.constraint(equalTo: body.heightAnchor),
			navigatorHost.heightAnchor.constraint(equalTo: body.heightAnchor),
			rule.heightAnchor.constraint(equalTo: body.heightAnchor),
			sections.widthAnchor.constraint(equalTo: contentScroll.contentView.widthAnchor),
		])
		navigatorTransition = GitNavigatorTransition(
			widthConstraint: navigatorWidth,
			layoutView: surface,
			expandedWidth: 220
		)
		render(runtime.state)
	}

	override func viewDidLayout()
	{
		super.viewDidLayout()
		updateComparisonToolbarLayout()
		updateNavigatorVisibility(animated: false)
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

	private func configureDiffSectionsScrolling()
	{
		sections.orientation = .vertical
		sections.alignment = .leading
		sections.spacing = 0
		sections.translatesAutoresizingMaskIntoConstraints = false
		contentScroll = AppKitLayout.scrollableContent(
			sections,
			inset: 0
		)
		contentScroll.hasVerticalScroller = true
		contentScroll.hasHorizontalScroller = false
		contentScroll.autohidesScrollers = true
		contentScroll.drawsBackground = false
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
		let tab = pill(
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
		diffLayoutPreference = diffLayoutPreference.next
		applyDiffLayoutPreference()
	}

	private func applyDiffLayoutPreference()
	{
		for diff in diffViews
		{
			diff.layoutPreference = diffLayoutPreference
		}
		updateDiffLayoutButton()
		view.needsLayout = true
	}

	private func updateDiffLayoutButton()
	{
		let tooltip: String
		switch diffLayoutPreference
		{
		case .automatic: tooltip = "Auto diff: switch to unified diff"
		case .unified: tooltip = "Switch to split diff"
		case .split: tooltip = "Switch to auto diff"
		}
		diffLayoutButton?.toolTip = tooltip
		diffLayoutButton?.setAccessibilityValue(diffLayoutPreference.rawValue)
		diffLayoutButton?.image = GitReviewReferenceIcons.image(
			diffLayoutPreference == .unified ? .unifiedDisplayMode : .displayMode
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
		let banner = pill(
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

	private func pill(
		_ content: NSView,
		radius: CGFloat = 20,
		horizontalInset: CGFloat = 10,
		verticalInset: CGFloat = 10
	) -> NSView
	{
		let surface = DesktopSurface(
			DesktopTheme.elevated,
			cornerRadius: radius
		)
		surface.addSubview(content)
		content.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			content.leadingAnchor.constraint(
				equalTo: surface.leadingAnchor,
				constant: horizontalInset
			),
			content.trailingAnchor.constraint(
				equalTo: surface.trailingAnchor,
				constant: -horizontalInset
			),
			content.topAnchor.constraint(
				equalTo: surface.topAnchor,
				constant: verticalInset
			),
			content.bottomAnchor.constraint(
				equalTo: surface.bottomAnchor,
				constant: -verticalInset
			),
		])
		return surface
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
		filterField.placeholderString = "Filter files…"
		filterField.delegate = self
		filterField.font = .systemFont(ofSize: 14)
		filterField.isBezeled = false
		filterField.drawsBackground = false
		(filterField.cell as? NSSearchFieldCell)?.searchButtonCell?.image =
			GitReviewReferenceIcons.image(.search)
		filterField.setAccessibilityLabel("Filter changed files by path")
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
		tree.addTableColumn(column)
		tree.headerView = nil
		tree.rowHeight = 30
		tree.selectionHighlightStyle = .regular
		tree.style = .plain
		tree.backgroundColor = .clear
		tree.delegate = self
		tree.dataSource = self
		tree.target = self
		tree.action = #selector(selectTreeRow)
		tree.setAccessibilityLabel("Changed-file tree")
		tree.onNavigateDirectory =
		{
			[weak self] expand in self?.navigateDirectory(expand: expand)
		}
		tree.onActivateRow =
		{
			[weak self] in self?.activateSelectedRow()
		}
		let scroll = NSScrollView()
		scroll.documentView = tree
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.drawsBackground = false
		let filterSurface = DesktopSurface(
			DesktopTheme.canvas,
			cornerRadius: 10,
			bordered: true
		)
		AppKitLayout.pin(
			filterField,
			to: filterSurface,
			inset: 6
		)
		filterSurface.heightAnchor.constraint(equalToConstant: 36).isActive = true
		let stack = NSStackView(views: [filterSurface, scroll])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 8
		AppKitLayout.pin(
			stack,
			to: navigator,
			inset: 8
		)
		filterSurface.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		scroll.bottomAnchor.constraint(equalTo: stack.bottomAnchor).isActive = true
	}

	private func render(_ state: GitReviewState)
	{
		guard isViewLoaded
		else
		{
			return
		}
		if diffLayoutOwner != state.owner || !state.isOpen
		{
			diffLayoutOwner = state.owner
			diffLayoutPreference = .automatic
			applyDiffLayoutPreference()
		}
		if state.scope == .lastTurn, renderedComparisonScope != .lastTurn
		{
			diffLayoutPreference = .unified
			applyDiffLayoutPreference()
		}
		renderedComparisonScope = state.isOpen ? state.scope : nil
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
			projectionCache.clear()
			collapsedFileIDs.removeAll()
			collapseAllMode = false
			collapseSnapshotID = nil
			collapseOwner = nil
			removeSections()
			largeComparisonBanner?.isHidden = true
			treeRows = []
			tree.reloadData()
			return
		}
		if collapseSnapshotID != snapshot.id || collapseOwner != state.owner
		{
			collapsedFileIDs.removeAll()
			collapseAllMode = false
			collapseSnapshotID = snapshot.id
			collapseOwner = state.owner
		}
		updateCollapseDiffsButton(snapshot)
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
		projectionCache.prepare(for: presentation)
		treeRows = presentation.treeRows(
			filter: state.filter,
			expandedDirectories: state.expandedDirectories
		)
		tree.reloadData()
		if let selection = state.selectedFileID ?? displayedFileID,
			let row = treeRows.firstIndex(where:
			{
				$0.fileID == selection
			})
		{
			tree.selectRowIndexes(
				IndexSet(integer: row),
				byExtendingSelection: false
			)
		}
		if treeRows.isEmpty && !state.filter.isEmpty
		{
			statusLabel.stringValue += " · No matching filtered files."
			statusLabel.isHidden = false
		}
		updateDiffSections(
			presentation: presentation,
			selectedFileID: displayedFileID,
			usesSingleFile: usesSingleFile
		)
	}

	private func updateDiffSections(
		presentation: GitDiffPresentation,
		selectedFileID displayedFileID: String?,
		usesSingleFile: Bool
	)
	{
		let snapshot = presentation.snapshot
		let needsSectionUpdate = renderedSnapshotID != snapshot.id
			|| renderedOptions != presentation.options
			|| renderedSelectedFileID != displayedFileID || renderedOwner != snapshot.request.owner
		guard needsSectionUpdate
		else
		{
			return
		}
		let origin = contentScroll.contentView.bounds.origin
		let changesDisplayedFile = renderedSnapshotID != snapshot.id
			|| renderedOwner != snapshot.request.owner
			|| renderedSelectedFileID != displayedFileID
		let files = usesSingleFile
			? snapshot.files.filter
			{
				$0.id == displayedFileID
			} : snapshot.files
		reconcileFileSections(
			files,
			presentation: presentation
		)

		renderedSnapshotID = snapshot.id
		renderedOwner = snapshot.request.owner
		renderedOptions = presentation.options
		renderedSelectedFileID = displayedFileID
		sections.layoutSubtreeIfNeeded()
		contentScroll.contentView
			.scroll(to: usesSingleFile && changesDisplayedFile ? .zero : origin)
		contentScroll.reflectScrolledClipView(contentScroll.contentView)
	}

	private func reconcileFileSections(
		_ files: [GitComparisonFile],
		presentation: GitDiffPresentation
	)
	{
		var nextKeys: [Data: GitDiffFileSectionKey] = [:]
		for file in files
		{
			nextKeys[Data(file.id.utf8)] = GitDiffFileSectionKey(
				file: file,
				presentation: presentation,
				isCollapsed: collapsedFileIDs.contains(file.id)
			)
		}
		for (id, section) in fileSections where fileSectionKeys[id] != nextKeys[id]
		{
			sections.removeArrangedSubview(section)
			section.removeFromSuperview()
			fileSections.removeValue(forKey: id)
		}

		for (index, file) in files.enumerated()
		{
			let fileIdentity = Data(file.id.utf8)
			if let section = fileSections[fileIdentity]
			{
				if !sections.arrangedSubviews.indices.contains(index)
					|| sections.arrangedSubviews[index] !== section
				{
					sections.removeArrangedSubview(section)
					sections.insertArrangedSubview(
						section,
						at: index
					)
				}
				continue
			}
			let section = makeFileSection(
				file,
				presentation: presentation
			)
			sections.insertArrangedSubview(
				section,
				at: index
			)
			section.widthAnchor.constraint(equalTo: sections.widthAnchor).isActive = true
			fileSections[fileIdentity] = section
		}
		fileSectionKeys = nextKeys
		diffViews = files.flatMap
		{
			fileSections[Data($0.id.utf8)]?.diffViews ?? []
		}
	}

	private func makeFileSection(
		_ file: GitComparisonFile,
		presentation: GitDiffPresentation
	) -> GitDiffFileSectionView
	{
		let isCollapsed = collapsedFileIDs.contains(file.id)
		let rows = isCollapsed ? nil : projectionCache.file(
			file,
			presentation: presentation
		).rows
		return GitDiffFileSectionView(
			file: file,
			rows: rows,
			isCollapsed: isCollapsed,
			layoutPreference: diffLayoutPreference,
			wrapsCode: wrapsCode,
			onToggleFileDiff:
			{
				[weak self] button in self?.toggleFileDiff(button)
			},
			onExpandGap:
			{
				[weak self] button in self?.expandGap(button)
			}
		)
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
			if state.reportedChanges != nil
			{
				statusLabel.stringValue += " · recorded edits from the latest editing turn"
			}
			else
			{
				statusLabel.stringValue += " · pre-turn tracked files → "
					+ "current tracked working tree"
					+ "; includes later edits"
			}
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
		case .lastTurn: ("Pre-turn tracked files", "Current tracked working tree")
		}
	}

	private func removeSections()
	{
		diffViews.removeAll()
		for section in sections.arrangedSubviews
		{
			sections.removeArrangedSubview(section)
			section.removeFromSuperview()
		}
		fileSections = [:]
		fileSectionKeys = [:]
		renderedSnapshotID = nil
		renderedOwner = nil
		renderedOptions = nil
		renderedSelectedFileID = nil
	}

	func numberOfRows(in tableView: NSTableView) -> Int
	{
		treeRows.count
	}

	func tableView(
		_ tableView: NSTableView,
		viewFor tableColumn: NSTableColumn?,
		row: Int
	) -> NSView?
	{
		guard treeRows.indices.contains(row)
		else
		{
			return nil
		}
		let item = treeRows[row]
		let expanded = runtime.state.expandedDirectories.contains(item.path)
		let image = item.isDirectory
			? GitReviewReferenceIcons.image(expanded ? .chevronDown : .chevronRight)
			: GitReviewReferenceIcons.fileImage(
				relativePath: item.path,
				isDirectory: item.isDirectory
			)
		let icon = NSImageView(image: image)
		icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
		icon.setAccessibilityElement(false)
		let name = NSTextField(labelWithString: item.name)
		name.lineBreakMode = .byTruncatingMiddle
		name.font = .systemFont(ofSize: 13)
		name.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		var views: [NSView] = [icon, name, GitReviewControls.spacer()]
		if let fileID = item.fileID,
			let file = runtime.state.snapshot?.files.first(where:
			{
				$0.id == fileID
			})
		{
			let plus = NSTextField(labelWithString: "+\(file.additions)")
			plus.textColor = .systemGreen
			let minus = NSTextField(labelWithString: "-\(file.deletions)")
			minus.textColor = .systemRed
			if file.additions > 0
			{
				views.append(plus)
			}
			if file.deletions > 0
			{
				views.append(minus)
			}
		}
		let cell = GitReviewTreeCell(views: views)
		cell.orientation = .horizontal
		cell.alignment = .centerY
		cell.spacing = 6
		cell.guideDepth = item.depth
		cell.edgeInsets = NSEdgeInsets(
			top: 0,
			left: CGFloat(8 + 16 * item.depth),
			bottom: 0,
			right: 4
		)
		cell.toolTip = item.path
		cell.setAccessibilityLabel((item.isDirectory ? "Directory " : "Changed file ") + item.path)
		return cell
	}

	func tableViewSelectionDidChange(_ notification: Notification)
	{
		guard !rendering, treeRows.indices.contains(tree.selectedRow),
				let file = treeRows[tree.selectedRow].fileID
		else
		{
			return
		}
		runtime.selectFile(file)
		scrollToFile(file)
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

	private func navigateDirectory(expand: Bool)
	{
		guard treeRows.indices.contains(tree.selectedRow)
		else
		{
			return
		}
		let row = treeRows[tree.selectedRow]
		guard row.isDirectory
		else
		{
			return
		}
		if runtime.state.expandedDirectories
			.contains(row.path) != expand
		{
			runtime.toggleDirectory(row.path)
		}
	}

	private func activateSelectedRow()
	{
		guard treeRows.indices.contains(tree.selectedRow)
		else
		{
			return
		}
		let row = treeRows[tree.selectedRow]
		if row.isDirectory
		{
			runtime.toggleDirectory(row.path)
		}
		else if let id = row.fileID
		{
			runtime.selectFile(id)
			scrollToFile(id)
		}
	}

	private func scrollToFile(_ id: String)
	{
		guard let section = fileSections[Data(id.utf8)]
		else
		{
			return
		}
		guard let document = contentScroll.documentView
		else
		{
			return
		}
		contentScroll.layoutSubtreeIfNeeded()
		document.layoutSubtreeIfNeeded()
		let sectionRect = section.convert(
			section.bounds,
			to: document
		)
		let clip = contentScroll.contentView
		let maximumY = max(
			0,
			document.bounds.height - clip.bounds.height
		)
		clip.scroll(to: NSPoint(
			x: clip.bounds.minX,
			y: min(
				maximumY,
				max(
					0,
					sectionRect.minY
				)
			)
		))
		contentScroll.reflectScrolledClipView(clip)
		section.setAccessibilityLabel("Selected changed file: \(id)")
	}

	@objc private func selectTreeRow()
	{
		guard treeRows.indices.contains(tree.clickedRow)
		else
		{
			return
		}
		let row = treeRows[tree.clickedRow]
		if row.isDirectory
		{
			runtime.toggleDirectory(row.path)
		}
		else if let file = row.fileID
		{
			runtime.selectFile(file)
			scrollToFile(file)
		}
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
		navigatorHidden.toggle()
		updateNavigatorVisibility(animated: true)
	}

	private func updateNavigatorVisibility(animated: Bool)
	{
		let visible = !navigatorHidden && view.bounds.width >= 500
		guard navigatorRequestedVisible != visible
		else
		{
			return
		}
		let wasInitialized = navigatorRequestedVisible != nil
		navigatorRequestedVisible = visible
		if visible
		{
			navigator.isHidden = false
			navigatorDivider?.isHidden = false
		}
		navigatorTransition?.setVisible(
			visible,
			animated: animated && wasInitialized
		)
		{
			[weak self] in
			guard let self, self.navigatorRequestedVisible == visible
			else
			{
				return
			}
			if !visible
			{
				self.navigator.isHidden = true
				self.navigatorDivider?.isHidden = true
			}
		}
		updateNavigatorToggleAppearance()
	}

	private func updateNavigatorToggleAppearance()
	{
		let visible = navigatorRequestedVisible == true
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
			$0.id == selectedFileID
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
		guard let snapshot = state.snapshot, let owner = state.owner,
				state.pendingRequest == nil,
				let index = snapshot.files.firstIndex(where:
				{
					$0.id == (state.selectedFileID ?? snapshot.files.first?.id)
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
		wrapsCode.toggle()
		wordWrapButton?
			.setAccessibilityLabel(wrapsCode ? "Stop wrapping code lines" : "Wrap code lines")
		wordWrapButton?.toolTip = wrapsCode ? "Stop wrapping code lines" : "Wrap code lines"
		wordWrapButton?.setAccessibilityValue(wrapsCode ? "On" : "Off")
		for diff in diffViews
		{
			diff.wrapsCode = wrapsCode
		}
	}

	@objc private func toggleAllDiffs()
	{
		guard let snapshot = runtime.state.snapshot
		else
		{
			return
		}
		collapseAllMode.toggle()
		collapsedFileIDs = collapseAllMode ? Set(snapshot.files.map(\.id)) : []
		refreshSections()
	}

	@objc private func toggleFileDiff(_ sender: NSButton)
	{
		guard let id = sender.identifier?.rawValue,
				runtime.state.snapshot?.files.contains(where:
				{
					$0.id == id
				}) == true
		else
		{
			return
		}
		if !collapsedFileIDs.insert(id).inserted
		{
			collapsedFileIDs.remove(id)
		}
		refreshSections()
	}

	private func refreshSections()
	{
		renderedOptions = nil
		render(runtime.state)
	}

	private func updateCollapseDiffsButton(_ snapshot: GitComparisonSnapshot)
	{
		let title = collapseAllMode ? "Expand all diffs" : "Collapse all diffs"
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

	func tableView(
		_ tableView: NSTableView,
		rowViewForRow row: Int
	) -> NSTableRowView?
	{
		GitReviewFileRowView()
	}

	@objc private func changeRevisions()
	{
		runtime.setRevisions(
			base: baseField.stringValue,
			target: targetField.stringValue
		)
	}
	@objc private func expandGap(_ sender: NSButton)
	{
		if let id = sender.identifier?.rawValue
		{
			runtime.expandGap(id)
		}
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
					wrapsCode ? "Stop wrapping code lines" : "Wrap code lines",
					#selector(toggleWordWrap),
					true,
					wrapsCode ? .on : .off
				),
				(
					collapseAllMode ? "Expand all diffs" : "Collapse all diffs",
					#selector(toggleAllDiffs),
					!(runtime.state.snapshot?.files.isEmpty ?? true),
					collapseAllMode ? .on : .off
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
private final class GitChangesSectionsView: NSStackView
{
	override var isFlipped: Bool
	{
		true
	}
}

@MainActor
private final class GitChangesTreeView: NSTableView
{
	var onNavigateDirectory: ((Bool) -> Void)?
	var onActivateRow: (() -> Void)?

	override func keyDown(with event: NSEvent)
	{
		switch event.keyCode
		{
		case 123: onNavigateDirectory?(false)
		case 124: onNavigateDirectory?(true)
		case 36, 76: onActivateRow?()
		default: super.keyDown(with: event)
		}
	}
}
