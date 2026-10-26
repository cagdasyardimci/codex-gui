import AppKit

/// A complete resource row owns its information hierarchy and standard inspect/remove actions.
@MainActor
final class DesktopResourceRow: NSView
{
	enum Presentation
	{
		case attachment, file, compact
	}

	struct Action
	{
		let title: String
		let icon: DesktopIcon
		let accessibilityLabel: String
		let identifier: String
		let perform: (NSButton) -> Void
	}

	let titleLabel: NSTextField
	let detailLabel: NSTextField?
	private(set) var actionButtons: [NSButton] = []

	init(
		title: String,
		detail: String? = nil,
		icon: NSImage? = nil,
		diffStats: DesktopDiffStats.Counts? = nil,
		presentation: Presentation,
		badge: String? = nil,
		actions: [Action] = []
	)
	{
		titleLabel = NSTextField(labelWithString: title)
		detailLabel = detail.map
		{
			NSTextField(wrappingLabelWithString: $0)
		}
		super.init(frame: .zero)
		titleLabel.font = .systemFont(
			ofSize: 13,
			weight: presentation == .attachment ? .medium : .regular
		)
		titleLabel.textColor = AppKitColorTokens.primaryText
		titleLabel
			.lineBreakMode = presentation == .compact ? .byTruncatingTail : .byTruncatingMiddle
		titleLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		titleLabel.toolTip = title
		var labels: [NSView] = [titleLabel]
		if let detailLabel
		{
			detailLabel.font = .systemFont(ofSize: 12)
			detailLabel.textColor = AppKitColorTokens.secondaryText
			detailLabel.lineBreakMode = .byTruncatingMiddle
			detailLabel.maximumNumberOfLines = 2
			detailLabel.setContentCompressionResistancePriority(
				.defaultLow,
				for: .horizontal
			)
			detailLabel.toolTip = detail
			labels.append(detailLabel)
		}
		let information = AppKitLayout.verticalStack(
			labels,
			spacing: 2
		)
		information.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		var content: [NSView] = []
		if let icon
		{
			let image = NSImageView(image: icon)
			image.imageScaling = .scaleProportionallyDown
			image.contentTintColor = AppKitColorTokens.secondaryText
			image.setAccessibilityElement(false)
			image.widthAnchor.constraint(equalToConstant: 16).isActive = true
			image.heightAnchor.constraint(equalToConstant: 16).isActive = true
			content.append(image)
		}
		content += [information, NSView()]
		if let badge
		{
			let badgeLabel = NSTextField(labelWithString: badge)
			badgeLabel.font = .systemFont(ofSize: 12)
			badgeLabel.textColor = AppKitColorTokens.secondaryText
			badgeLabel.setContentCompressionResistancePriority(
				.required,
				for: .horizontal
			)
			content.append(badgeLabel)
		}
		if let diffStats
		{
			let stats = DesktopDiffStats(
				counts: diffStats,
				presentation: .resource
			)
			stats.setContentCompressionResistancePriority(
				.required,
				for: .horizontal
			)
			content.append(stats)
		}
		for action in actions
		{
			let button = Self.actionButton(action)
			actionButtons.append(button)
			content.append(button)
		}
		let row = AppKitLayout.horizontalStack(
			content,
			spacing: presentation == .compact ? 10 : 8
		)
		AppKitLayout.pin(
			row,
			to: self,
			inset: 0
		)
		if presentation == .compact
		{
			heightAnchor.constraint(equalToConstant: 26).isActive = true
		}
		else
		{
			heightAnchor.constraint(greaterThanOrEqualToConstant: presentation == .file ? 36 : 28)
				.isActive = true
		}
		setAccessibilityLabel([title, detail].compactMap
		{
			$0
		}.joined(separator: ": "))
	}

	static func actionButton(_ action: Action) -> NSButton
	{
		let button = DesktopActionButton(
			title: action.title,
			presentation: .icon
		)
		button.image = DesktopIcons.image(
			action.icon,
			size: 14
		)
		button.imagePosition = .imageOnly
		button.identifier = NSUserInterfaceItemIdentifier(action.identifier)
		button.setAccessibilityLabel(action.accessibilityLabel)
		button.toolTip = action.title
		button.onAction =
		{
			[weak button] in
			guard let button
			else
			{
				return
			}
			action.perform(button)
		}
		return button
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
