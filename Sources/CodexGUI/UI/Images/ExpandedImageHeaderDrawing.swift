import AppKit

@MainActor
enum ExpandedImageHeaderDrawing
{
	static func foreground(
		enabled: Bool
	) -> NSColor
	{
		AppKitColorTokens.enabledForeground(
			AppKitColorTokens.imageControlText,
			enabled: enabled
		)
	}

	static func drawBackground(
		control: NSButton,
		hover: Bool
	)
	{
		let pressed = control.cell?.isHighlighted == true
		let active = control.isEnabled && (pressed || hover)
		(active ? AppKitColorTokens.imageControlHover : AppKitColorTokens.imageControlSurface)
			.setFill()
		let shape = NSBezierPath(
			roundedRect: control.bounds,
			xRadius: control.bounds.height / 2,
			yRadius: control.bounds.height / 2
		)
		shape.fill()
	}

}
