import AppKit

@MainActor
final class InspectorViewController: NSViewController
{
	private typealias Layout = LayoutTokens.Inspector

	static var summaryPaneWidth: CGFloat
	{
		Layout.summaryPaneWidth
	}

	let gitChanges = GitChangesViewController()
	let panels = ContextPanelShell()
	let changes = ChangesViewController()
	let summary = PinnedSummaryViewController()
	var conversationSources: ConversationSourcesViewController?
	var conversationSubagents: SubagentsViewController?
	let toolsTabs = ToolsTabViewController()
	private(set) var isShowingTools = false
	private var isShowingExpandedConversation = false
	private var expandedConversationSummaryRevealed = false
	var onToolsClose: ((Bool) -> Void)?
	var onPaneContentChange: (() -> Void)?
	var onToolChangesSelected: (() -> Void)?
	private var summaryVisible = true
	private(set) var isShowingDetails = false
	var hasPaneContent: Bool
	{
		summaryVisible || isShowingDetails || isShowingTools
	}

	private var renderedOwner: FeaturePresentationOwner?
	private weak var inspectorBox: InspectorBoxSurface?
	private let headerDivider = DesktopSurface(AppKitColorTokens.border)
	var onSummaryDisplayChange: ((Bool) -> Void)?
	private let content = NSView()
	private let projectLabel = NSTextField(labelWithString: "Project")
	private var preferredBoxHeight: NSLayoutConstraint?
	private var hasReviewContent = false
	private var summaryTransition: PinnedSummaryTransition?
	private var summaryTransitionRevision = 0

	private var fullHeightConstraint: NSLayoutConstraint?
	private var maximumHeightConstraint: NSLayoutConstraint?
	var onDetailGeometryChange: ((Bool) -> Void)?
	var onCloseDetail: ((ContextPanelDestination?) -> Void)?
	private var boxEdgeConstraints: [NSLayoutConstraint] = []
	private var summaryLeadingConstraint: NSLayoutConstraint?
	private var summaryWidthLimitConstraint: NSLayoutConstraint?
	private var summaryPreferredWidthConstraint: NSLayoutConstraint?
	private var contentEdgeConstraints: [NSLayoutConstraint] = []
	private(set) var isGitReviewFocused = false
	var onGitReviewDisplayChange: ((Bool) -> Void)?

	func setGitReviewFocused(_ focused: Bool)
	{
		guard focused != isGitReviewFocused
		else
		{
			return
		}
		isGitReviewFocused = focused
		gitChanges.isExpanded = focused
		onGitReviewDisplayChange?(focused)
		updateContentVisibility()
	}

	override func loadView()
	{
		let container = DesktopSurface(AppKitColorTokens.canvas)
		let box = makeInspectorBox(in: container)

		configureHeaderControls()
		installInspectorContent(in: box)

		view = container
		installToolsPane(in: container)
		configureToolsPaneCallbacks()
		configureDetailPanels()
		installSummaryAndDetailContent()
	}

	private func installToolsPane(in container: NSView)
	{
		addChild(toolsTabs)
		AppKitLayout.pin(
			toolsTabs.view,
			to: container,
			inset: 0
		)
		toolsTabs.view.isHidden = true
		toolsTabs.setContentVisible(false)
	}

