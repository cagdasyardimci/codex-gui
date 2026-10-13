import AppKit
import QuartzCore

enum EffortSliderGeometry
{
	static let knobDiameter = LayoutTokens.EffortSlider.knobDiameter
	static let trackHeight = LayoutTokens.EffortSlider.trackHeight
	static let trackCornerRadius = ShapeTokens.EffortSlider.trackCornerRadius
	static let filledTickDiameter = LayoutTokens.EffortSlider.filledTickDiameter
	static let unfilledTickDiameter = LayoutTokens.EffortSlider.unfilledTickDiameter
	static let trackEdgeWidth = ShapeTokens.EffortSlider.trackEdgeWidth

	static func knobRect(centeredIn rect: NSRect) -> NSRect
	{
		knobRect(
			centerX: rect.midX,
			centerY: rect.midY
		)
	}

	static func knobRect(
		centerX: CGFloat,
		centerY: CGFloat
	) -> NSRect
	{
		NSRect(
			x: centerX - knobDiameter / 2,
			y: centerY - knobDiameter / 2,
			width: knobDiameter,
			height: knobDiameter
		)
	}

	static func tickRect(
		centerX: CGFloat,
		centerY: CGFloat,
		filled: Bool
	) -> NSRect
	{
		let tickDiameter = filled ? filledTickDiameter : unfilledTickDiameter
		return NSRect(
			x: centerX - tickDiameter / 2,
			y: centerY - tickDiameter / 2,
			width: tickDiameter,
			height: tickDiameter
		)
	}

	static func filledTrack(
		track: NSRect,
		knob: NSRect,
		value: Double,
		minimum: Double,
		maximum: Double
	) -> NSRect
	{
		let hasFilledTrack = value > minimum && maximum > minimum
		let filledWidth = hasFilledTrack ? min(
			track.width,
			max(
				0,
				knob.midX - track.minX
			)
		) : 0
		return NSRect(
			x: track.minX,
			y: track.minY,
			width: filledWidth,
			height: track.height
		)
	}
}

@MainActor
final class EffortSliderCell: NSSliderCell
{
	var ultraSelected = false

	override var knobThickness: CGFloat
	{
		EffortSliderGeometry.knobDiameter
	}

	override func barRect(flipped: Bool) -> NSRect
	{
		canonicalTrack(flipped: flipped)
	}

	override func knobRect(flipped: Bool) -> NSRect
	{
		let track = canonicalTrack(flipped: flipped)
		let center = centerX(
			for: doubleValue,
			in: track
		)
		return EffortSliderGeometry.knobRect(
			centerX: center,
			centerY: track.midY
		)
	}

	override func rectOfTickMark(at index: Int) -> NSRect
	{
		let track = canonicalTrack(flipped: controlView?.isFlipped ?? false)
		let x = centerX(
			for: tickMarkValue(at: index),
			in: track
		)
		return EffortSliderGeometry.tickRect(
			centerX: x,
			centerY: track.midY,
			filled: tickMarkValue(at: index) <= doubleValue
		)
	}

	override func indexOfTickMark(at point: NSPoint) -> Int
	{
		guard numberOfTickMarks > 0
		else
		{
			return NSNotFound
		}
		let track = canonicalTrack(flipped: controlView?.isFlipped ?? false)
		guard track.insetBy(
			dx: -2,
			dy: -4
		).contains(point)
		else
		{
			return NSNotFound
		}
		return (0 ..< numberOfTickMarks).min
		{
			abs(rectOfTickMark(at: $0).midX - point.x)
				< abs(rectOfTickMark(at: $1).midX - point.x)
		} ?? NSNotFound
	}

	private func canonicalTrack(flipped: Bool) -> NSRect
	{
		let bar = controlView?.bounds ?? .zero
		return NSRect(
			x: bar.minX,
			y: bar.midY - EffortSliderGeometry.trackHeight / 2,
			width: bar.width,
			height: EffortSliderGeometry.trackHeight
		)
	}

