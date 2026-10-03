import AppKit

/// Owns split-pane geometry, responsive collapse decisions, and persisted divider choices.
@MainActor
final class WindowPaneController
{
	private weak var window: NSWindow?
	private let navigation: NavigationViewController
	private let inspector: InspectorViewController
	private let conversation: ConversationViewController
	private let conversationContainer: ClippedPaneViewController
	private let reviewContainer: ClippedPaneViewController
	private var conversationIsInExpandedPane = false
	let split: NSSplitViewController
	private let reviewPane: NSSplitViewItem
	private let conversationPane: NSSplitViewItem
	private(set) var isToolsExpanded = false
	private let layoutStore: WindowLayoutStore?
	private var expandedNavigationWidth = WindowPaneLayout.navigationWidth
	private var expandedReviewWidth = WindowPaneLayout.reviewWidth
	private var expandedToolsWidth = WindowPaneLayout.reviewWidth
	private var usesToolsSizing = false
	private var reviewVisibility: WindowReviewVisibility = .automatic
	private var reviewAutomaticallyCollapsed = false
	private var hasPresentedWindow = false
	private var isApplyingPaneLayout = false
	private(set) var isAnimatingToolsExpansion = false
	private var toolsExpansionRevision = 0
	private var toolsPaneTransition: ToolsPaneTransition?
	private var reviewDragSettings: ReviewDragSettings?
	private var lastDraggedReviewWidth: CGFloat?
	var onToolsExpansionFinished: (() -> Void)?
	var onToolsExpansionLayoutChanged: (() -> Void)?
	private var lastAppliedSplitWidth: CGFloat?

	var reviewViewportWidth: CGFloat
	{
		reviewPane.isCollapsed ? 0 : reviewPane.viewController.view.frame.width
	}

	var isShowingExpandedConversation: Bool
	{
		isToolsExpanded && inspector.isShowingTools && inspector.toolsTabs.isConversationSelected
	}

	var tabViewportWidth: CGFloat
	{
		if isToolsExpanded, !isAnimatingToolsExpansion
		{
			let navigationWidth = split.splitViewItems[0].isCollapsed
				? 0 : expandedNavigationWidth + split.splitView.dividerThickness
			return max(
				0,
				split.splitView.bounds.width - navigationWidth
			)
		}
		return reviewViewportWidth
	}

	private var workspaceFilesExpanded = false
	private var workspaceFilesWidth: CGFloat = 760
	private var savedGitReviewLayout: GitReviewLayout?
	private(set) var isGitReviewFocused = false

	private struct GitReviewLayout
	{
		let navigationCollapsed: Bool
		let conversationCollapsed: Bool
		let conversationCanCollapse: Bool
		let reviewVisibility: WindowReviewVisibility
		let workspaceFilesExpanded: Bool
	}

	private struct ReviewDragSettings
	{
		let minimumThickness: CGFloat
		let canCollapse: Bool
		let canCollapseFromWindowResize: Bool
	}

