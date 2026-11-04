import AppKit

/// Retained focus artwork shared by app-owned controls; the control owns focus and refresh timing.
@MainActor
final class DesktopControlFocusIndicator
{
	enum Shape
	{
		case dialog, capsule
	}

	private var layer: CAShapeLayer?

	func update(
		in view: NSView,
		shape: Shape?,
		focused: Bool
	)
	{
		guard let shape
		else
		{
			layer?.isHidden = true
			return
		}
		if layer == nil
		{
			view.wantsLayer = true
			let indicator = CAShapeLayer()
			indicator.fillColor = nil
			indicator.lineWidth = 2
			indicator.zPosition = 100
			view.layer?.addSublayer(indicator)
			layer = indicator
		}
		guard let layer
		else
		{
			return
		}
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		defer
		{
			CATransaction.commit()
		}
		layer.isHidden = !focused
		layer.frame = view.bounds
		layer.contentsScale = view.window?.backingScaleFactor ?? 2
		switch shape
		{
		case .dialog:
			layer.path = AppKitShapePath.roundedCGPath(
				view.bounds.insetBy(
					dx: 2,
					dy: 2
				),
				radius: min(
					8,
					view.bounds.height / 2 - 2
				),
				curve: ShapeTokens.Connections.curve
			)
		case .capsule:
			// A two-point exterior ring must leave the complete control surface visible.
			layer.path = CGPath(
				roundedRect: view.bounds.insetBy(
					dx: -1,
					dy: -1
				),
				cornerWidth: view.bounds.height / 2 + 1,
				cornerHeight: view.bounds.height / 2 + 1,
				transform: nil
			)
		}
		layer.strokeColor = AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.focus,
			for: view
		)
	}
}
