import AppKit

/// Search rows truncate the primary name and secondary context independently.
@MainActor
final class DesktopSearchResultButton: DesktopLayerButton
{
	init(
		title: String,
		context: String,
		shortcut: String = "",
		inlineContext: Bool = false,
		target: AnyObject?,
		action: Selector?
	)
	{
		super.init(frame: .zero)
		self.title = ""
		self.target = target
		self.action = action
		isBordered = false
		wantsLayer = true
		layer?.cornerRadius = 12
		let name = NSTextField(labelWithString: title)
		name.font = .systemFont(ofSize: 14)
		name.lineBreakMode = .byTruncatingMiddle
		name.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let detail = NSTextField(labelWithString: context)
		detail.font = .systemFont(ofSize: 13)
		detail.textColor = .secondaryLabelColor
		detail.lineBreakMode = .byTruncatingMiddle
		detail.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let key = NSTextField(labelWithString: shortcut)
		key.font = .systemFont(ofSize: 11)
		key.textColor = .secondaryLabelColor
		let keycap = DesktopSurface(
			AppKitColorTokens.searchResultSelection,
			cornerRadius: 7
		)
		AppKitLayout.pin(
			key,
			to: keycap,
			inset: 2
		)
		key.setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
		let spacer = NSView()
		let row = AppKitLayout.horizontalStack(
			inlineContext ? [name, detail, spacer, keycap] : [name, spacer, detail, keycap],
			spacing: 8
		)
		row.translatesAutoresizingMaskIntoConstraints = false
		addSubview(row)
		NSLayoutConstraint.activate([
			row.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 8
			),
			row.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -8
			),
			row.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		name.setContentHuggingPriority(
			.defaultHigh,
			for: .horizontal
		)
		detail.setContentHuggingPriority(
			.defaultHigh,
			for: .horizontal
		)
		detail.widthAnchor.constraint(
			lessThanOrEqualTo: row.widthAnchor,
			multiplier: 0.4
		)
		.isActive = true
		keycap.isHidden = shortcut.isEmpty
		setAccessibilityLabel([title, context, shortcut].filter
		{
			!$0.isEmpty
		}
		.joined(separator: ", "))
		toolTip = [title, context].joined(separator: " · ")
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		bounds.contains(convert(
			point,
			from: superview
		)) ? self : nil
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