	private func centerX(
		for value: Double,
		in track: NSRect
	) -> CGFloat
	{
		let valueRange = maxValue - minValue
		let fraction = maxValue > minValue ? CGFloat(min(
			1,
			max(
				0,
				(value - minValue) / valueRange
			)
		)) : 0
		let knobInset = min(
			EffortSliderGeometry.knobDiameter / 2,
			track.width / 2
		)
		let travelWidth = max(
			0,
			track.width - 2 * knobInset
		)
		return track.minX + knobInset + fraction * travelWidth
	}

	override func drawBar(
		inside rect: NSRect,
		flipped: Bool
	)
	{
		let track = canonicalTrack(flipped: flipped)
		let knob = knobRect(flipped: flipped)
		let trackPath = NSBezierPath(
			roundedRect: track,
			xRadius: EffortSliderGeometry.trackCornerRadius,
			yRadius: EffortSliderGeometry.trackCornerRadius
		)
		let filledTrack = EffortSliderGeometry.filledTrack(
			track: track,
			knob: knob,
			value: doubleValue,
			minimum: minValue,
			maximum: maxValue
		)

		EffortPopoverStyle.track.setFill()
		trackPath.fill()
		drawFilledTrack(
			filledTrack,
			clippedTo: trackPath
		)
		let edge = NSBezierPath(
			roundedRect: track.insetBy(
				dx: EffortSliderGeometry.trackEdgeWidth / 2,
				dy: EffortSliderGeometry.trackEdgeWidth / 2
			),
			xRadius: EffortSliderGeometry.trackCornerRadius,
			yRadius: EffortSliderGeometry.trackCornerRadius
		)
		AppKitColorTokens.effortTrackEdge.setStroke()
		edge.lineWidth = EffortSliderGeometry.trackEdgeWidth
		edge.stroke()
		drawEffortTicks(in: track)
		(controlView as? EffortSlider)?.updateTrackGeometry(
			track: track,
			knob: knob
		)
	}

	private func drawFilledTrack(
		_ filledTrack: NSRect,
		clippedTo trackPath: NSBezierPath
	)
	{
		guard filledTrack.width > 0
		else
		{
			return
		}
		NSGraphicsContext.saveGraphicsState()
		trackPath.addClip()
		if ultraSelected
		{
			NSGradient(
				starting: EffortPopoverStyle.blue,
				ending: .systemPurple
			)?.draw(
				in: filledTrack,
				angle: 0
			)
		}
		else
		{
			EffortPopoverStyle.blue.setFill()
			filledTrack.fill()
		}
		NSGraphicsContext.restoreGraphicsState()
	}

	private func drawEffortTicks(in track: NSRect)
	{
		for index in 0 ..< numberOfTickMarks
		{
			let filled = tickMarkValue(at: index) <= doubleValue
			(filled ? AppKitColorTokens.effortFilledTick : EffortPopoverStyle.tick).setFill()
			let centerX = rectOfTickMark(at: index).midX
			let tick = EffortSliderGeometry.tickRect(
				centerX: centerX,
				centerY: track.midY,
				filled: filled
			)
			NSBezierPath(ovalIn: tick).fill()
		}
	}

	override func drawKnob(_ knobRect: NSRect)
	{
		NSGraphicsContext.saveGraphicsState()
		let shadow = NSShadow()
		shadow.shadowColor = ShadowTokens.effortThumb.color
		shadow.shadowBlurRadius = ShadowTokens.effortThumb.blur
		shadow.shadowOffset = NSSize(
			width: 0,
			height: -ShadowTokens.effortThumb.offsetY
		)
		shadow.set()
		AppKitColorTokens.effortThumb.setFill()
		let whiteKnob = EffortSliderGeometry.knobRect(centeredIn: knobRect)
		NSBezierPath(ovalIn: whiteKnob).fill()
		NSGraphicsContext.restoreGraphicsState()
	}

	override func drawTickMarks()
	{
	}
}

