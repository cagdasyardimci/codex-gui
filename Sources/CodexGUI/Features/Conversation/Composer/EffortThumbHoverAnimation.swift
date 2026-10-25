import AppKit

/// Frame scheduling can be controlled without replacing the spring interpolation.
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

/// Interpolation approximates the observed spring trajectory, not its unknown physics.
@MainActor
final class EffortThumbHoverAnimation: EffortThumbHoverAnimating
{
	var onProgress: (@MainActor @Sendable (CGFloat) -> Void)?
	private let expanding: Bool
	private var timer: Timer?
	let duration: TimeInterval
	var isAnimating: Bool
	{
		timer != nil
	}
	var currentProgress: Float = 0
	{
		didSet
		{
			onProgress?(interpolatedProgress(CGFloat(currentProgress)))
		}
	}

	private enum Configuration
	{
		static let enterDuration: TimeInterval = 0.35
		static let leaveDuration: TimeInterval = 0.45
		static let frameRate: Double = 120
		static let enterProgress: [CGFloat] = [0, 0.15, 0.53, 0.79, 0.92, 0.975, 0.994, 1]
		static let leaveProgress: [CGFloat] =
			[0, 0.1, 0.39, 0.65, 0.82, 0.921, 0.972, 0.994, 1.0015, 1]
	}

	init(expanding: Bool)
	{
		self.expanding = expanding
		duration = expanding ? Configuration.enterDuration : Configuration.leaveDuration
	}

	isolated deinit
	{
		timer?.invalidate()
	}

	func start()
	{
		stop()
		let startedAt = ContinuousClock.now
		let timer = Timer(
			timeInterval: 1 / Configuration.frameRate,
			repeats: true
		)
		{
			[weak self] timer in
			let timerID = ObjectIdentifier(timer)
			MainActor.assumeIsolated
			{
				guard let self, let activeTimer = self.timer,
						ObjectIdentifier(activeTimer) == timerID
				else
				{
					return
				}
				let elapsed = startedAt.duration(to: .now).components
				let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
				let progress = min(
					1,
					seconds / self.duration
				)
				if progress >= 1
				{
					self.stop()
				}
				self.currentProgress = Float(progress)
			}
		}
		self.timer = timer
		RunLoop.main.add(
			timer,
			forMode: .common
		)
		RunLoop.main.add(
			timer,
			forMode: .eventTracking
		)
		currentProgress = 0
	}

	func stop()
	{
		timer?.invalidate()
		timer = nil
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
