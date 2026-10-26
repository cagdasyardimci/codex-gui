import AppKit

/// Complete native toolbar icon control; semantic presets retain each chrome's native cell.
@MainActor
final class DesktopToolbarIconButton: DesktopHoverButton
{
	enum Preset
	{
		case windowToolbar, contentToolbar, toolsHeader
		case tabClose(metrics: LayoutTokens.TabContent)
		case tabOverflow(metrics: LayoutTokens.TabContent)
	}

	var label: String
	{
		didSet
		{
			updateLabel()
		}
	}
	private let side: CGFloat

	init(
		image: NSImage?,
		label: String,
		preset: Preset,
		target: AnyObject? = nil,
		action: Selector? = nil,
		isEnabled: Bool = true
	)
	{
		self.label = label
		switch preset
		{
		case .windowToolbar, .contentToolbar: side = LayoutTokens.Toolbar.controlSize
		case .toolsHeader: side = LayoutTokens.Tabs.controlSize
		case .tabClose(let metrics): side = metrics.closeControlSize
		case .tabOverflow(let metrics): side = metrics.moreControlSize
		}
		super.init(frame: .zero)
		title = ""
		self.target = target
		self.action = action
		switch preset
		{
		case .windowToolbar:
			bezelStyle = .inline
			cornerRadius = ShapeTokens.Toolbar.controlRadius
		case .contentToolbar:
			bezelStyle = .texturedRounded
		case .toolsHeader, .tabClose, .tabOverflow:
			AppKitControlStyling.styleButton(self)
			cornerCurve = ShapeTokens.TabControls.cornerCurve
			if case .tabClose = preset
			{
				cornerRadius = ShapeTokens.TabControls.closeRadius
			}
			else
			{
				cornerRadius = ShapeTokens.TabControls.standardRadius
			}
		}
		isBordered = false
		self.image = image
		imagePosition = .imageOnly
		contentTintColor = AppKitColorTokens.secondaryText
		self.isEnabled = isEnabled
		updateLabel()
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: side),
			heightAnchor.constraint(equalToConstant: side),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var intrinsicContentSize: NSSize
	{
		NSSize(
			width: side,
			height: side
		)
	}

	private func updateLabel()
	{
		toolTip = label
		setAccessibilityLabel(label)
	}
}
