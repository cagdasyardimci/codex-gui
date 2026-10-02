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
			[weak self] in self?.applyResponsivePaneLayout()
		}
		splitView.onDividerInteractionEnded =
		{
			[weak self] index in
			self?.rememberDividerChoice(at: index)
		}
		splitView.onDividerInteractionBegan =
		{
			[weak self] in self?.cancelToolsPaneAnimation()
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
		let navigationCollapsed = split.splitViewItems[0].isCollapsed
		layoutStore?.layout = WindowLayout(
			frame: window.frame,
			navigationWidth: expandedNavigationWidth,
			reviewWidth: expandedReviewWidth,
			reviewCollapsed: reviewVisibility == .collapsed,
			navigationCollapsed: navigationCollapsed,
			paneGeometryVersion: WindowPaneLayout.version,
			reviewVisibility: reviewVisibility
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

	func setReviewCollapsed(_ collapsed: Bool)
	{
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
			inspector.setExpandedConversation(true)
		}
		else
		{
			inspector.setExpandedConversation(false)
			reviewContainer.detachContent()
			conversationContainer.restoreContent()
			reviewContainer.restoreContent()
		}
	}

	func openToolsPane()
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
			inspector.setExpandedConversation(false)
		}
		updateExpandedPaneContent()
		animateToolsPane(transition)
	}

	private func prepareToolsPaneAnimation(
		animated: Bool,
		openingToolsPane: Bool = false
	) -> ToolsPaneTransition?
	{
		guard animated, hasPresentedWindow,
				!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
				let transition = ToolsPaneTransition(
				splitView: split.splitView,
				navigationPane: split.splitViewItems[0],
				conversationPane: conversationPane,
				reviewPane: reviewPane,
				openingToolsPane: openingToolsPane
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
		guard let transition, !target.collapsed
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
			toReviewWidth: target.width,
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
		isApplyingPaneLayout = wasApplyingPaneLayout
		applyResponsivePaneLayout(force: true)
		conversation.endPaneResize()
		onToolsExpansionLayoutChanged?()
		onToolsExpansionFinished?()
	}

	private func updateInspectorSizing()
	{
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
		reviewPane.maximumThickness = usesToolsSizing
			? NSSplitViewItem.unspecifiedDimension : WindowPaneLayout.reviewMaximumWidth
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

	private func reviewLayout(width: CGFloat) -> (collapsed: Bool, width: CGFloat)
	{
		let navigationWidth = split.splitViewItems[0].isCollapsed ? 0 : expandedNavigationWidth
		let conversationWidth = isToolsExpanded ? 0 : WindowPaneLayout.conversationMinimumWidth
		let dividerCount = (navigationWidth > 0 ? 1 : 0) + (isToolsExpanded ? 0 : 1)
		let dividerSpace = split.splitView.dividerThickness * CGFloat(dividerCount)
		let available = width - navigationWidth - dividerSpace - conversationWidth
		let preferred = usesToolsSizing ? expandedToolsWidth : expandedReviewWidth
		let collapsed: Bool
		switch reviewVisibility
		{
		case .collapsed: collapsed = true
		case .automatic:
			collapsed = width - navigationWidth - dividerSpace - preferred
				< WindowPaneLayout.conversationComfortableWidth
		case .expanded: collapsed = available < WindowPaneLayout.reviewMinimumWidth
		}
		return (collapsed, isToolsExpanded ? available : min(
			preferred,
			available
		))
	}

	private func rememberDividerChoice(at index: Int)
	{
		guard !isApplyingPaneLayout, !isAnimatingToolsExpansion
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
						WindowPaneLayout.reviewMinimumWidth,
						reviewViewportWidth
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

@MainActor
private final class ConversationSplitViewController: NSSplitViewController
{
	var onLayout: (() -> Void)?

	override func viewDidLayout()
	{
		super.viewDidLayout()
		onLayout?()
	}
}

@MainActor
private final class ConversationSplitView: NSSplitView
{
	var onDividerInteractionEnded: ((Int) -> Void)?
	var onDividerInteractionBegan: (() -> Void)?
	var showsReviewDivider = false
	{
		didSet
		{
			if showsReviewDivider != oldValue
			{
				needsDisplay = true
			}
		}
	}

	private var dividerTrackingArea: NSTrackingArea?
	private var dividerHovered = false
	private var dividerDragging = false

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let dividerTrackingArea
		{
			removeTrackingArea(dividerTrackingArea)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		dividerTrackingArea = area
		if let window
		{
			updateDividerHover(at: convert(
				window.mouseLocationOutsideOfEventStream,
				from: nil
			))
		}
	}

	override func mouseEntered(with event: NSEvent)
	{
		updateDividerHover(at: convert(
			event.locationInWindow,
			from: nil
		))
	}

	override func mouseMoved(with event: NSEvent)
	{
		updateDividerHover(at: convert(
			event.locationInWindow,
			from: nil
		))
	}

	override func mouseExited(with event: NSEvent)
	{
		dividerHovered = false
		needsDisplay = true
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	private func updateDividerHover(at location: NSPoint)
	{
		let hovered = subviews.first.map
		{
			$0.frame.width > 0
				&& abs(location.x - $0.frame.maxX - dividerThickness / 2) <= 6
				&& bounds.contains(location)
		} ?? false
		guard hovered != dividerHovered
		else
		{
			return
		}
		dividerHovered = hovered
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent)
	{
		let location = convert(
			event.locationInWindow,
			from: nil
		)
		let dividerIndex = subviews.indices.dropLast().first
		{
			abs(location.x - subviews[$0].frame.maxX - dividerThickness / 2) <= 6
		}
		dividerDragging = dividerIndex == 0
		needsDisplay = true
		if dividerIndex != nil
		{
			onDividerInteractionBegan?()
		}
		super.mouseDown(with: event)
		dividerDragging = false
		if let window
		{
			updateDividerHover(at: convert(
				window.mouseLocationOutsideOfEventStream,
				from: nil
			))
		}
		needsDisplay = true
		if let dividerIndex
		{
			onDividerInteractionEnded?(dividerIndex)
		}
	}

	override func drawDivider(in rect: NSRect)
	{
		guard let firstPane = subviews.first,
				abs(rect.minX - firstPane.frame.maxX) > dividerThickness
		else
		{
			let color = dividerHovered || dividerDragging
				? DesktopTheme.highlightedPaneDivider : DesktopTheme.paneDivider
			color.setFill()
			rect.fill()
			return
		}
		(showsReviewDivider ? DesktopTheme.paneDivider : DesktopTheme.canvas).setFill()
		rect.fill()
	}
}
