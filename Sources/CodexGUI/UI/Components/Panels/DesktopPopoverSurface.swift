import AppKit

@MainActor
final class DesktopPopoverSurface: DesktopSurface
{
	private let backdrop = NSVisualEffectView()
	private let cornerCurve: ShapeTokens.CornerCurve

	init(cornerCurve: ShapeTokens.CornerCurve = .circular)
	{
		self.cornerCurve = cornerCurve
		super.init(
			.clear,
			cornerRadius: ShapeTokens.Popover.cornerRadius,
			cornerCurve: cornerCurve,
			shadows: ShadowTokens.popover
		)
		backdrop.material = .popover
		backdrop.blendingMode = .behindWindow
		backdrop.state = .active
		backdrop.wantsLayer = true
		backdrop.layer?.cornerRadius = ShapeTokens.Popover.cornerRadius
		backdrop.layer?.masksToBounds = true
		let tint = DesktopSurface(
			AppKitColorTokens.popover,
			cornerRadius: ShapeTokens.Popover.cornerRadius,
			cornerCurve: cornerCurve,
			bordered: true,
			borderWidth: ShapeTokens.Popover.edgeWidth,
			borderColor: AppKitColorTokens.popoverEdge
		)
		for background in [backdrop, tint]
		{
			background.setAccessibilityElement(false)
			AppKitLayout.pin(
				background,
				to: self,
				inset: 0
			)
		}
	}

	override func layout()
	{
		super.layout()
		guard case .superellipse = cornerCurve
		else
		{
			return
		}
		let mask = backdrop.layer?.mask as? CAShapeLayer ?? CAShapeLayer()
		mask.frame = backdrop.bounds
		mask.path = AppKitShapePath.roundedCGPath(
			backdrop.bounds,
			radius: ShapeTokens.Popover.cornerRadius,
			curve: cornerCurve
		)
		backdrop.layer?.cornerRadius = 0
		backdrop.layer?.mask = mask
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
