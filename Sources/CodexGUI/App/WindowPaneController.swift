import AppKit

/// Owns split-pane geometry, responsive collapse decisions, and persisted divider choices.
@MainActor
final class WindowPaneController
{
	private weak var window: NSWindow?
	private let navigation: NavigationViewController
	private let inspector: InspectorViewController
	let split: NSSplitViewController
	private let reviewPane: NSSplitViewItem
	private let layoutStore: WindowLayoutStore?
	private var expandedNavigationWidth = WindowPaneLayout.navigationWidth
	private var expandedReviewWidth = WindowPaneLayout.reviewWidth
	private var reviewVisibility: WindowReviewVisibility = .automatic
	private var reviewAutomaticallyCollapsed = false
	private var hasPresentedWindow = false
	private var isApplyingPaneLayout = false
	private var lastAppliedSplitWidth: CGFloat?

	init(
		navigation: NavigationViewController,
		conversation: ConversationViewController,
		inspector: InspectorViewController,
		layoutStore: WindowLayoutStore?
	)
	{
		self.navigation = navigation
		self.inspector = inspector
		self.layoutStore = layoutStore
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
		split.addSplitViewItem(
			Self.pane(
				conversation,
				minimumWidth: WindowPaneLayout.conversationMinimumWidth
			)
		)
		reviewPane = Self.pane(
			inspector,
			minimumWidth: WindowPaneLayout.reviewMinimumWidth,
			maximumWidth: WindowPaneLayout.reviewMaximumWidth,
			holdingPriority: WindowPaneLayout.sideHoldingPriority
		)
		reviewPane.canCollapse = true
		reviewPane.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
		split.addSplitViewItem(reviewPane)

		self.split = split
		split.onLayout =
		{
			[weak self] in self?.applyResponsivePaneLayout()
		}
		splitView.onDividerInteractionEnded =
		{
			[weak self] index in
			self?.rememberDividerChoice(at: index)
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
		split.splitViewItems[0].isCollapsed = collapsed
		applyResponsivePaneLayout(force: true)
	}

	func setReviewCollapsed(_ collapsed: Bool)
	{
		reviewVisibility = collapsed ? .collapsed : .expanded
		applyResponsivePaneLayout(force: true)
	}

	private func applyResponsivePaneLayout(force: Bool = false)
	{
		guard hasPresentedWindow, !isApplyingPaneLayout
		else
		{
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
		let navigationWidth = split.splitViewItems[0].isCollapsed ? 0 : expandedNavigationWidth
		let dividerWidth = split.splitView.dividerThickness
		let reviewDividerSpace = dividerWidth * (navigationWidth > 0 ? 2 : 1)
		let availableReviewWidth =
			width - navigationWidth - reviewDividerSpace - WindowPaneLayout.conversationMinimumWidth
		let collapseReview: Bool
		switch reviewVisibility
		{
		case .collapsed:
			collapseReview = true
		case .automatic:
			collapseReview =
				width - navigationWidth - reviewDividerSpace - expandedReviewWidth
					< WindowPaneLayout.conversationComfortableWidth
		case .expanded:
			collapseReview = availableReviewWidth < WindowPaneLayout.reviewMinimumWidth
		}
		reviewAutomaticallyCollapsed = reviewVisibility != .collapsed && collapseReview
		let reviewCollapseChanged = reviewPane.isCollapsed != collapseReview
		if reviewCollapseChanged
		{
			reviewPane.isCollapsed = collapseReview
		}
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
		if !reviewPane.isCollapsed
		{
			let visibleReviewWidth = min(
				expandedReviewWidth,
				availableReviewWidth
			)
			if abs(inspector.view.frame.width - visibleReviewWidth) >= 0.5
			{
				split.splitView.setPosition(
					width - visibleReviewWidth - dividerWidth,
					ofDividerAt: 1
				)
			}
		}
	}

	private func rememberDividerChoice(at index: Int)
	{
		guard !isApplyingPaneLayout
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
			if !reviewPane.isCollapsed, !reviewAutomaticallyCollapsed
			{
				expandedReviewWidth = WindowPaneLayout
					.restoredReviewWidth(inspector.view.frame.width)
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
		DesktopTheme.canvas.setFill()
		rect.fill()
	}
}
