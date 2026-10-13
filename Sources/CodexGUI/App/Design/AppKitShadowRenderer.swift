import AppKit
import QuartzCore

/// Applies native shadow geometry; views own the retained layers and refresh timing.
@MainActor
enum AppKitShadowRenderer
{
	static func apply(
		_ style: ShadowTokens.Style,
		to layer: CALayer,
		in view: NSView,
		cornerRadius: CGFloat
	)
	{
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		layer.frame = view.bounds
		layer.shadowColor = AppKitColorResolution.resolvedCGColor(
			style.color,
			for: view
		)
		layer.shadowOpacity = 1
		layer.shadowOffset = CGSize(
			width: 0,
			height: view.isFlipped ? style.offsetY : -style.offsetY
		)
		// Approximate the CSS blur with a native Gaussian radius; the kernels differ.
		layer.shadowRadius = style.blur / 2
		layer.shadowPath = CGPath(
			roundedRect: layer.bounds.insetBy(
				dx: -style.spread,
				dy: -style.spread
			),
			cornerWidth: max(
				0,
				cornerRadius + style.spread
			),
			cornerHeight: max(
				0,
				cornerRadius + style.spread
			),
			transform: nil
		)
		// Sublayer shadows otherwise cover their owner's fill. Keep only the outside portion.
		let mask = layer.mask as? CAShapeLayer ?? CAShapeLayer()
		let outset = style.blur + abs(style.spread) + abs(style.offsetY) + 4
		mask.frame = layer.bounds.insetBy(
			dx: -outset,
			dy: -outset
		)
		let maskPath = CGMutablePath()
		maskPath.addRect(mask.bounds)
		maskPath.addRoundedRect(
			in: layer.bounds.offsetBy(
				dx: outset,
				dy: outset
			),
			cornerWidth: cornerRadius,
			cornerHeight: cornerRadius
		)
		mask.path = maskPath
		mask.fillRule = .evenOdd
		mask.fillColor = NSColor.black.cgColor
		layer.mask = mask
		CATransaction.commit()
	}
}