/// Particles animate only inside the actual filled track, without UI state or layout updates.
@MainActor
final class EffortSlider: NSSlider
{
	var ultraSelected = false
	{
		didSet
		{
			(cell as? EffortSliderCell)?.ultraSelected = ultraSelected
			if ultraSelected != oldValue
			{
				needsDisplay = true
				updateParticles()
			}
		}
	}
	var fastMode = false
	{
		didSet
		{
			updateParticles()
		}
	}
	var isPresented = false
	{
		didSet
		{
			updateParticles()
		}
	}

	private enum ParticleMode
	{
		case hidden
		case fastTrail
		case ultraWiggle
		case ultraStill
	}

	private let particleRoot = CALayer()
	private let roundedTrackMask = CAShapeLayer()
	private let filledClip = CALayer()
	private let knobCutoutMask = CAShapeLayer()
	private var particles: [CALayer] = []
	private var particleMode: ParticleMode = .hidden
	private var trackRect = NSRect.zero
	private var filledRect = NSRect.zero
	private var whiteKnobRect = NSRect.zero

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		wantsLayer = true
		particleRoot.isHidden = true
		particleRoot.mask = roundedTrackMask
		filledClip.masksToBounds = true
		filledClip.mask = knobCutoutMask
		knobCutoutMask.fillRule = .evenOdd
		particleRoot.addSublayer(filledClip)
		layer?.addSublayer(particleRoot)
		makeParticles()
	}

	private func makeParticles()
	{
		for index in 0 ..< 12
		{
			let dot = CALayer()
			let size = 1.6 + CGFloat(index % 4) * 0.4
			dot.bounds = CGRect(
				x: 0,
				y: 0,
				width: size,
				height: size
			)
			dot.cornerRadius = size / 2
			dot.backgroundColor = NSColor.white.cgColor
			dot.opacity = 0
			filledClip.addSublayer(dot)
			particles.append(dot)
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func updateTrackGeometry(
		track: NSRect,
		knob: NSRect
	)
	{
		let filled = EffortSliderGeometry.filledTrack(
			track: track,
			knob: knob,
			value: doubleValue,
			minimum: minValue,
			maximum: maxValue
		)
		let whiteKnob = EffortSliderGeometry.knobRect(centeredIn: knob)
		let geometryChanged =
			trackRect != track || filledRect != filled || whiteKnobRect != whiteKnob
		guard geometryChanged
		else
		{
			updateParticles()
			return
		}
		trackRect = track
		filledRect = filled
		whiteKnobRect = whiteKnob

		updateParticleMasks(
			track: track,
			filledTrack: filled,
			whiteKnob: whiteKnob
		)
		updateParticles(restart: true)
	}

	private func updateParticleMasks(
		track: NSRect,
		filledTrack: NSRect,
		whiteKnob: NSRect
	)
	{
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		particleRoot.frame = bounds
		particleRoot.isGeometryFlipped = isFlipped
		roundedTrackMask.frame = particleRoot.bounds
		roundedTrackMask.path = CGPath(
			roundedRect: track,
			cornerWidth: EffortSliderGeometry.trackCornerRadius,
			cornerHeight: EffortSliderGeometry.trackCornerRadius,
			transform: nil
		)
		filledClip.frame = filledTrack
		knobCutoutMask.frame = filledClip.bounds
		let cutout = CGMutablePath()
		cutout.addRect(filledClip.bounds)
		cutout.addEllipse(
			in: whiteKnob.offsetBy(
				dx: -filledTrack.minX,
				dy: -filledTrack.minY
			)
		)
		knobCutoutMask.path = cutout
		CATransaction.commit()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		updateParticles()
	}

	override func viewDidHide()
	{
		super.viewDidHide()
		updateParticles()
	}

	override func viewDidUnhide()
	{
		super.viewDidUnhide()
		updateParticles()
	}

	private func desiredParticleMode() -> ParticleMode
	{
		let canDisplayParticles = isPresented && filledRect.width > 0
			&& window?.isVisible == true && !isHiddenOrHasHiddenAncestor
		guard canDisplayParticles
		else
		{
			return .hidden
		}
		if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		{
			return ultraSelected ? .ultraStill : .hidden
		}
		if fastMode
		{
			return .fastTrail
		}
		return ultraSelected ? .ultraWiggle : .hidden
	}

	private func updateParticles(restart: Bool = false)
	{
		let mode = desiredParticleMode()
		let shouldReconfigureParticles = restart || mode != particleMode
		guard shouldReconfigureParticles
		else
		{
			return
		}
		particleMode = mode
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		particleRoot.isHidden = mode == .hidden
		for (index, dot) in particles.enumerated()
		{
			dot.removeAllAnimations()
			dot.opacity = 0
			guard mode != .hidden
			else
			{
				continue
			}
			configureParticle(
				dot,
				at: index,
				mode: mode
			)
		}
		CATransaction.commit()
	}

	private func configureParticle(
		_ dot: CALayer,
		at index: Int,
		mode: ParticleMode
	)
	{
		let phase = Double(index) / Double(particles.count)
		let verticalPosition = filledRect.height * (0.3 + CGFloat((index * 7) % 9) / 20)
		let baseOpacity = Float(0.35 + Double(index % 4) * 0.12)
		if mode == .fastTrail
		{
			animateTrail(
				dot,
				index: index,
				y: verticalPosition,
				opacity: baseOpacity,
				phase: phase
			)
		}
		else
		{
			let horizontalPosition =
				filledRect.width * (CGFloat(index) + 0.6) / CGFloat(particles.count)
			let origin = CGPoint(
				x: horizontalPosition,
				y: verticalPosition
			)
			dot.position = origin
			dot.opacity = baseOpacity
			if mode == .ultraWiggle
			{
				animateWiggle(
					dot,
					index: index,
					origin: origin,
					phase: phase
				)
			}
		}
	}

	private func animateTrail(
		_ dot: CALayer,
		index: Int,
		y: CGFloat,
		opacity: Float,
		phase: Double
	)
	{
		let crossingDuration = max(
			0.45,
			Double(filledRect.width) / 200
		)
		let durationVariation = 1 + Double(index % 3) * 0.06
		let duration = crossingDuration * durationVariation
		let start = CGPoint(
			x: filledRect.width,
			y: y
		)
		let finish = CGPoint(
			x: -2,
			y: y + CGFloat(index % 3 - 1) * 0.5
		)
		dot.position = start
		let movement = CABasicAnimation(keyPath: "position")
		movement.fromValue = NSValue(point: start)
		movement.toValue = NSValue(point: finish)
		movement.duration = duration

		let fade = CAKeyframeAnimation(keyPath: "opacity")
		fade.values = [0, opacity, opacity * 0.7, 0]
		fade.keyTimes = [0, 0.12, 0.75, 1]
		fade.duration = duration

		let shrink = CABasicAnimation(keyPath: "transform.scale")
		shrink.fromValue = 1
		shrink.toValue = 0.45
		shrink.duration = duration

		let group = CAAnimationGroup()
		group.animations = [movement, fade, shrink]
		group.duration = duration
		group.beginTime = CACurrentMediaTime() - duration * phase
		group.repeatCount = .infinity
		group.timingFunction = CAMediaTimingFunction(name: .linear)
		dot.add(
			group,
			forKey: "effortTrail"
		)
	}

	private func animateWiggle(
		_ dot: CALayer,
		index: Int,
		origin: CGPoint,
		phase: Double
	)
	{
		let duration = 1.8 + Double(index % 5) * 0.15
		let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
		let wiggle = CAKeyframeAnimation(keyPath: "position")
		wiggle.values = [
			NSValue(point: origin),
			NSValue(point: CGPoint(
				x: origin.x + direction * 0.8,
				y: origin.y + 0.6
			)),
			NSValue(point: CGPoint(
				x: origin.x - direction * 0.5,
				y: origin.y - 0.8
			)),
			NSValue(point: origin),
		]
		wiggle.keyTimes = [0, 0.33, 0.66, 1]
		wiggle.duration = duration
		wiggle.beginTime = CACurrentMediaTime() - duration * phase
		wiggle.repeatCount = .infinity
		wiggle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
		dot.add(
			wiggle,
			forKey: "ultraWiggle"
		)
	}
}