	private func configureToolsPaneCallbacks()
	{
		toolsTabs.onCloseLastTab =
		{
			[weak self] in self?.closeToolsPane()
		}
		toolsTabs.onClosePane =
		{
			[weak self] in self?.closeToolsPane()
		}
		toolsTabs.onChangesSelectionChange =
		{
			[weak self] in
			guard let self, self.isShowingTools, self.toolsTabs.isChangesSelected
			else
			{
				return
			}
			self.attachGitChangesToSelectedToolTab()
			self.onToolChangesSelected?()
		}
		toolsTabs.onChangesTabClosed =
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			self.toolsTabs.detachChanges()
			self.gitChanges.close()
		}
	}

	private func configureDetailPanels()
	{
		panels.register(
			gitChanges,
			for: .changes,
			providesHeader: true
		)
		panels.register(
			changes,
			for: .reportedChanges
		)
		gitChanges.onClose =
		{
			[weak self] in self?.showSummary()
		}
		gitChanges.onShowReportedChanges =
		{
			[weak self] in
			guard let self, let owner = self.renderedOwner
			else
			{
				return
			}
			self.open(ContextPanelRequest(
				owner: owner,
				destination: .reportedChanges
			))
		}
	}

	private func installSummaryAndDetailContent()
	{
		summary.onContentHeightChange =
		{
			[weak self] in self?.updateBoxHeight()
		}
		addChild(summary)
		AppKitLayout.pin(
			summary.view,
			to: content,
			inset: 0
		)
		addChild(panels)
		AppKitLayout.pin(
			panels.view,
			to: content,
			inset: 0
		)
		panels.view.isHidden = true
		panels.onClose =
		{
			[weak self] in self?.showSummary()
		}
	}

	func renderSummary(
		_ presentation: PinnedSummaryPresentation,
		visible: Bool
	)
	{
		_ = view
		let ownerChanged = renderedOwner != presentation.owner
		if ownerChanged || summaryVisible != visible
		{
			cancelSummaryTransition()
		}
		if ownerChanged
		{
			if gitChanges.runtime.state.isOpen
			{
				gitChanges.close()
			}
			setGitReviewFocused(false)
			isShowingDetails = false
			expandedConversationSummaryRevealed = false
		}
		renderedOwner = presentation.owner
		if ownerChanged
		{
			toolsTabs.removeSourcesTab()
			toolsTabs.removeSubagentsTab()
		}
		summaryVisible = visible
		summary.render(presentation)
		updateContentVisibility()
		if isShowingTools && toolsTabs.isChangesSelected &&
			(ownerChanged || !gitChanges.runtime.state.isOpen)
		{
			onToolChangesSelected?()
		}
	}

	@discardableResult
	func open(_ request: ContextPanelRequest) -> Bool
	{
		guard request.owner == renderedOwner,
				panels.availableDestinations.contains(request.destination)
		else
		{
			return false
		}
		if request.destination != .changes, gitChanges.runtime.state.isOpen
		{
			gitChanges.close()
		}
		if request.destination == .changes
		{
			toolsTabs.detachChanges()
			gitChanges.showsInternalChangesTab = true
		}
		guard panels.open(request)
		else
		{
			return false
		}
		cancelSummaryTransition()
		isShowingTools = false
		isShowingDetails = true
		// Opening a detail uses the right inspector. Full-width Changes requires
		// the explicit expand or panel control.
		setGitReviewFocused(false)
		if request.destination == .changes
		{
			gitChanges.isExpanded = false
		}
		updateContentVisibility()
		return true
	}

	func showSummary()
	{
		if gitChanges.runtime.state.isOpen
		{
			gitChanges.close()
		}
		setGitReviewFocused(false)
		isShowingTools = false
		isShowingDetails = false
		updateContentVisibility()
	}

	var isSummaryBesideExpandedConversation: Bool
	{
		isShowingTools && isShowingExpandedConversation && expandedConversationSummaryRevealed
			&& summaryVisible
	}

	func setExpandedConversation(
		_ active: Bool,
		resetSummary: Bool
	)
	{
		if isShowingExpandedConversation != active
		{
			cancelSummaryTransition()
		}
		isShowingExpandedConversation = active
		if resetSummary
		{
			expandedConversationSummaryRevealed = false
		}
		updateContentVisibility()
	}

	func showSummaryBesideExpandedConversation()
	{
		if gitChanges.runtime.state.isOpen
		{
			gitChanges.close()
		}
		setGitReviewFocused(false)
		expandedConversationSummaryRevealed = true
		isShowingDetails = false
		updateContentVisibility()
	}

	func showReportedChanges()
	{
		guard let owner = renderedOwner
		else
		{
			return
		}
		open(ContextPanelRequest(
			owner: owner,
			destination: .reportedChanges
		))
	}

	func showToolsTab()
	{
		if gitChanges.runtime.state.isOpen && toolsTabs.changesTabID == nil
		{
			gitChanges.close()
		}
		setGitReviewFocused(false)
		cancelSummaryTransition()
		_ = view
		toolsTabs.openNewTab()
		isShowingTools = true
		updateContentVisibility()
	}

	/// Clears the previous surface before caching the opening transition, preserving pane geometry.
	func hideContentForToolsOpening()
	{
		cancelSummaryTransition()
		_ = view
		inspectorBox?.isHidden = true
		toolsTabs.view.isHidden = true
	}

	func showToolsPane()
	{
		if gitChanges.runtime.state.isOpen && toolsTabs.changesTabID == nil
		{
			gitChanges.close()
		}
		setGitReviewFocused(false)
		cancelSummaryTransition()
		_ = view
		if toolsTabs.tabCount == 0
		{
			toolsTabs.openNewTab()
		}
		isShowingTools = true
		updateContentVisibility()
		if toolsTabs.isChangesSelected
		{
			attachGitChangesToSelectedToolTab()
			onToolChangesSelected?()
		}
	}

	func showGitChangesInSelectedToolTab(
		owner: FeaturePresentationOwner,
		lastTurnID: String?,
		baselineRevision: Int,
		baselineFailure: GitComparisonFailure?
	)
	{
		guard isShowingTools, toolsTabs.selectedTabID != nil
		else
		{
			return
		}
		gitChanges.showsInternalChangesTab = false
		toolsTabs.showChanges(gitChanges)
		gitChanges.activate(
			owner: owner,
			lastTurnID: lastTurnID,
			baselineRevision: baselineRevision,
			baselineFailure: baselineFailure
		)
	}

	@discardableResult
	func openSourcesInToolTab(_ request: ContextPanelRequest) -> Bool
	{
		guard request.destination == .sources, request.owner == renderedOwner,
				let controller = conversationSources, controller.owner == request.owner,
				request.recordID == nil || controller.sources.record(
				for: request,
				owner: request.owner
				) != nil
		else
		{
			return false
		}
		prepareToolTabOpening()
		toolsTabs.showSources(controller)
		controller.select(request)
		updateContentVisibility()
		return true
	}

	@discardableResult
	func openSubagentsInToolTab(_ request: ContextPanelRequest) -> Bool
	{
		guard request.destination == .subagents, request.owner == renderedOwner,
				let controller = conversationSubagents, controller.owner == request.owner,
				request.recordID == nil
		else
		{
			return false
		}
		prepareToolTabOpening()
		toolsTabs.showSubagents(controller)
		updateContentVisibility()
		return true
	}

	private func prepareToolTabOpening()
	{
		_ = view
		cancelSummaryTransition()
		if gitChanges.runtime.state.isOpen, toolsTabs.changesTabID == nil
		{
			gitChanges.close()
		}
		isShowingTools = true
		isShowingDetails = false
		setGitReviewFocused(false)
	}

	private func attachGitChangesToSelectedToolTab()
	{
		guard toolsTabs.isChangesSelected
		else
		{
			return
		}
		gitChanges.showsInternalChangesTab = false
		toolsTabs.showChanges(gitChanges)
	}

	func closeToolsPane()
	{
		if isShowingDetails, panels.destination == .changes, gitChanges.parent !== panels
		{
			isShowingDetails = false
		}
		isShowingTools = false
		updateContentVisibility()
		onToolsClose?(isShowingDetails || summaryVisible)
	}

	func animateSummaryVisibilityChange(_ updates: () -> Void)
	{
		cancelSummaryTransition()
		_ = view
		guard !isShowingTools || (isShowingExpandedConversation && !isSummaryDisplayed),
				!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		else
		{
			updates()
			return
		}
		let wasDisplayed = isSummaryDisplayed
		let closingTransition = wasDisplayed
			? inspectorBox.flatMap
			{
				PinnedSummaryTransition(view: $0)
			} : nil
		updates()
		view.window?.layoutIfNeeded()
		view.layoutSubtreeIfNeeded()
		let isDisplayed = isSummaryDisplayed
		guard wasDisplayed != isDisplayed
		else
		{
			return
		}
		let transition = isDisplayed
			? inspectorBox.flatMap
			{
				PinnedSummaryTransition(view: $0)
			} : closingTransition
		guard let transition
		else
		{
			return
		}
		summaryTransitionRevision += 1
		let revision = summaryTransitionRevision
		summaryTransition = transition
		transition.animate(appearing: isDisplayed)
		{
			[weak self] in
			guard let self, self.summaryTransitionRevision == revision
			else
			{
				return
			}
			self.summaryTransition = nil
		}
	}

	private var isSummaryDisplayed: Bool
	{
		guard summaryVisible, !isShowingDetails,
				!isShowingTools || isSummaryBesideExpandedConversation, let inspectorBox
		else
		{
			return false
		}
		return !inspectorBox.isHiddenOrHasHiddenAncestor
	}

	private func cancelSummaryTransition()
	{
		summaryTransitionRevision += 1
		summaryTransition?.cancel()
		summaryTransition = nil
	}

	private func updateContentVisibility()
	{
		let showDetails = isShowingDetails && !isShowingTools
		summary.view.isHidden = showDetails || !summaryVisible
		panels.view.isHidden = !showDetails

		let showSummary = !isShowingTools ? summaryVisible : isSummaryBesideExpandedConversation
		inspectorBox?.isHidden = !showDetails && !showSummary
		toolsTabs.view.isHidden = !isShowingTools || isShowingExpandedConversation
		toolsTabs.setContentVisible(!toolsTabs.view.isHidden)

		let fullBleedChanges = showDetails && [.changes, .sources].contains(panels.destination)
		inspectorBox?.isSummaryCard = !showDetails
		inspectorBox?.isFullBleed = fullBleedChanges
		boxEdgeConstraints[0].isActive = showDetails
		summaryLeadingConstraint?.isActive = !showDetails
		summaryWidthLimitConstraint?.isActive = !showDetails
		summaryPreferredWidthConstraint?.isActive = !showDetails
		projectLabel.isHidden = !showDetails || fullBleedChanges
		headerDivider.isHidden = !showDetails || fullBleedChanges
		updateInspectorGeometry(
			showDetails: showDetails,
			fullBleedChanges: fullBleedChanges
		)

		let wideDetail = showDetails && [.changes, .sources].contains(panels.destination)
		onDetailGeometryChange?(wideDetail)
		onSummaryDisplayChange?(showSummary && !showDetails)
		updateBoxHeight()
		onPaneContentChange?()
	}

	private func updateInspectorGeometry(
		showDetails: Bool,
		fullBleedChanges: Bool
	)
	{
		for (index, constraint) in boxEdgeConstraints.enumerated()
		{
			let isTrailingOrBottomEdge = index == 1 || index == 3
			constraint.constant = fullBleedChanges
				? 0 : (isTrailingOrBottomEdge ? -Layout.boxInset : Layout.boxInset)
			if index == 1, !showDetails
			{
				constraint.constant = -Layout.summaryTrailingInset
			}
		}
		fullHeightConstraint?.constant = fullBleedChanges ? 0 : -Layout.boxInset
		for (index, constraint) in contentEdgeConstraints.enumerated()
		{
			let isTrailingOrBottomEdge = index == 1 || index == 3
			let inset: CGFloat
			if fullBleedChanges
			{
				inset = 0
			}
			else if !showDetails
			{
				inset = index < 2
					? Layout.summaryHorizontalInset : Layout.summaryVerticalInset
			}
			else
			{
				inset = Layout.contentInset
			}
			constraint.constant = isTrailingOrBottomEdge ? -inset : inset
		}
		let fullHeightDetail = showDetails && [.changes, .sources]
			.contains(panels.destination)
		maximumHeightConstraint?.isActive = !fullHeightDetail
		fullHeightConstraint?.isActive = fullHeightDetail
	}

	private func makeInspectorBox(in container: NSView) -> NSView
	{
		let box = InspectorBoxSurface()
		box.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(box)
		inspectorBox = box
		let preferredHeight = box.heightAnchor.constraint(equalToConstant: Layout.initialBoxHeight)
		// The box may yield space without raising the window's minimum content height.
		preferredHeight.priority = NSLayoutConstraint.Priority(1)
		preferredBoxHeight = preferredHeight
		maximumHeightConstraint = box.heightAnchor
			.constraint(lessThanOrEqualToConstant: Layout.detailHeight)
		fullHeightConstraint = box.bottomAnchor.constraint(
			equalTo: container.bottomAnchor,
			constant: -Layout.boxInset
		)
		boxEdgeConstraints = [
			box.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: Layout.boxInset
			),
			box.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -Layout.boxInset
			),
			box.topAnchor.constraint(
				equalTo: container.topAnchor,
				constant: Layout.boxInset
			),
			box.bottomAnchor.constraint(
				lessThanOrEqualTo: container.bottomAnchor,
				constant: -Layout.boxInset
			),
		]
		summaryLeadingConstraint = box.leadingAnchor.constraint(
			greaterThanOrEqualTo: container.leadingAnchor,
			constant: 0
		)
		summaryWidthLimitConstraint = box.widthAnchor
			.constraint(lessThanOrEqualToConstant: Layout.summaryWidth)
		let preferredSummaryWidth = box.widthAnchor.constraint(equalToConstant: Layout.summaryWidth)
		preferredSummaryWidth.priority = NSLayoutConstraint.Priority(999)
		summaryPreferredWidthConstraint = preferredSummaryWidth
		NSLayoutConstraint.activate(boxEdgeConstraints + [
			maximumHeightConstraint!,
			preferredHeight
		])
		return box
	}

	private func configureHeaderControls()
	{
		projectLabel.font = AppKitFontResolver.font(TypographyTokens.Summary.body)
		projectLabel.textColor = .secondaryLabelColor
		projectLabel.lineBreakMode = .byTruncatingMiddle
		projectLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		projectLabel.setAccessibilityLabel("Inspector project")
	}

	private func installInspectorContent(in box: NSView)
	{
		let divider = headerDivider
		let stack = AppKitLayout.verticalStack(
			[projectLabel, divider, content],
			spacing: 12
		)
		box.addSubview(stack)
		stack.translatesAutoresizingMaskIntoConstraints = false
		contentEdgeConstraints = [
			stack.leadingAnchor.constraint(
				equalTo: box.leadingAnchor,
				constant: Layout.contentInset
			),
			stack.trailingAnchor.constraint(
				equalTo: box.trailingAnchor,
				constant: -Layout.contentInset
			),
			stack.topAnchor.constraint(
				equalTo: box.topAnchor,
				constant: Layout.contentInset
			),
			stack.bottomAnchor.constraint(
				equalTo: box.bottomAnchor,
				constant: -Layout.contentInset
			),
		]
		NSLayoutConstraint.activate(contentEdgeConstraints)
		projectLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
		content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		content.bottomAnchor.constraint(equalTo: stack.bottomAnchor).isActive = true
		content.setContentHuggingPriority(
			.defaultLow,
			for: .vertical
		)
	}

	/// Updates the floating inspector's heading and height; child controllers render their own
	/// state.
	func render(_ snapshot: ConversationSnapshot)
	{
		render(ReviewPresentation(snapshot))
	}
	func render(_ snapshot: ReviewPresentation)
	{
		projectLabel.stringValue =
			snapshot.projectPath.map
				{
					URL(fileURLWithPath: $0).lastPathComponent
				} ?? "Project"
		projectLabel.toolTip = snapshot.projectPath
		if let review = snapshot.selectedReview
		{
			hasReviewContent = !review.files.isEmpty
		}
		else
		{
			hasReviewContent =
				snapshot.reviewTurns
					.isEmpty && (!snapshot.changedFiles.isEmpty || !snapshot.diff.isEmpty)
		}
		updateBoxHeight()
	}

	private func updateBoxHeight()
	{
		preferredBoxHeight?.constant = isShowingDetails
			? Layout.detailHeight
			: min(
				Layout.detailHeight,
				summary.preferredContentHeight + 2 * Layout.summaryVerticalInset
			)
	}
}

