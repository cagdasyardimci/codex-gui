import AppKit
import QuartzCore

/// Animates the floating summary card without delaying its visibility state update.
@MainActor
final class PinnedSummaryTransition
{
	private weak var source: NSView?
	private let sourceAlpha: CGFloat
	private let parent: NSView
	private let snapshot: SummaryTransitionSnapshotView
	private var completionTask: Task<Void, Never>?

	init?(view: NSView)
	{
		guard let parent = view.superview, !view.bounds.isEmpty,
				let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
		else
		{
			return nil
		}
		view.cacheDisplay(
			in: view.bounds,
			to: bitmap
		)
		guard let image = bitmap.cgImage
		else
		{
			return nil
		}
		source = view
		sourceAlpha = view.alphaValue
		self.parent = parent
		snapshot = SummaryTransitionSnapshotView(
			frame: view.frame,
			image: image,
			scale: view.window?.backingScaleFactor ?? 1
		)
	}

	func animate(
		appearing: Bool,
		completion: @escaping @MainActor () -> Void
	)
	{
		parent.addSubview(
			snapshot,
			positioned: .above,
			relativeTo: nil
		)
		guard let layer = snapshot.layer
		else
		{
			cancel()
			completion()
			return
		}
		source?.alphaValue = 0

		let scale: CGFloat = 0.9
		let travel = parent.bounds.maxX - snapshot.frame.minX
		var hiddenTransform = CATransform3DMakeScale(
			scale,
			scale,
			1
		)
		// Compensate for scaling around the center to keep the card's top edge fixed.
		hiddenTransform.m41 = travel - snapshot.bounds.width * (1 - scale) / 2
		hiddenTransform.m42 = snapshot.bounds.height * (1 - scale) / 2
		let initialTransform = appearing ? hiddenTransform : CATransform3DIdentity
		let finalTransform = appearing ? CATransform3DIdentity : hiddenTransform
		let transform = CABasicAnimation(keyPath: "transform")
		transform.fromValue = NSValue(caTransform3D: initialTransform)
		transform.toValue = NSValue(caTransform3D: finalTransform)
		let opacity = CABasicAnimation(keyPath: "opacity")
		opacity.fromValue = appearing ? 0 : 1
		opacity.toValue = appearing ? 1 : 0

		let duration = appearing ? 0.24 : 0.1
		let animation = CAAnimationGroup()
		animation.animations = [transform, opacity]
		animation.duration = duration
		animation.timingFunction = appearing
			? CAMediaTimingFunction(
				controlPoints: 0.16,
				1,
				0.3,
				1
			) : CAMediaTimingFunction(name: .easeIn)
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		layer.transform = finalTransform
		layer.opacity = appearing ? 1 : 0
		layer.add(
			animation,
			forKey: "pinnedSummaryVisibility"
		)
		CATransaction.commit()

		completionTask = Task
		{
			@MainActor [weak self] in
			try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
			guard let self, !Task.isCancelled
			else
			{
				return
			}
			self.cancel()
			completion()
		}
	}

	func cancel()
	{
		completionTask?.cancel()
		completionTask = nil
		snapshot.layer?.removeAllAnimations()
		snapshot.removeFromSuperview()
		source?.alphaValue = sourceAlpha
	}
}

@MainActor
private final class SummaryTransitionSnapshotView: NSView
{
	private let image: CGImage

	init(
		frame: NSRect,
		image: CGImage,
		scale: CGFloat
	)
	{
		self.image = image
		super.init(frame: frame)
		wantsLayer = true
		layerContentsRedrawPolicy = .onSetNeedsDisplay
		layer?.contentsScale = scale
		layer?.contents = image
	}

	@available(
		*,
		unavailable
	)
	required init?(coder: NSCoder)
	{
		nil
	}

	override var wantsUpdateLayer: Bool
	{
		true
	}

	override func updateLayer()
	{
		layer?.contents = image
	}

	override func hitTest(_: NSPoint) -> NSView?
	{
		nil
	}
}
