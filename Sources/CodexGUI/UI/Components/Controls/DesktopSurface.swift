import AppKit

@MainActor
class DesktopSurface: NSView
{
	private let color: NSColor
	private let cornerRadius: CGFloat
	private let cornerCurve: ShapeTokens.CornerCurve
	private let bordered: Bool
	private let borderWidth: CGFloat
	private let borderColor: NSColor
	private let shadows: [ShadowTokens.Style]
	private var shadowLayers: [CALayer] = []

	init(
		_ color: NSColor,
		cornerRadius: CGFloat = 0,
		cornerCurve: ShapeTokens.CornerCurve = .circular,
		bordered: Bool = false,
		borderWidth: CGFloat = 1,
		borderColor: NSColor? = nil,
		shadows: [ShadowTokens.Style] = []
	)
	{
		self.color = color
		self.cornerRadius = cornerRadius
		self.cornerCurve = cornerCurve
		self.bordered = bordered
		self.borderWidth = borderWidth
		self.borderColor = borderColor ?? AppKitColorTokens.border
		self.shadows = shadows
		super.init(frame: .zero)
		if !shadows.isEmpty
		{
			wantsLayer = true
			for _ in shadows
			{
				let shadow = CALayer()
				layer?.insertSublayer(
					shadow,
					at: 0
				)
				shadowLayers.append(shadow)
			}
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var isOpaque: Bool
	{
		false
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		updateShadows()
		needsDisplay = true
	}

	override func layout()
	{
		super.layout()
		updateShadows()
	}

	private func updateShadows()
	{
		for (shadow, layer) in zip(
			shadows,
			shadowLayers
		)
		{
			AppKitShadowRenderer.apply(
				shadow,
				to: layer,
				in: self,
				cornerRadius: cornerRadius,
				cornerCurve: cornerCurve
			)
		}
	}

	override func draw(_ dirtyRect: NSRect)
	{
		color.setFill()
		let inset: CGFloat = bordered ? borderWidth / 2 : 0
		let path = AppKitShapePath.roundedRect(
			bounds.insetBy(
				dx: inset,
				dy: inset
			),
			radius: cornerRadius,
			curve: cornerCurve
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
