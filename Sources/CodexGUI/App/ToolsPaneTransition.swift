import AppKit
import QuartzCore

/// Moves the native split divider while both clipped pane viewports remain live.
@MainActor
final class ToolsPaneTransition
{
	static let duration: TimeInterval = 0.24

	@MainActor
	private struct PaneSettings
	{
		let minimumThickness: CGFloat
		let canCollapse: Bool
		let canCollapseFromWindowResize: Bool

		init(_ pane: NSSplitViewItem)
		{
			minimumThickness = pane.minimumThickness
			canCollapse = pane.canCollapse
			canCollapseFromWindowResize = pane.canCollapseFromWindowResize
		}

		func restore(_ pane: NSSplitViewItem)
		{
			pane.minimumThickness = minimumThickness
			pane.canCollapse = canCollapse
			pane.canCollapseFromWindowResize = canCollapseFromWindowResize
		}
	}

	private let splitView: NSSplitView
	private let conversationPane: NSSplitViewItem
	private let reviewPane: NSSplitViewItem
	private let conversationSettings: PaneSettings
	private let reviewSettings: PaneSettings
	private let initialWidth: CGFloat
	private let navigationWidth: CGFloat?
	private let navigationPane: NSSplitViewItem
	private let initialReviewWidth: CGFloat
	private var geometryConstraints: [NSLayoutConstraint] = []
	private var reviewWidthConstraint: NSLayoutConstraint?
	private var finalConversationCollapsed = false
	private var finalReviewCollapsed = false
	private var isPrepared = false
	private var animationTask: Task<Void, Never>?

	var splitWidthChanged: Bool
	{
		abs(splitView.bounds.width - initialWidth) >= 0.5
	}

	init?(
		splitView: NSSplitView,
		navigationPane: NSSplitViewItem,
		conversationPane: NSSplitViewItem,
		reviewPane: NSSplitViewItem,
		openingToolsPane: Bool = false
	)
	{
		guard splitView.bounds.width > 0
		else
		{
			return nil
		}
		self.splitView = splitView
		self.conversationPane = conversationPane
		self.reviewPane = reviewPane
		self.navigationPane = navigationPane
		conversationSettings = PaneSettings(conversationPane)
		reviewSettings = PaneSettings(reviewPane)
		initialWidth = splitView.bounds.width
		navigationWidth = navigationPane.isCollapsed ? nil : navigationPane.viewController.view
			.frame.width
		initialReviewWidth = openingToolsPane || reviewPane.isCollapsed
			? 0 : reviewPane.viewController.view.frame.width
		finalConversationCollapsed = conversationPane.isCollapsed
		finalReviewCollapsed = reviewPane.isCollapsed
	}

	/// Locks the starting geometry before changing inspector content or sizing rules.
	func prepare()
	{
		guard !isPrepared
		else
		{
			return
		}
		isPrepared = true
		for pane in [conversationPane, reviewPane]
		{
			pane.minimumThickness = 0
			pane.canCollapse = false
			pane.canCollapseFromWindowResize = false
		}
		installGeometryConstraints()
		conversationPane.isCollapsed = false
		reviewPane.isCollapsed = false
		applyReviewWidth(initialReviewWidth)
	}

	func animate(
		toReviewWidth width: CGFloat,
		conversationCollapsed: Bool,
		reviewCollapsed: Bool,
		progress: @escaping @MainActor () -> Void,
		completion: @escaping @MainActor () -> Void
	)
	{
		prepare()
		finalConversationCollapsed = conversationCollapsed
		finalReviewCollapsed = reviewCollapsed
		// Both panes stay uncollapsed during motion, so their divider still occupies space.
		let availableWidth = initialWidth - (navigationWidth ?? 0)
			- splitView.dividerThickness * (navigationWidth == nil ? 1 : 2)
		let finalWidth = conversationCollapsed ? max(
			0,
			availableWidth
		) : width
		progress()
		guard isPrepared
		else
		{
			return
		}
		let frameRate = min(
			120,
			max(
				60,
				splitView.window?.screen?.maximumFramesPerSecond ?? 60
			)
		)
		animationTask = Task
		{
			@MainActor [weak self] in
			guard let self
			else
			{
				return
			}
			let started = CACurrentMediaTime()
			while !Task.isCancelled
			{
				let elapsed = min(
					1,
					(CACurrentMediaTime() - started) / Self.duration
				)
				let eased = Self.easeInEaseOut(elapsed)
				self.applyReviewWidth(
					self
						.initialReviewWidth + (finalWidth - self.initialReviewWidth) *
						CGFloat(eased)
				)
				progress()
				guard !Task.isCancelled, self.isPrepared
				else
				{
					return
				}
				if elapsed >= 1
				{
					self.restorePaneSettings()
					self.animationTask = nil
					completion()
					return
				}
				do
				{
					try await Task.sleep(nanoseconds: UInt64(1_000_000_000 / frameRate))
				}
				catch
				{
					return
				}
			}
		}
	}

	func cancel()
	{
		animationTask?.cancel()
		animationTask = nil
		restorePaneSettings()
	}

	private func installGeometryConstraints()
	{
		let width = reviewPane.viewController.view.widthAnchor.constraint(
			equalToConstant: initialReviewWidth
		)
		width.identifier = "Tools transition review width"
		reviewWidthConstraint = width
		geometryConstraints = [width]
		if let navigationWidth
		{
			let navigation = navigationPane.viewController.view.widthAnchor.constraint(
				equalToConstant: navigationWidth
			)
			navigation.identifier = "Tools transition navigation width"
			geometryConstraints.append(navigation)
		}
		NSLayoutConstraint.activate(geometryConstraints)
	}

	private func applyReviewWidth(_ width: CGFloat)
	{
		reviewWidthConstraint?.constant = width
		splitView.layoutSubtreeIfNeeded()
	}

	private func restorePaneSettings()
	{
		guard isPrepared
		else
		{
			return
		}
		isPrepared = false
		NSLayoutConstraint.deactivate(geometryConstraints)
		geometryConstraints.removeAll()
		reviewWidthConstraint = nil
		conversationPane.isCollapsed = finalConversationCollapsed
		reviewPane.isCollapsed = finalReviewCollapsed
		conversationSettings.restore(conversationPane)
		reviewSettings.restore(reviewPane)
	}

	private static func easeInEaseOut(_ fraction: Double) -> Double
	{
		guard fraction > 0, fraction < 1
		else
		{
			return fraction
		}
		var lower = 0.0
		var upper = 1.0
		for _ in 0 ..< 12
		{
			let parameter = (lower + upper) / 2
			let inverse = 1 - parameter
			let time = 3 * inverse * inverse * parameter * 0.42
				+ 3 * inverse * parameter * parameter * 0.58 + parameter * parameter * parameter
			if time < fraction
			{
				lower = parameter
			}
			else
			{
				upper = parameter
			}
		}
		let parameter = (lower + upper) / 2
		return 3 * (1 - parameter) * parameter * parameter + parameter * parameter * parameter
	}
}
