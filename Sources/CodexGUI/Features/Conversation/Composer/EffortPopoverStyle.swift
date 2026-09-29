import AppKit

@MainActor
enum EffortPopoverStyle
{
	static let blue = NSColor(
		srgbRed: 0x39 / 255.0,
		green: 0x7E / 255.0,
		blue: 0xF5 / 255.0,
		alpha: 1
	)
	static let surface = color(
		light: 0xF4F4F4,
		dark: 0x2A2A2A
	)
	static let border = color(
		light: 0xD5D5D5,
		dark: 0x414141
	)
	static let track = color(
		light: 0xD8D8D8,
		dark: 0x414141
	)
	static let tick = color(
		light: 0x7D7D7D,
		dark: 0xA0A0A0
	)
	static let model = color(
		light: 0x5C5C5C,
		dark: 0xB0B0B0
	)
	static let icon = color(
		light: 0x6B6B6B,
		dark: 0xA0A0A0
	)

	private static func color(
		light: UInt32,
		dark: UInt32
	) -> NSColor
	{
		NSColor(name: nil)
		{
			appearance in
			let usesDarkAppearance = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			let rgbValue = usesDarkAppearance ? dark : light
			return NSColor(
				srgbRed: CGFloat((rgbValue >> 16) & 0xFF) / 255,
				green: CGFloat((rgbValue >> 8) & 0xFF) / 255,
				blue: CGFloat(rgbValue & 0xFF) / 255,
				alpha: 1
			)
		}
	}
}

@MainActor
final class EffortPopoverSurface: NSView
{
	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		let path = NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: 0.5,
				dy: 0.5
			),
			xRadius: 16,
			yRadius: 16
		)
		EffortPopoverStyle.surface.setFill()
		path.fill()
		EffortPopoverStyle.border.setStroke()
		path.lineWidth = 1
		path.stroke()
	}
}
