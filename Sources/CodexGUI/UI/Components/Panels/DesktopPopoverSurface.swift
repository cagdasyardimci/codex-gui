import AppKit

@MainActor
final class DesktopPopoverSurface: DesktopSurface
{
	init()
	{
		super.init(
			.clear,
			cornerRadius: ShapeTokens.Popover.cornerRadius,
			shadows: ShadowTokens.popover
		)
		let backdrop = NSVisualEffectView()
		backdrop.material = .popover
		backdrop.blendingMode = .behindWindow
		backdrop.state = .active
		backdrop.wantsLayer = true
		backdrop.layer?.cornerRadius = ShapeTokens.Popover.cornerRadius
		backdrop.layer?.masksToBounds = true
		let tint = DesktopSurface(
			AppKitColorTokens.popover,
			cornerRadius: ShapeTokens.Popover.cornerRadius,
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

	required init?(coder: NSCoder)
	{
		nil
	}
}