	init(
		navigation: NavigationViewController,
		conversation: ConversationViewController,
		inspector: InspectorViewController,
		layoutStore: WindowLayoutStore?
	)
	{
		self.navigation = navigation
		self.inspector = inspector
		self.conversation = conversation
		self.layoutStore = layoutStore
		conversationContainer = ClippedPaneViewController(
			content: conversation,
			minimumContentWidth: WindowPaneLayout.conversationMinimumWidth
		)
		reviewContainer = ClippedPaneViewController(
			content: inspector,
			minimumContentWidth: WindowPaneLayout.reviewMinimumWidth
		)
		let split = ConversationSplitViewController()
		let splitView = ConversationSplitView(frame: .zero)
		split.splitView = splitView
		split.splitView.isVertical = true
		split.splitView.dividerStyle = .thin
		let navigationPane = Self.pane(
			navigation,
			minimumWidth: WindowPaneLayout.navigationMinimumWidth,
			maximumWidth: WindowPaneLayout.navigationMaximumWidth,
			holdingPriority: WindowPaneLayout.sideHoldingPriority
		)
		navigationPane.canCollapse = true
		navigationPane.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
		split.addSplitViewItem(navigationPane)
		conversationPane = Self.pane(
			conversationContainer,
			minimumWidth: WindowPaneLayout.conversationMinimumWidth
		)
		conversationPane.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
		split.addSplitViewItem(conversationPane)
		reviewPane = Self.pane(
			reviewContainer,
			minimumWidth: WindowPaneLayout.reviewMinimumWidth,
			maximumWidth: WindowPaneLayout.reviewMaximumWidth,
			holdingPriority: WindowPaneLayout.sideHoldingPriority
		)
		reviewPane.canCollapse = true
		reviewPane.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
		split.addSplitViewItem(reviewPane)

		self.split = split
		inspector.toolsTabs.onTabSelectionChange =
		{
			[weak self] in self?.updateExpandedTabSelection()
		}
		inspector.onPaneContentChange =
		{
			[weak self] in self?.updateInspectorSizing()
		}
		split.onLayout =
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			if self.reviewDragSettings != nil, !self.reviewPane.isCollapsed
			{
				self.lastDraggedReviewWidth = self.reviewViewportWidth
			}
			self.applyResponsivePaneLayout()
		}
		splitView.onDividerInteractionEnded =
		{
			[weak self] index, requestedWidth in
			self?.endDividerInteraction(
				at: index,
				requestedWidth: requestedWidth
			)
		}
		splitView.onDividerInteractionBegan =
		{
			[weak self] index in self?.beginDividerInteraction(at: index)
		}

	}

	func restoreLayout(in window: NSWindow)
	{
		self.window = window
		if let layout = layoutStore?.layout
		{
			window.setFrame(
				layout.visibleFrame(
					on: NSScreen.screens.map(\.visibleFrame),
					minimumSize: window.minSize
				),
				display: false
			)
			expandedNavigationWidth = WindowPaneLayout
				.restoredNavigationWidth(layout.navigationWidth)
			expandedReviewWidth = WindowPaneLayout.restoredReviewWidth(layout.reviewWidth)
			split.splitViewItems[0].isCollapsed = layout.navigationCollapsed ?? false
			reviewVisibility =
				layout.reviewVisibility ?? (layout.reviewCollapsed ? .collapsed : .automatic)
			reviewPane.isCollapsed = reviewVisibility == .collapsed
		}
		else
		{
			reviewPane.isCollapsed = true
			window.setFrame(
				NSRect(
					origin: window.frame.origin,
					size: NSSize(
						width: 1200,
						height: 760
					)
				),
				display: false
			)
			window.center()
		}
	}

	func didPresentWindow()
	{
		hasPresentedWindow = true
		applyResponsivePaneLayout(force: true)
	}

	func saveLayout()
	{
		guard let window
		else
		{
			return
		}
		let navigationCollapsed = savedGitReviewLayout?.navigationCollapsed
			?? split.splitViewItems[0].isCollapsed
		layoutStore?.layout = WindowLayout(
			frame: window.frame,
			navigationWidth: expandedNavigationWidth,
			reviewWidth: expandedReviewWidth,
			reviewCollapsed: (savedGitReviewLayout?.reviewVisibility ?? reviewVisibility) ==
				.collapsed,
			navigationCollapsed: navigationCollapsed,
			paneGeometryVersion: WindowPaneLayout.version,
			reviewVisibility: savedGitReviewLayout?.reviewVisibility ?? reviewVisibility
		)
	}

	func toggleSidebar()
	{
		setSidebarCollapsed(!split.splitViewItems[0].isCollapsed)
	}

	func setSidebarCollapsed(_ collapsed: Bool)
	{
		guard split.splitViewItems[0].isCollapsed != collapsed
		else
		{
			return
		}
		cancelToolsPaneAnimation()
		split.splitViewItems[0].isCollapsed = collapsed
		applyResponsivePaneLayout(force: true)
	}

	func setGitReviewFocused(_ focused: Bool)
	{
		guard focused != isGitReviewFocused
		else
		{
			return
		}
		isGitReviewFocused = focused
		let navigationPane = split.splitViewItems[0]
		let conversationPane = split.splitViewItems[1]
		if focused
		{
			savedGitReviewLayout = GitReviewLayout(
				navigationCollapsed: navigationPane.isCollapsed,
				conversationCollapsed: conversationPane.isCollapsed,
				conversationCanCollapse: conversationPane.canCollapse,
				reviewVisibility: reviewVisibility,
				workspaceFilesExpanded: workspaceFilesExpanded
			)
			conversationPane.canCollapse = true
			reviewPane.maximumThickness = NSSplitViewItem.unspecifiedDimension
			navigationPane.isCollapsed = true
			conversationPane.isCollapsed = true
			reviewPane.isCollapsed = false
		}
		else if let saved = savedGitReviewLayout
		{
			savedGitReviewLayout = nil
			navigationPane.isCollapsed = saved.navigationCollapsed
			conversationPane.isCollapsed = saved.conversationCollapsed
			conversationPane.canCollapse = saved.conversationCanCollapse
			reviewVisibility = saved.reviewVisibility
			workspaceFilesExpanded = saved.workspaceFilesExpanded
			reviewPane.maximumThickness = workspaceFilesExpanded ? 1000 : WindowPaneLayout
				.reviewMaximumWidth
		}
		applyResponsivePaneLayout(force: true)
	}

	func setWorkspaceFilesExpanded(_ expanded: Bool)
	{
		workspaceFilesExpanded = expanded
		if !isGitReviewFocused && !inspector.isShowingTools
		{
			reviewPane.maximumThickness = expanded ? 1000 : WindowPaneLayout.reviewMaximumWidth
		}
		applyResponsivePaneLayout(force: true)
	}

	func setReviewCollapsed(_ collapsed: Bool)
	{
		guard !isGitReviewFocused
		else
		{
			return
		}
		reviewVisibility = collapsed ? .collapsed : .expanded
		if collapsed
		{
			setToolsExpanded(false)
		}
		else
		{
			cancelToolsPaneAnimation()
		}
		applyResponsivePaneLayout(force: true)
	}

	func toggleToolsExpanded()
	{
		guard usesToolsSizing, isToolsExpanded || !reviewPane.isCollapsed,
				!isAnimatingToolsExpansion
		else
		{
			return
		}
		if !isToolsExpanded
		{
			expandedToolsWidth = reviewViewportWidth
		}
		reviewVisibility = .expanded
		setToolsExpanded(
			!isToolsExpanded,
			animated: !isToolsExpanded
		)
		applyResponsivePaneLayout(force: true)
	}

	private func updateExpandedTabSelection()
	{
		guard isToolsExpanded
		else
		{
			return
		}
		cancelToolsPaneAnimation()
		updateExpandedPaneContent()
		onToolsExpansionLayoutChanged?()
	}

	private func updateExpandedPaneContent()
	{
		let showConversation = isShowingExpandedConversation
		guard conversationIsInExpandedPane != showConversation
		else
		{
			return
		}
		conversationIsInExpandedPane = showConversation
		if showConversation
		{
			conversationContainer.detachContent()
			reviewContainer.present(
				conversation,
				minimumWidth: WindowPaneLayout.conversationMinimumWidth
			)
			inspector.setExpandedConversation(
				true,
				resetSummary: false
			)
			updateExpandedSummaryLayout()
		}
		else
		{
			inspector.setExpandedConversation(
				false,
				resetSummary: !isToolsExpanded || !inspector.isShowingTools
			)
			reviewContainer.detachContent()
			conversationContainer.restoreContent()
			reviewContainer.restoreContent()
		}
	}

	private func updateExpandedSummaryLayout()
	{
		guard conversationIsInExpandedPane
		else
		{
			return
		}
		let width = min(
			expandedReviewWidth,
			max(
				WindowPaneLayout.reviewMinimumWidth,
				reviewViewportWidth - WindowPaneLayout
					.conversationMinimumWidth
			)
		)
		reviewContainer.setAside(
			inspector.isSummaryBesideExpandedConversation ? inspector : nil,
			width: width
		)
	}

	func openToolsPane(configureContent: () -> Void =
	{
	})
	{
		guard !isAnimatingToolsExpansion
		else
		{
			return
		}
		let transition = prepareToolsPaneAnimation(
			animated: true,
			openingToolsPane: true
		)
		inspector.hideContentForToolsOpening()
		inspector.showToolsPane()
		configureContent()
		reviewVisibility = .expanded
		animateToolsPane(transition)
	}

	private func setToolsExpanded(
		_ expanded: Bool,
		animated: Bool = false
	)
	{
		guard isToolsExpanded != expanded || isAnimatingToolsExpansion
		else
		{
			return
		}
		cancelToolsPaneAnimation()
		let transition = prepareToolsPaneAnimation(animated: animated)
		isToolsExpanded = expanded
		inspector.toolsTabs.setExpanded(expanded)
		if !expanded
		{
			inspector.setExpandedConversation(
				false,
				resetSummary: true
			)
		}
		updateExpandedPaneContent()
		animateToolsPane(transition)
	}

	private func prepareToolsPaneAnimation(
		animated: Bool,
		openingToolsPane: Bool = false,
		startingReviewWidth: CGFloat? = nil
	) -> ToolsPaneTransition?
	{
		guard animated, hasPresentedWindow,
				!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
				let transition = ToolsPaneTransition(
				splitView: split.splitView,
				navigationPane: split.splitViewItems[0],
				conversationPane: conversationPane,
				reviewPane: reviewPane,
				openingToolsPane: openingToolsPane,
				startingReviewWidth: startingReviewWidth
				)
		else
		{
			return nil
		}
		toolsPaneTransition = transition
		isAnimatingToolsExpansion = true
		conversation.beginPaneResize()
		transition.prepare()
		return transition
	}

	private func animateToolsPane(_ transition: ToolsPaneTransition?)
	{
		let target = reviewLayout(width: split.splitView.bounds.width)
		guard let transition
		else
		{
			cancelToolsPaneAnimation()
			applyResponsivePaneLayout(force: true)
			return
		}
		toolsExpansionRevision += 1
		let revision = toolsExpansionRevision
		toolsPaneTransition = transition
		isAnimatingToolsExpansion = true
		(split.splitView as? ConversationSplitView)?.showsReviewDivider =
			usesToolsSizing && !target.collapsed && !isToolsExpanded
		transition.animate(
			toReviewWidth: target.collapsed ? 0 : target.width,
			conversationCollapsed: isToolsExpanded,
			reviewCollapsed: target.collapsed,
			progress:
			{
				[weak self] in self?.onToolsExpansionLayoutChanged?()
			},
			completion:
			{
				[weak self] in
				guard let self, self.toolsExpansionRevision == revision
				else
				{
					return
				}
				self.toolsPaneTransition = nil
				self.isAnimatingToolsExpansion = false
				self.restoreReviewDragSettings()
				self.applyReviewMinimumWidth()
				self.applyResponsivePaneLayout(force: true)
				self.conversation.endPaneResize()
				self.onToolsExpansionLayoutChanged?()
				self.onToolsExpansionFinished?()
			}
		)
	}

	private func cancelToolsPaneAnimation()
	{
		guard let transition = toolsPaneTransition
		else
		{
			return
		}
		toolsExpansionRevision += 1
		toolsPaneTransition = nil
		isAnimatingToolsExpansion = false
		let wasApplyingPaneLayout = isApplyingPaneLayout
		isApplyingPaneLayout = true
		transition.cancel()
		restoreReviewDragSettings()
		applyReviewMinimumWidth()
		isApplyingPaneLayout = wasApplyingPaneLayout
		applyResponsivePaneLayout(force: true)
		conversation.endPaneResize()
		onToolsExpansionLayoutChanged?()
		onToolsExpansionFinished?()
	}

	private func updateInspectorSizing()
	{
		if isShowingExpandedConversation
		{
			updateExpandedSummaryLayout()
		}
		guard usesToolsSizing != inspector.isShowingTools
		else
		{
			return
		}
		usesToolsSizing = inspector.isShowingTools
		if !usesToolsSizing
		{
			setToolsExpanded(false)
		}
		if !isAnimatingToolsExpansion
		{
			applyReviewMinimumWidth()
		}
		reviewPane.maximumThickness = usesToolsSizing
			? NSSplitViewItem
			.unspecifiedDimension :
			(workspaceFilesExpanded ? 1000 : WindowPaneLayout.reviewMaximumWidth)
		applyResponsivePaneLayout(force: true)
	}

	private func applyResponsivePaneLayout(force: Bool = false)
	{
		guard hasPresentedWindow, !isApplyingPaneLayout
		else
		{
			return
		}
		if isAnimatingToolsExpansion
		{
			if toolsPaneTransition?.splitWidthChanged == true
			{
				cancelToolsPaneAnimation()
			}
			return
		}
		let width = split.splitView.bounds.width
		guard width > 0
		else
		{
			return
		}
		if !force, let lastAppliedSplitWidth, abs(width - lastAppliedSplitWidth) < 0.5
		{
			return
		}

		isApplyingPaneLayout = true
		defer
		{
			isApplyingPaneLayout = false
		}
		lastAppliedSplitWidth = width
		if isGitReviewFocused
		{
			reviewPane.isCollapsed = false
			split.view.layoutSubtreeIfNeeded()
			return
		}
		let collapseConversation = isToolsExpanded
		let dividerWidth = split.splitView.dividerThickness
		let target = reviewLayout(width: width)
		let collapseReview = target.collapsed
		reviewAutomaticallyCollapsed = reviewVisibility != .collapsed && collapseReview
		let reviewCollapseChanged = reviewPane.isCollapsed != collapseReview
		applyPaneVisibility(
			conversationCollapsed: collapseConversation,
			reviewCollapsed: collapseReview
		)
		(split.splitView as? ConversationSplitView)?.showsReviewDivider =
			usesToolsSizing && !collapseReview && !isToolsExpanded
		// Ordinary resizing has already laid out the split view. Only a pane transition or an
		// explicit restore needs another pass before measuring the pane widths.
		if reviewCollapseChanged || force
		{
			split.view.layoutSubtreeIfNeeded()
		}
		if !split.splitViewItems[0].isCollapsed,
			abs(navigation.view.frame.width - expandedNavigationWidth) >= 0.5
		{
			split.splitView.setPosition(
				expandedNavigationWidth,
				ofDividerAt: 0
			)
		}
		if !reviewPane.isCollapsed, !isToolsExpanded
		{
			let visibleReviewWidth = target.width
			if abs(reviewViewportWidth - visibleReviewWidth) >= 0.5
			{
				split.splitView.setPosition(
					width - visibleReviewWidth - dividerWidth,
					ofDividerAt: 1
				)
			}
		}
		updateExpandedSummaryLayout()
	}

	private func applyPaneVisibility(
		conversationCollapsed: Bool,
		reviewCollapsed: Bool
	)
	{
		conversationPane.canCollapse = true
		// Release the outgoing pane before opening the incoming pane. Temporarily showing both
		// expanded panes lets AppKit increase the window width to satisfy their minimum sizes.
		if conversationCollapsed, !conversationPane.isCollapsed
		{
			conversationPane.isCollapsed = true
		}
		if reviewCollapsed, !reviewPane.isCollapsed
		{
			reviewPane.isCollapsed = true
		}
		if !conversationCollapsed, conversationPane.isCollapsed
		{
			conversationPane.isCollapsed = false
		}
		if !reviewCollapsed, reviewPane.isCollapsed
		{
			reviewPane.isCollapsed = false
		}
		conversationPane.canCollapse = conversationCollapsed
	}

	private func reviewLayout(width: CGFloat) -> WindowPaneLayoutPolicy.ReviewLayout
	{
		WindowPaneLayoutPolicy.reviewLayout(
			width: width,
			navigationCollapsed: split.splitViewItems[0].isCollapsed,
			navigationWidth: expandedNavigationWidth,
			dividerThickness: split.splitView.dividerThickness,
			isToolsExpanded: isToolsExpanded,
			usesToolsSizing: usesToolsSizing,
			workspaceFilesExpanded: workspaceFilesExpanded,
			expandedToolsWidth: expandedToolsWidth,
			workspaceFilesWidth: workspaceFilesWidth,
			expandedReviewWidth: expandedReviewWidth,
			reviewVisibility: reviewVisibility
		)
	}

	private func rememberDividerChoice(at index: Int)
	{
		guard !isApplyingPaneLayout, !isAnimatingToolsExpansion, !isGitReviewFocused
		else
		{
			return
		}
		if index == 0, !split.splitViewItems[0].isCollapsed
		{
			expandedNavigationWidth = WindowPaneLayout.restoredNavigationWidth(
				navigation.view.frame.width
			)
		}
		else if index == 1
		{
			reviewVisibility = reviewPane.isCollapsed ? .collapsed : .expanded
			if !reviewPane.isCollapsed, !reviewAutomaticallyCollapsed, !isToolsExpanded
			{
				if usesToolsSizing
				{
					expandedToolsWidth = max(
						WindowPaneLayout.toolsMinimumWidth,
						reviewViewportWidth
					)
				}
				else if workspaceFilesExpanded
				{
					workspaceFilesWidth = min(
						1000,
						max(
							220,
							reviewViewportWidth
						)
					)
				}
				else
				{
					expandedReviewWidth = WindowPaneLayout
						.restoredReviewWidth(reviewViewportWidth)
				}
			}
		}
		applyResponsivePaneLayout(force: true)
	}

	func beginDividerInteraction(at index: Int)
	{
		cancelToolsPaneAnimation()
		guard index == 1, usesToolsSizing, inspector.isShowingTools,
				!isToolsExpanded, !isGitReviewFocused, !reviewPane.isCollapsed
		else
		{
			return
		}
		reviewDragSettings = ReviewDragSettings(
			minimumThickness: reviewPane.minimumThickness,
			canCollapse: reviewPane.canCollapse,
			canCollapseFromWindowResize: reviewPane.canCollapseFromWindowResize
		)
		lastDraggedReviewWidth = reviewViewportWidth
		reviewPane.minimumThickness = WindowPaneLayout.toolsMinimumWidth
		reviewPane.canCollapse = false
		reviewPane.canCollapseFromWindowResize = false
	}

	func endDividerInteraction(
		at index: Int,
		requestedWidth: CGFloat? = nil
	)
	{
		guard index == 1, reviewDragSettings != nil
		else
		{
			restoreReviewDragSettings()
			rememberDividerChoice(at: index)
			return
		}
		let endingWidth = reviewPane.isCollapsed
			? lastDraggedReviewWidth ?? 0 : reviewViewportWidth
		let targetWidth = requestedWidth ?? endingWidth
		guard reviewPane.isCollapsed || targetWidth < WindowPaneLayout.toolsMinimumWidth
		else
		{
			restoreReviewDragSettings()
			rememberDividerChoice(at: index)
			return
		}
		reviewVisibility = .collapsed
		let transition = prepareToolsPaneAnimation(
			animated: true,
			startingReviewWidth: endingWidth
		)
		if let transition
		{
			animateToolsPane(transition)
		}
		else
		{
			restoreReviewDragSettings()
			applyResponsivePaneLayout(force: true)
			onToolsExpansionLayoutChanged?()
			onToolsExpansionFinished?()
		}
	}

	private func restoreReviewDragSettings()
	{
		guard let reviewDragSettings
		else
		{
			return
		}
		self.reviewDragSettings = nil
		lastDraggedReviewWidth = nil
		reviewPane.minimumThickness = reviewDragSettings.minimumThickness
		reviewPane.canCollapse = reviewDragSettings.canCollapse
		reviewPane.canCollapseFromWindowResize = reviewDragSettings.canCollapseFromWindowResize
	}

	private func applyReviewMinimumWidth()
	{
		reviewPane.minimumThickness = usesToolsSizing
			? WindowPaneLayout.toolsMinimumWidth : WindowPaneLayout.reviewMinimumWidth
	}

	var isReviewCollapsed: Bool
	{
		reviewPane.isCollapsed
	}

	func toggleReview()
	{
		// A second click can cancel an explicit open request that cannot fit at this width.
		let cancelHiddenOpenRequest =
			reviewVisibility == .expanded && reviewAutomaticallyCollapsed && reviewPane.isCollapsed
		setReviewCollapsed(cancelHiddenOpenRequest || !reviewPane.isCollapsed)
	}

	private static func pane(
		_ controller: NSViewController,
		minimumWidth: CGFloat,
		maximumWidth: CGFloat = NSSplitViewItem.unspecifiedDimension,
		holdingPriority: NSLayoutConstraint.Priority = .defaultLow
	) -> NSSplitViewItem
	{
		let pane = NSSplitViewItem(viewController: controller)
		pane.minimumThickness = minimumWidth
		pane.maximumThickness = maximumWidth
		pane.holdingPriority = holdingPriority
		return pane
	}
}
