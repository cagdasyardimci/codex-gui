import AppKit

/// The visible tree geometry shared by the workspace and comparison navigators.
@MainActor
enum ViewerFileTreeLayout
{
	static let rowHeight: CGFloat = 28
	static let indentation: CGFloat = 16
	static let iconSize: CGFloat = 16
	static let leadingInset: CGFloat = 8
	static let labelGap: CGFloat = 8

	static func configure(_ table: NSTableView)
	{
		table.rowHeight = rowHeight
		table.style = .plain
		table.backgroundColor = .clear
		table.selectionHighlightStyle = .regular
		table.usesAlternatingRowBackgroundColors = false
	}
}

@MainActor
final class ViewerFileTreeRow: NSTableCellView
{
	let iconView = NSImageView()
	let nameLabel = NSTextField(labelWithString: "")
	private let disclosure = NSButton()
	private let accessory = NSStackView()
	private var depth = 0
	private var isDirectory = false
	private var directoryPath = ""
	private var onToggle: (() -> Void)?

	init()
	{
		super.init(frame: .zero)
		wantsLayer = true
		iconView.setAccessibilityElement(false)
		nameLabel.font = .systemFont(ofSize: 13)
		nameLabel.lineBreakMode = .byTruncatingTail
		nameLabel.cell?.usesSingleLineMode = true
		nameLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		disclosure.isBordered = false
		disclosure.imagePosition = .imageOnly
		disclosure.target = self
		disclosure.action = #selector(toggleDirectory)
		disclosure.setButtonType(.momentaryPushIn)
		accessory.orientation = .horizontal
		accessory.alignment = .centerY
		accessory.spacing = 6
		for child in [iconView, nameLabel, disclosure, accessory]
		{
			addSubview(child)
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func configure(
		name: String,
		path: String,
		depth: Int,
		isDirectory: Bool,
		isExpanded: Bool,
		icon: NSImage?,
		secondary: Bool = false,
		accessories: [NSView] = [],
		onToggle: (() -> Void)? = nil
	)
	{
		self.depth = max(
			0,
			depth
		)
		self.isDirectory = isDirectory
		directoryPath = path
		self.onToggle = onToggle
		nameLabel.stringValue = name
		nameLabel.textColor = secondary ? .secondaryLabelColor : .labelColor
		iconView.image = icon
		iconView.contentTintColor = .secondaryLabelColor
		iconView.isHidden = icon == nil
		disclosure.isHidden = !isDirectory
		if isDirectory
		{
			setExpanded(isExpanded)
		}
		for view in accessory.arrangedSubviews
		{
			accessory.removeArrangedSubview(view)
			view.removeFromSuperview()
		}
		for view in accessories
		{
			accessory.addArrangedSubview(view)
		}
		accessory.isHidden = accessories.isEmpty
		toolTip = path
		setAccessibilityLabel(path)
		needsLayout = true
		needsDisplay = true
	}

	func setExpanded(_ expanded: Bool)
	{
		guard isDirectory
		else
		{
			return
		}
		disclosure.image = DesktopIcons.image(
			expanded ? .chevronSmallDown : .chevronSmallRight,
			size: ViewerFileTreeLayout.iconSize
		)
		disclosure.contentTintColor = .secondaryLabelColor
		disclosure.setAccessibilityLabel("\(expanded ? "Collapse" : "Expand") \(directoryPath)")
	}

	override func layout()
	{
		super.layout()
		let layout = ViewerFileTreeLayout.self
		let leading = layout.leadingInset + CGFloat(depth) * layout.indentation
		let iconRect = NSRect(
			x: leading,
			y: (bounds.height - layout.iconSize) / 2,
			width: layout.iconSize,
			height: layout.iconSize
		)
		disclosure.frame = iconRect
		iconView.frame = iconRect
		let accessoryWidth = accessory.isHidden ? 0 : accessory.fittingSize.width
		accessory.frame = NSRect(
			x: max(
				0,
				bounds.maxX - accessoryWidth - 4
			),
			y: 0,
			width: accessoryWidth,
			height: bounds.height
		)
		let labelX = iconRect.maxX + layout.labelGap
		let labelEnd = accessory.isHidden ? bounds.maxX - 4 : accessory.frame.minX - 6
		nameLabel.frame = NSRect(
			x: labelX,
			y: (bounds.height - nameLabel.intrinsicContentSize.height) / 2,
			width: max(
				0,
				labelEnd - labelX
			),
			height: nameLabel.intrinsicContentSize.height
		)
	}

	override func draw(_ dirtyRect: NSRect)
	{
		super.draw(dirtyRect)
		guard depth > 0
		else
		{
			return
		}
		AppKitColorTokens.border.setStroke()
		for level in 0 ..< depth
		{
			let x = ViewerFileTreeLayout.leadingInset + 8
				+ CGFloat(level) * ViewerFileTreeLayout.indentation
			let guide = NSBezierPath()
			guide.move(to: NSPoint(
				x: x,
				y: bounds.minY
			))
			guide.line(to: NSPoint(
				x: x,
				y: bounds.maxY
			))
			guide.lineWidth = 1
			guide.stroke()
		}
	}

	@objc private func toggleDirectory()
	{
		guard isDirectory
		else
		{
			return
		}
		onToggle?()
	}
}

@MainActor
final class ViewerFileTreeSelectionRow: NSTableRowView
{
	override var interiorBackgroundStyle: NSView.BackgroundStyle
	{
		.normal
	}

	override func drawSelection(in dirtyRect: NSRect)
	{
		guard isSelected
		else
		{
			return
		}
		let outline = NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: 1,
				dy: 1
			),
			xRadius: 6,
			yRadius: 6
		)
		AppKitColorTokens.canvas.setFill()
		outline.fill()
		NSColor.systemBlue.setStroke()
		outline.lineWidth = 1
		outline.stroke()
	}
}
