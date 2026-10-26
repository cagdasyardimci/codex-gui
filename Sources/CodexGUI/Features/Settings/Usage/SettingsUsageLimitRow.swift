import AppKit

/// An allowance row owns its labels, remaining bar, and accessible percentage presentation.
@MainActor
final class SettingsUsageLimitRow: SettingsContentRow
{
	init(limit: SettingsUsagePresentation.Limit)
	{
		let title = DesktopLineBoxLabel(
			limit.title,
			role: TypographyTokens.Connections.rowLabel
		)
		let reset = Self.secondary(limit.reset)
		let remaining = Self.secondary(limit.remaining.map
		{
			SettingsUsagePresentation.percent($0) + " left"
		} ?? "Unavailable")
		let details = NSStackView(views: [reset, NSView(), remaining])
		details.spacing = 12
		let views: [NSView] = [title, details] + (limit.remaining.map
		{
			[SettingsUsageLimitBar(
				remaining: $0,
				label: limit.accessibilityLabel
			)] as [NSView]
		} ?? [])
		let stack = AppKitLayout.verticalStack(
			views,
			spacing: 4
		)
		for view in views
		{
			view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		super.init(content: stack)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	private static func secondary(_ text: String) -> DesktopLineBoxLabel
	{
		let label = DesktopLineBoxLabel(
			text,
			role: TypographyTokens.Connections.caption
		)
		label.textColor = AppKitColorTokens.settingsSecondaryText
		return label
	}
}

@MainActor
private final class SettingsUsageLimitBar: NSView
{
	private let remaining: Double
	init(
		remaining: Double,
		label: String
	)
	{
		self.remaining = remaining
		super.init(frame: .zero)
		heightAnchor.constraint(equalToConstant: 6).isActive = true
		setAccessibilityElement(true)
		setAccessibilityRole(.progressIndicator)
		setAccessibilityLabel(label)
		setAccessibilityValue(SettingsUsagePresentation.percent(remaining) + " left")
	}
	required init?(coder: NSCoder)
	{
		nil
	}
	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}
	override func draw(_ dirtyRect: NSRect)
	{
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		let path = NSBezierPath(
			roundedRect: bounds,
			xRadius: 3,
			yRadius: 3
		)
		AppKitColorTokens.connectionsEdge.setFill()
		path.fill()
		path.addClip()
		AppKitColorTokens.settingsPrimaryText.setFill()
		NSRect(
			x: 0,
			y: 0,
			width: bounds.width * remaining / 100,
			height: bounds.height
		).fill()
	}
}
