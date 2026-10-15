import AppKit
import QuartzCore

@MainActor
final class CurrentActionLabel: NSTextField
{
	static let sweepDuration: TimeInterval = 1.75
	static let pauseDuration: TimeInterval = 0.35
	static let animationKey = "currentActionSweep"

	var actionIsActive = false
	{
		didSet
		{
			synchronizeAnimation()
		}
	}
	var presentationIsVisible = true
	{
		didSet
		{
			synchronizeAnimation()
		}
	}
	var shouldReduceMotion: () -> Bool =
	{
		NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
	}
	private(set) var highlightLayer: CALayer?
	private var maskBounds = NSRect.zero
	private var maskText = ""
	private var maskScale: CGFloat = 0

	override var stringValue: String
	{
		didSet
		{
			if oldValue != stringValue
			{
				stopAnimation()
				needsLayout = true
				synchronizeAnimation()
			}
		}
	}

	override var isHidden: Bool
	{
		didSet
		{
			synchronizeAnimation()
		}
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		let notifications = NSWorkspace.shared.notificationCenter
		notifications.removeObserver(
			self,
			name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
			object: nil
		)
		if window != nil
		{
			notifications.addObserver(
				self,
				selector: #selector(accessibilityOptionsChanged),
				name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
				object: nil
			)
		}
		synchronizeAnimation()
	}

	override func viewDidChangeBackingProperties()
	{
		super.viewDidChangeBackingProperties()
		synchronizeAnimation()
	}

	override func layout()
	{
		super.layout()
		synchronizeAnimation()
	}

	@objc private func accessibilityOptionsChanged()
	{
		synchronizeAnimation()
	}

	func synchronizeAnimation()
	{
		guard actionIsActive, presentationIsVisible, window != nil,
				!isHiddenOrHasHiddenAncestor, !stringValue.isEmpty, !shouldReduceMotion(),
				bounds.width > 0, bounds.height > 0
		else
		{
			stopAnimation()
			return
		}
		let scale = window?.backingScaleFactor ?? 1
		if highlightLayer != nil, maskBounds == bounds, maskText == stringValue, maskScale == scale
		{
			return
		}
		stopAnimation()
		guard let maskImage = glyphMask(scale: scale)
		else
		{
			return
		}
		let highlight = installHighlightLayers(
			maskImage: maskImage,
			scale: scale
		)
		startHighlightSweep(
			on: highlight.gradient,
			bandWidth: highlight.bandWidth
		)
		highlightLayer = highlight.overlay
		maskBounds = bounds
		maskText = stringValue
		maskScale = scale
	}

	private func installHighlightLayers(
		maskImage: CGImage,
		scale: CGFloat
	) -> (overlay: CALayer, gradient: CAGradientLayer, bandWidth: CGFloat)
	{
		wantsLayer = true
		let overlay = CALayer()
		let mask = CALayer()
		let gradient = CAGradientLayer()
		let bandWidth = min(
			64,
			max(
				24,
				bounds.width * 0.45
			)
		)
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		overlay.frame = bounds
		mask.frame = overlay.bounds
		mask.contents = maskImage
		mask.contentsScale = scale
		overlay.mask = mask
		gradient.colors = [
			NSColor.white.withAlphaComponent(0).cgColor,
			NSColor.white.withAlphaComponent(0.12).cgColor,
			NSColor.white.withAlphaComponent(0.38).cgColor,
			NSColor.white.withAlphaComponent(0.12).cgColor,
			NSColor.white.withAlphaComponent(0).cgColor,
		]
		gradient.locations = [0, 0.3, 0.5, 0.7, 1]
		gradient.startPoint = CGPoint(
			x: 0,
			y: 0.5
		)
		gradient.endPoint = CGPoint(
			x: 1,
			y: 0.5
		)
		gradient.bounds = CGRect(
			x: 0,
			y: 0,
			width: bandWidth,
			height: bounds.height
		)
		gradient.position = CGPoint(
			x: -bandWidth / 2,
			y: bounds.height / 2
		)
		overlay.addSublayer(gradient)
		layer?.addSublayer(overlay)
		CATransaction.commit()
		return (overlay, gradient, bandWidth)
	}

	private func startHighlightSweep(
		on gradient: CAGradientLayer,
		bandWidth: CGFloat
	)
	{
		// The whole band begins and ends outside the label. Holding the final position
		// supplies the pause without a timer or a repeating completion callback.
		let sweep = CAKeyframeAnimation(keyPath: "position.x")
		sweep.values = [-bandWidth / 2, bounds.width + bandWidth / 2, bounds.width + bandWidth / 2]
		sweep.keyTimes = [
			0,
			NSNumber(value: Self.sweepDuration / (Self.sweepDuration + Self.pauseDuration)),
			1
		]
		sweep.duration = Self.sweepDuration + Self.pauseDuration
		sweep.calculationMode = .linear
		sweep.timingFunctions = [
			CAMediaTimingFunction(name: .linear),
			CAMediaTimingFunction(name: .linear),
		]
		sweep.repeatCount = .infinity
		gradient.add(
			sweep,
			forKey: Self.animationKey
		)
	}

	private func stopAnimation()
	{
		highlightLayer?.sublayers?.forEach
		{
			$0.removeAllAnimations()
		}
		highlightLayer?.removeFromSuperlayer()
		highlightLayer = nil
	}

	func glyphMask(scale: CGFloat) -> CGImage?
	{
		guard let textCell = cell?.copy() as? NSTextFieldCell,
				let bitmap = NSBitmapImageRep(
				bitmapDataPlanes: nil,
				pixelsWide: Int(ceil(bounds.width * scale)),
				pixelsHigh: Int(ceil(bounds.height * scale)),
				bitsPerSample: 8,
				samplesPerPixel: 4,
				hasAlpha: true,
				isPlanar: false,
				colorSpaceName: .deviceRGB,
				bytesPerRow: 0,
				bitsPerPixel: 0
				),
				let context = NSGraphicsContext(bitmapImageRep: bitmap)
		else
		{
			return nil
		}
		bitmap.size = bounds.size
		textCell.textColor = .white
		textCell.drawsBackground = false
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = context
		context.cgContext.scaleBy(
			x: scale,
			y: scale
		)
		textCell.drawInterior(
			withFrame: NSRect(
				origin: .zero,
				size: bounds.size
			),
			in: self
		)
		NSGraphicsContext.restoreGraphicsState()
		return bitmap.cgImage
	}
}
