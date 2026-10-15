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
	private let now: @MainActor () -> TimeInterval
	private let sleep: @MainActor (UInt64) async -> Void
	private let shouldReduceMotion: @MainActor () -> Bool
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
		expandedWidth: CGFloat = 280,
		now: @escaping @MainActor () -> TimeInterval =
		{
			CACurrentMediaTime()
		},
		sleep: @escaping @MainActor (UInt64) async -> Void =
		{
			try? await Task.sleep(nanoseconds: $0)
		},
		shouldReduceMotion: @escaping @MainActor () -> Bool =
		{
			NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		}
	)
	{
		self.widthConstraint = widthConstraint
		self.layoutView = layoutView
		self.expandedWidth = expandedWidth
		self.now = now
		self.sleep = sleep
		self.shouldReduceMotion = shouldReduceMotion
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
		guard animated, !shouldReduceMotion(),
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
		// Inject timing so reversal tests can observe a frame without scheduling deadlines.
		let now = now
		let sleep = sleep
		let shouldReduceMotion = shouldReduceMotion
		let started = now()
		animationTask = Task
		{
			@MainActor [weak self] in
			while !Task.isCancelled
			{
				let elapsed = min(
					1,
					(now() - started) / Self.duration
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
					if elapsed >= 1 || shouldReduceMotion()
					{
						self.applyWidth(finalWidth)
						self.animationTask = nil
						completion?()
						return
					}
				}
				await sleep(UInt64(1_000_000_000 / frameRate))
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