@MainActor
private final class InspectorBoxSurface: NSView
{
	private static let cornerRadius = ShapeTokens.Inspector.summaryRadius
	private let depthLayers = ShadowTokens.summary.map
	{
		_ in CALayer()
	}

	var isSummaryCard = true
	{
		didSet
		{
			updateShadow()
			needsDisplay = true
		}
	}

	var isFullBleed = false
	{
		didSet
		{
			updateShadow()
			needsDisplay = true
		}
	}

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		wantsLayer = true
		for depth in depthLayers
		{
			layer?.insertSublayer(
				depth,
				at: 0
			)
		}
		updateShadow()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func layout()
	{
		super.layout()
		updateShadow()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		updateShadow()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		(isSummaryCard ? AppKitColorTokens.summaryCard : AppKitColorTokens.inspector).setFill()
		let radius: CGFloat = isFullBleed ? 0 :
			(isSummaryCard ? Self.cornerRadius : ShapeTokens.Inspector.detailRadius)
		let borderWidth: CGFloat = isSummaryCard && !isFullBleed ? ShapeTokens.Inspector
			.summaryEdgeWidth : 0
		let path = NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: borderWidth / 2,
				dy: borderWidth / 2
			),
			xRadius: radius,
			yRadius: radius
		)
		path.fill()
		if borderWidth > 0
		{
			AppKitColorTokens.summaryEdge.setStroke()
			path.lineWidth = borderWidth
			path.stroke()
		}
	}

	private func updateShadow()
	{
		guard let layer
		else
		{
			return
		}
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		layer.masksToBounds = false
		for (shadow, depth) in zip(
			ShadowTokens.summary,
			depthLayers
		)
		{
			depth.isHidden = !isSummaryCard || isFullBleed
			AppKitShadowRenderer.apply(
				shadow,
				to: depth,
				in: self,
				cornerRadius: Self.cornerRadius
			)
		}
		CATransaction.commit()
	}
}
