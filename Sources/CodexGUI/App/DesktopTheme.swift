import AppKit

@MainActor
enum DesktopTheme
{
	static let canvas = color(
		light: 0xFFFFFF,
		dark: 0x181818
	)
	static let slashMenu = color(
		light: 0xFFFFFF,
		dark: 0x2D2D2D
	)
	static let slashMenuSelection = color(
		light: 0xF1F2F2,
		dark: 0x3C3C3C
	)
	static let sidebar = color(
		light: 0xF7F7F7,
		dark: 0x1E1E1E
	)
	static let elevated = color(
		light: 0xF5F5F5,
		dark: 0x272727
	)
	static let inspector = color(
		light: 0xF4F4F4,
		dark: 0x2D2D2D
	)
	static let chrome = color(
		light: 0xF7F7F7,
		dark: 0x242424
	)
	static let input = color(
		light: 0xF0F0F0,
		dark: 0x363636
	)
	static let selection = color(
		light: 0xE8E8E8,
		dark: 0x303030
	)
	static let border = color(
		light: 0xE4E4E4,
		dark: 0x363636
	)
	static let paneDivider = color(
		light: 0xE4E4E4,
		dark: 0x363636
	)
	static let highlightedPaneDivider = color(
		light: 0xD1D1D2,
		dark: 0x4A4A4A
	)
	static let userBubble = color(
		light: 0xECECEC,
		dark: 0x343434
	)

	static func styleButton(
		_ button: NSButton,
		icon: DesktopIcon? = nil,
		prominent: Bool = false
	)
	{
		button.bezelStyle = .inline
		button.isBordered = false
		button.controlSize = .small
		button.font = .systemFont(
			ofSize: 12,
			weight: prominent ? .medium : .regular
		)
		button.contentTintColor = prominent ? .labelColor : .secondaryLabelColor
		if let icon
		{
			button.image = DesktopIcons.image(
				icon,
				size: 13
			)
			button.imagePosition = .imageLeading
		}
		button.toolTip = button.toolTip ?? button.title
		button.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
	}

	static func stylePopup(_ popup: NSPopUpButton)
	{
		popup.bezelStyle = .inline
		popup.isBordered = false
		popup.controlSize = .small
		popup.font = .systemFont(ofSize: 12)
		popup.contentTintColor = .secondaryLabelColor
	}

	static func sectionLabel(_ text: String) -> NSTextField
	{
		let label = NSTextField(labelWithString: text)
		label.font = .systemFont(
			ofSize: 11,
			weight: .medium
		)
		label.textColor = .secondaryLabelColor
		return label
	}

	private static func color(
		light: UInt32,
		dark: UInt32
	) -> NSColor
	{
		NSColor(name: nil)
		{
			appearance in
			let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
			return NSColor(
				srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
				green: CGFloat((value >> 8) & 0xFF) / 255,
				blue: CGFloat(value & 0xFF) / 255,
				alpha: 1
			)
		}
	}
}

@MainActor
final class DesktopSegmentedControl: NSSegmentedControl
{
	override var intrinsicContentSize: NSSize
	{
		NSSize(
			width: NSView.noIntrinsicMetric,
			height: super.intrinsicContentSize.height
		)
	}

	override func layout()
	{
		super.layout()
		guard bounds.width > 0, segmentCount > 0
		else
		{
			return
		}
		let width = floor(max(
			1,
			bounds.width - 4
		) / CGFloat(segmentCount))
		for segment in 0 ..< segmentCount
		{
			if self.width(forSegment: segment) != width
			{
				setWidth(
					width,
					forSegment: segment
				)
			}
		}
	}
}

@MainActor
final class DesktopSurface: NSView
{
	private let color: NSColor
	private let cornerRadius: CGFloat
	private let bordered: Bool

	init(
		_ color: NSColor,
		cornerRadius: CGFloat = 0,
		bordered: Bool = false
	)
	{
		self.color = color
		self.cornerRadius = cornerRadius
		self.bordered = bordered
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
		let inset: CGFloat = bordered ? 0.5 : 0
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
			DesktopTheme.border.setStroke()
			path.lineWidth = 1
			path.stroke()
		}
	}
}
