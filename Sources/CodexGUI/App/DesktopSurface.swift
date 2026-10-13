import AppKit

@MainActor
final class DesktopSurface: NSView
{
	private let color: NSColor
	private let cornerRadius: CGFloat
	private let bordered: Bool
	private let borderWidth: CGFloat
	private let borderColor: NSColor

	init(
		_ color: NSColor,
		cornerRadius: CGFloat = 0,
		bordered: Bool = false,
		borderWidth: CGFloat = 1,
		borderColor: NSColor? = nil
	)
	{
		self.color = color
		self.cornerRadius = cornerRadius
		self.bordered = bordered
		self.borderWidth = borderWidth
		self.borderColor = borderColor ?? AppKitColorTokens.border
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var isOpaque: Bool
	{
		cornerRadius == 0
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		color.setFill()
		let inset: CGFloat = bordered ? borderWidth / 2 : 0
		let path = NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: inset,
				dy: inset
			),
			xRadius: cornerRadius,
			yRadius: cornerRadius
		)
		path.fill()
		if bordered
		{
			borderColor.setStroke()
			path.lineWidth = borderWidth
			path.stroke()
		}
	}
}
