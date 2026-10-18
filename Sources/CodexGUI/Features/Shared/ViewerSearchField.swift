import AppKit

@MainActor
final class ViewerSearchField: NSSearchField
{
	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		cell = ViewerSearchFieldCell(textCell: "")
		isEditable = true
		isSelectable = true
		isBordered = false
		drawsBackground = false
		if let searchCell = cell as? NSSearchFieldCell
		{
			searchCell.searchButtonCell?.image = DesktopIcons.image(.search)
			if let clear = DesktopIcon(rawValue: "XCircleFilledCrossedClose")
			{
				searchCell.cancelButtonCell?.image = DesktopIcons.image(
					clear,
					size: 13
				)
			}
		}
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
		let path = NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: 0.5,
				dy: 0.5
			),
			xRadius: 9,
			yRadius: 9
		)
		AppKitColorTokens.canvas.setFill()
		path.fill()
		AppKitColorTokens.subtleEdge.setStroke()
		path.stroke()
		super.draw(dirtyRect)
	}
}

@MainActor
private final class ViewerSearchFieldCell: NSSearchFieldCell
{
	override func searchButtonRect(forBounds rect: NSRect) -> NSRect
	{
		NSRect(
			x: rect.minX + 10,
			y: rect.midY - 8,
			width: 16,
			height: 16
		)
	}

	override func cancelButtonRect(forBounds rect: NSRect) -> NSRect
	{
		NSRect(
			x: rect.maxX - 23,
			y: rect.midY - 6.5,
			width: 13,
			height: 13
		)
	}

	override func searchTextRect(forBounds rect: NSRect) -> NSRect
	{
		let font = font ?? NSFont.systemFont(ofSize: 13)
		let height = min(
			rect.height,
			ceil(font.ascender - font.descender + font.leading)
		)
		let leading = searchButtonRect(forBounds: rect).maxX + 6
		let trailing = stringValue.isEmpty ? rect.maxX - 10
			: cancelButtonRect(forBounds: rect).minX - 6
		return NSRect(
			x: leading,
			y: rect.midY - height / 2,
			width: max(
				0,
				trailing - leading
			),
			height: height
		)
	}
}
