import AppKit

@MainActor
final class ToolbarSeparatorView: NSView
{
	init(constrained: Bool = true)
	{
		super.init(frame: .zero)
		setAccessibilityElement(false)
		if constrained
		{
			widthAnchor.constraint(equalToConstant: 1).isActive = true
			heightAnchor.constraint(equalToConstant: 18).isActive = true
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		nil
	}

	override func draw(_ dirtyRect: NSRect)
	{
		NSColor.separatorColor.setFill()
		bounds.fill()
	}
}
