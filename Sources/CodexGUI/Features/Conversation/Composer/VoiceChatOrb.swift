import AppKit
import QuartzCore

/// Passive call artwork. The composer reserves room for the largest speaking state.
@MainActor
final class VoiceChatOrb: NSView
{
	private static let maximumScale: CGFloat = 1.08
	private static let rippleDuration: CFTimeInterval = 0.76
	private static let quietBloomOpacity: Float = 0.18
	private static let still = VoiceOrbFlow.frame()
	private static let animationFrames = Task.detached(priority: .utility)
	{
		(flow: VoiceOrbFlow.frames(), ripple: VoiceOrbFlow.rippleFrames())
	}

	private let orb = CALayer()
	private let ground = CAGradientLayer()
	private let haze = CAGradientLayer()
	private let bloom = CAGradientLayer()
	private let refraction = CALayer()
	private let fluid = CALayer()
	private let ripples = [CALayer(), CALayer(), CALayer()]
	private var rippleFrames: [CGImage] = []
	private var lastRipple = -Double.infinity
	private var rippleAngle: CGFloat = 0
	private var frameLoad: Task<Void, Never>?
	private let reflection = CAGradientLayer()
	private let diameter: CGFloat
	private var active = false
	private var level: CGFloat = 0

	init(diameter: CGFloat)
	{
		self.diameter = diameter
		super.init(frame: .zero)
		wantsLayer = true
		layer?.addSublayer(orb)
		orb.masksToBounds = true
		for artwork in [ground, refraction, haze, bloom, reflection]
		{
			orb.addSublayer(artwork)
		}
		for ripple in ripples
		{
			orb.insertSublayer(
				ripple,
				above: bloom
			)
		}
		refraction.addSublayer(fluid)
		fluid.contents = Self.still
		configureArtwork()

		let space = ceil(diameter * Self.maximumScale)
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: space),
			heightAnchor.constraint(equalToConstant: space),
		])
		setAccessibilityElement(false)
		NSWorkspace.shared.notificationCenter.addObserver(
			self,
			selector: #selector(updateMotion),
			name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
			object: nil
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		nil
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		updateMotion()
	}

	override func layout()
	{
		super.layout()
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		orb.bounds = CGRect(
			x: 0,
			y: 0,
			width: diameter,
			height: diameter
		)
		orb.position = CGPoint(
			x: bounds.midX,
			y: bounds.midY
		)
		orb.cornerRadius = diameter / 2
		ground.frame = orb.bounds
		haze.frame = orb.bounds.insetBy(
			dx: -diameter * 0.3,
			dy: -diameter * 0.3
		)
		bloom.frame = haze.frame
		refraction.bounds = orb.bounds
		refraction.position = CGPoint(
			x: orb.bounds.midX,
			y: orb.bounds.midY
		)
		fluid.frame = refraction.bounds
		reflection.frame = haze.frame
		for ripple in ripples
		{
			ripple.bounds = orb.bounds
			ripple.position = CGPoint(
				x: orb.bounds.midX,
				y: orb.bounds.midY
			)
		}
		CATransaction.commit()
	}

	func setActive(_ active: Bool)
	{
		guard self.active != active
		else
		{
			return
		}
		self.active = active
		updateMotion()
	}

	func setPlaybackLevel(_ rms: Double)
	{
		guard shouldAnimate, rms.isFinite
		else
		{
			return
		}
		let next = CGFloat(min(
			1,
			max(
				0,
				(rms - 0.012) / 0.19
			)
		))
		guard abs(next - level) >= 0.02 || (next == 0 && level > 0)
		else
		{
			return
		}
		let duration = next > level ? 0.12 : 0.38
		if next > 0.19, level < 0.12 || next - level > 0.17
		{
			emitRipple(strength: next)
		}
		level = next
		animate(
			orb,
			keyPath: "transform.scale",
			to: 1 + (Self.maximumScale - 1) * next,
			duration: duration
		)
		updateFlowRate()
		animate(
			bloom,
			keyPath: "opacity",
			to: CGFloat(Self.quietBloomOpacity) + 0.52 * next,
			duration: duration
		)
	}

	private var shouldAnimate: Bool
	{
		active && window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
	}

	@objc private func updateMotion()
	{
		if shouldAnimate
		{
			startFlow()
			orbit(
				haze,
				radius: diameter * 0.14,
				duration: 9.6
			)
			orbit(
				bloom,
				radius: diameter * -0.19,
				duration: 6.8
			)
			orbit(
				reflection,
				radius: diameter * 0.06,
				duration: 11.4
			)
		}
		else
		{
			level = 0
			lastRipple = -.infinity
			rippleAngle = 0
			frameLoad?.cancel()
			frameLoad = nil
			for artwork in [orb, refraction, fluid, haze, bloom, reflection]
			{
				artwork.removeAllAnimations()
			}
			for ripple in ripples
			{
				ripple.removeAllAnimations()
			}
			CATransaction.begin()
			CATransaction.setDisableActions(true)
			orb.transform = CATransform3DIdentity
			fluid.speed = 1
			fluid.beginTime = 0
			fluid.timeOffset = 0
			bloom.opacity = Self.quietBloomOpacity
			CATransaction.commit()
		}
	}

	private func configureArtwork()
	{
		// The gradients and fluid textures form one illustration. Their colors must blend
		// in the same color space regardless of the theme’s control tints.
		ground.colors = [
			CGColor(
				srgbRed: 0.23,
				green: 0.39,
				blue: 0.79,
				alpha: 1
			),
			CGColor(
				srgbRed: 0.34,
				green: 0.59,
				blue: 0.92,
				alpha: 1
			),
			CGColor(
				srgbRed: 0.23,
				green: 0.39,
				blue: 0.75,
				alpha: 1
			),
		]
		ground.startPoint = CGPoint(
			x: 0.18,
			y: 0.04
		)
		ground.endPoint = CGPoint(
			x: 0.79,
			y: 0.98
		)

		haze.type = .radial
		haze.colors = [
			CGColor(
				srgbRed: 0.72,
				green: 0.87,
				blue: 1,
				alpha: 0.64
			),
			CGColor(
				srgbRed: 0.36,
				green: 0.66,
				blue: 1,
				alpha: 0.28
			),
			CGColor(
				srgbRed: 0.32,
				green: 0.52,
				blue: 0.95,
				alpha: 0
			),
		]
		haze.startPoint = CGPoint(
			x: 0.42,
			y: 0.59
		)
		haze.endPoint = CGPoint(
			x: 0.84,
			y: 0.99
		)

		bloom.type = .radial
		bloom.colors = [
			CGColor(
				srgbRed: 0.83,
				green: 0.99,
				blue: 1,
				alpha: 0.68
			),
			CGColor(
				srgbRed: 0.43,
				green: 0.84,
				blue: 1,
				alpha: 0.34
			),
			CGColor(
				srgbRed: 0.38,
				green: 0.78,
				blue: 1,
				alpha: 0
			),
		]
		bloom.startPoint = CGPoint(
			x: 0.67,
			y: 0.63
		)
		bloom.endPoint = CGPoint(
			x: 0.89,
			y: 0.89
		)
		bloom.opacity = Self.quietBloomOpacity

		reflection.type = .radial
		reflection.colors = [
			CGColor(
				srgbRed: 0.84,
				green: 0.94,
				blue: 1,
				alpha: 0.39
			),
			CGColor(
				srgbRed: 0.86,
				green: 0.95,
				blue: 1,
				alpha: 0.13
			),
			CGColor(
				srgbRed: 0.87,
				green: 0.96,
				blue: 1,
				alpha: 0
			),
		]
		reflection.startPoint = CGPoint(
			x: 0.27,
			y: 0.19
		)
		reflection.endPoint = CGPoint(
			x: 0.76,
			y: 0.74
		)

	}

	private func startFlow()
	{
		guard frameLoad == nil, fluid.animation(forKey: "fluid") == nil
		else
		{
			return
		}
		frameLoad = Task
		{
			[weak self] in
			let frames = await Self.animationFrames.value
			guard !Task.isCancelled, let self, self.shouldAnimate
			else
			{
				return
			}
			self.frameLoad = nil
			guard let first = frames.flow.first, frames.flow.count > 1
			else
			{
				return
			}
			self.rippleFrames = frames.ripple
			let loop = Self.frameAnimation(
				frames.flow + [first],
				duration: VoiceOrbFlow.duration
			)
			loop.repeatCount = .infinity
			self.fluid.add(
				loop,
				forKey: "fluid"
			)
			self.updateFlowRate()
			if self.level > 0.19
			{
				self.emitRipple(strength: self.level)
			}
		}
	}

	private func emitRipple(strength: CGFloat)
	{
		let now = CACurrentMediaTime()
		guard now - lastRipple >= 0.22, let first = rippleFrames.first, rippleFrames.count > 1,
				let layer = ripples.first(where:
				{
					$0.animation(forKey: "speechRipple") == nil
				})
		else
		{
			return
		}
		lastRipple = now
		rippleAngle += .pi * 0.77
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		layer.contents = first
		let angle = 0.34 * sin(rippleAngle)
		layer.setAffineTransform(CGAffineTransform(rotationAngle: angle))
		layer.opacity = Float(0.38 + 0.62 * strength)
		layer.add(
			Self.frameAnimation(
				rippleFrames,
				duration: Self.rippleDuration
			),
			forKey: "speechRipple"
		)
		refractLiquid(
			strength: strength,
			angle: angle
		)
		CATransaction.commit()
	}

	private func refractLiquid(
		strength: CGFloat,
		angle: CGFloat
	)
	{
		// Keep the deformation on a separate clock from the continuously flowing texture.
		let motion = CAKeyframeAnimation(keyPath: "transform")
		let axis = CGAffineTransform(rotationAngle: angle + 0.7)
		let bend = 0.1 * strength
		let compression = axis.scaledBy(
			x: 1 + bend,
			y: 1 - bend * 0.43
		)
		.concatenating(axis.inverted())
		let rebound = axis.scaledBy(
			x: 1 - 0.26 * bend,
			y: 1 + 0.42 * bend
		)
		.concatenating(axis.inverted())
		motion.values = [
			NSValue(caTransform3D: refraction.presentation()?.transform ?? CATransform3DIdentity),
			NSValue(caTransform3D: CATransform3DMakeAffineTransform(compression)),
			NSValue(caTransform3D: CATransform3DMakeAffineTransform(rebound)),
			NSValue(caTransform3D: CATransform3DIdentity),
		]
		motion.keyTimes = [0, 0.23, 0.59, 1]
		motion.timingFunctions = [
			CAMediaTimingFunction(name: .easeOut),
			CAMediaTimingFunction(name: .easeInEaseOut),
			CAMediaTimingFunction(name: .easeOut),
		]
		motion.duration = Self.rippleDuration
		refraction.add(
			motion,
			forKey: "liquidRefraction"
		)
	}

	private static func frameAnimation(
		_ frames: [CGImage],
		duration: CFTimeInterval
	) -> CAKeyframeAnimation
	{
		let animation = CAKeyframeAnimation(keyPath: "contents")
		animation.values = frames
		animation.calculationMode = .discrete
		animation.keyTimes = frames.indices.map
		{
			NSNumber(value: Double($0) / Double(frames.count - 1))
		}
		animation.duration = duration
		return animation
	}

	private func updateFlowRate()
	{
		guard fluid.animation(forKey: "fluid") != nil, let parent = fluid.superlayer
		else
		{
			return
		}
		let desiredRate = Float(1 + 0.48 * level)
		guard abs(fluid.speed - desiredRate) > 0.01
		else
		{
			return
		}
		// Rebase the local clock at the current phase before changing playback speed.
		let now = CACurrentMediaTime()
		let localTime = fluid.convertTime(
			now,
			from: nil
		)
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		fluid.speed = desiredRate
		fluid.beginTime = parent.convertTime(
			now,
			from: nil
		)
		fluid.timeOffset = localTime
		CATransaction.commit()
	}

	private func orbit(
		_ light: CALayer,
		radius: CGFloat,
		duration: CFTimeInterval
	)
	{
		guard light.animation(forKey: "orbit") == nil
		else
		{
			return
		}
		let horizontal = CAKeyframeAnimation(keyPath: "transform.translation.x")
		horizontal.values = [0, radius, 0, -radius, 0]
		let vertical = CAKeyframeAnimation(keyPath: "transform.translation.y")
		vertical.values = [0, radius * 0.55, radius, radius * 0.55, 0]
		for axis in [horizontal, vertical]
		{
			axis.calculationMode = .cubic
			axis.duration = duration
		}
		let motion = CAAnimationGroup()
		motion.animations = [horizontal, vertical]
		motion.duration = duration
		motion.repeatCount = .infinity
		light.add(
			motion,
			forKey: "orbit"
		)
	}

	private func animate(
		_ artwork: CALayer,
		keyPath: String,
		to value: CGFloat,
		duration: CFTimeInterval
	)
	{
		let motion = CABasicAnimation(keyPath: keyPath)
		motion.fromValue = (artwork.presentation() ?? artwork).value(forKeyPath: keyPath)
		motion.toValue = value
		motion.duration = duration
		motion.timingFunction = CAMediaTimingFunction(name: .easeOut)
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		artwork.setValue(
			value,
			forKeyPath: keyPath
		)
		artwork.add(
			motion,
			forKey: keyPath
		)
		CATransaction.commit()
	}

}
