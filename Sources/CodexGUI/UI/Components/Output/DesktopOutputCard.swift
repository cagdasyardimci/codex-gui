import AppKit

/// A complete output container with one header, surface, content column and action slot.
@MainActor
class DesktopOutputCard: DesktopSurface
{
	enum Presentation
	{
		case code, terminal, error
	}

	static let contentInset: CGFloat = 12
	static let headerHeight: CGFloat = 20
	static let headerSpacing: CGFloat = 8
	static let headerAndInsetsHeight = contentInset * 2 + headerHeight + headerSpacing

	let bodyView: NSView
	let titleLabel: NSTextField

	init(
		title: String,
		presentation: Presentation,
		body: NSView,
		accessory: NSView? = nil
	)
	{
		bodyView = body
		titleLabel = NSTextField(labelWithString: title)
		let error = presentation == .error
		let fill = error ? AppKitColorResolution.color(
			light: 0xFEF1F0,
			dark: 0x270B0A
		) : AppKitColorTokens.elevated
		let edge = error ? AppKitColorResolution.color(
			light: 0xFBD5D3,
			dark: 0x7C221F
		) : AppKitColorTokens.border
		super.init(
			fill,
			cornerRadius: 12,
			bordered: true,
			borderColor: edge
		)

		var content: [NSView] = []
		if !error
		{
			let icon = NSImageView(image: DesktopIcons.image(
				presentation == .terminal ? .terminal : .code,
				size: 16
			))
			icon.contentTintColor = AppKitColorTokens.secondaryText
			icon.setAccessibilityElement(false)
			icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
			icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
			titleLabel.font = .systemFont(ofSize: 13)
			titleLabel.textColor = AppKitColorTokens.primaryText
			titleLabel.lineBreakMode = .byTruncatingTail
			titleLabel.setContentCompressionResistancePriority(
				.defaultLow,
				for: .horizontal
			)
			let views: [NSView] = [icon, titleLabel, NSView()] + (accessory.map
			{
				[$0]
			} ?? [])
			let header = AppKitLayout.horizontalStack(
				views,
				spacing: 6
			)
			header.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.headerHeight)
				.isActive = true
			content.append(header)
		}
		content.append(body)
		let stack = AppKitLayout.verticalStack(
			content,
			spacing: Self.headerSpacing
		)
		for child in content
		{
			child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		AppKitLayout.pin(
			stack,
			to: self,
			inset: Self.contentInset
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
