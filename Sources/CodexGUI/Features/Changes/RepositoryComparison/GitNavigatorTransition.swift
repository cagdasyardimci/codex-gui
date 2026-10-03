import AppKit
import QuartzCore

/// Moves the changed-file navigator while the comparison reflows beside it.
@MainActor
final class GitNavigatorTransition
{
	private static let duration: TimeInterval = ToolsPaneTransition.duration

	private let widthConstraint: NSLayoutConstraint
	private let layoutView: NSView
	private let expandedWidth: CGFloat
	private var animationTask: Task<Void, Never>?
	private var animationGeneration = 0

	var currentWidth: CGFloat
	{
		widthConstraint.constant
	}

	var isAnimating: Bool
	{
		animationTask != nil
	}

	init(
		widthConstraint: NSLayoutConstraint,
		layoutView: NSView,
		expandedWidth: CGFloat = 280
	)
	{
		self.widthConstraint = widthConstraint
		self.layoutView = layoutView
		self.expandedWidth = expandedWidth
	}

	deinit
	{
		animationTask?.cancel()
	}

	/// A new target replaces the running animation at its current displayed width.
	func setVisible(
		_ visible: Bool,
		animated: Bool = true,
		completion: (@MainActor () -> Void)? = nil
	)
	{
		animationTask?.cancel()
		animationTask = nil
		animationGeneration += 1
		let generation = animationGeneration
		let startWidth = currentWidth
		let finalWidth: CGFloat = visible ? expandedWidth : 0
		guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
				abs(finalWidth - startWidth) >= 0.5
		else
		{
			applyWidth(finalWidth)
			completion?()
			return
		}

		let frameRate = min(
			120,
			max(
				60,
				layoutView.window?.screen?.maximumFramesPerSecond ?? 60
			)
		)
		let started = CACurrentMediaTime()
		animationTask = Task
		{
			@MainActor [weak self] in
			while !Task.isCancelled
			{
				let elapsed = min(
					1,
					(CACurrentMediaTime() - started) / Self.duration
				)
				let eased = TransitionEasing.easeInEaseOut(elapsed)
				do
				{
					guard let self, self.animationGeneration == generation
					else
					{
						return
					}
					self.applyWidth(startWidth + (finalWidth - startWidth) * CGFloat(eased))
					if elapsed >= 1 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
					{
						self.applyWidth(finalWidth)
						self.animationTask = nil
						completion?()
						return
					}
				}
				try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 / frameRate))
			}
		}
	}

	func cancel()
	{
		animationGeneration += 1
		animationTask?.cancel()
		animationTask = nil
	}

	private func applyWidth(_ width: CGFloat)
	{
		widthConstraint.constant = width
		layoutView.layoutSubtreeIfNeeded()
	}
}
