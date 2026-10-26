import AppKit

@MainActor
final class ToolbarSeparatorView: NSView
{
	private static let separatorWidth: CGFloat = 1
	private static let separatorHeight: CGFloat = 18

	static func frame(
		dividerPosition: NSPoint,
		hostBounds: NSRect,
		backingScale: CGFloat
	) -> NSRect
	{
		let leadingEdge = dividerPosition.x - separatorWidth / 2
		let alignedLeadingEdge = (leadingEdge * backingScale).rounded() / backingScale

		return NSRect(
			x: alignedLeadingEdge,
			y: hostBounds.midY - separatorHeight / 2,
			width: separatorWidth,
			height: separatorHeight
		)
	}

	init(constrained: Bool = true)
	{
		super.init(frame: .zero)
		setAccessibilityElement(false)
		if constrained
		{
			widthAnchor.constraint(equalToConstant: Self.separatorWidth).isActive = true
			heightAnchor.constraint(equalToConstant: Self.separatorHeight).isActive = true
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
