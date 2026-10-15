import AppKit

/// Frame scheduling can be controlled without replacing the native interpolation.
@MainActor
protocol EffortThumbHoverAnimating: AnyObject
{
	var onProgress: (@MainActor @Sendable (CGFloat) -> Void)?
	{
		get set
	}
	var isAnimating: Bool
	{
		get
	}
	func start()
	func stop()
}

/// Native interpolation approximates the observed spring trajectory, not its unknown physics.
// Preserve NSAnimation's nonisolated overrides; the driver protocol must not infer class isolation.
nonisolated final class EffortThumbHoverAnimation: NSAnimation, EffortThumbHoverAnimating
{
	var onProgress: (@MainActor @Sendable (CGFloat) -> Void)?
	private let expanding: Bool
	private enum Configuration
	{
		static let enterDuration: TimeInterval = 0.35
		static let leaveDuration: TimeInterval = 0.45
		static let frameRate: Float = 120
		static let enterProgress: [CGFloat] = [0, 0.15, 0.53, 0.79, 0.92, 0.975, 0.994, 1]
		static let leaveProgress: [CGFloat] =
			[0, 0.1, 0.39, 0.65, 0.82, 0.921, 0.972, 0.994, 1.0015, 1]
	}

	@MainActor init(expanding: Bool)
	{
		self.expanding = expanding
		super.init(
			duration: expanding ? Configuration.enterDuration : Configuration.leaveDuration,
			animationCurve: .linear
		)
		animationBlockingMode = .nonblocking
		frameRate = Configuration.frameRate
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var runLoopModesForAnimating: [RunLoop.Mode]?
	{
		[.common, .eventTracking]
	}

	override var currentProgress: NSAnimation.Progress
	{
		get
		{
			super.currentProgress
		}
		set
		{
			super.currentProgress = newValue
			let callback = onProgress
			let progress = interpolatedProgress(CGFloat(newValue))
			// Nonblocking NSAnimation runs on the starting main run loop, including dragging.
			MainActor.assumeIsolated
			{
				callback?(progress)
			}
		}
	}

	private func interpolatedProgress(_ progress: CGFloat) -> CGFloat
	{
		let values = expanding ? Configuration.enterProgress : Configuration.leaveProgress
		guard progress > 0, progress < 1
		else
		{
			return progress <= 0 ? 0 : 1
		}
		let position = progress * CGFloat(values.count - 1)
		let index = Int(position)
		let fraction = position - CGFloat(index)
		let start = values[index]
		let end = values[index + 1]
		let startSlope = index == 0 ? 0 : (end - values[index - 1]) / 2
		let endSlope = index + 2 >= values.count ? 0 : (values[index + 2] - start) / 2
		let squared = fraction * fraction
		let cubed = squared * fraction
		return (2 * cubed - 3 * squared + 1) * start
			+ (cubed - 2 * squared + fraction) * startSlope
			+ (-2 * cubed + 3 * squared) * end
			+ (cubed - squared) * endSlope
	}
}
