import AppKit

/// Shared reference controls for the Changes review surface.
@MainActor
enum GitReviewControls
{
	static func pill(
		_ content: NSView,
		radius: CGFloat = 20,
		horizontalInset: CGFloat = 10,
		verticalInset: CGFloat = 10
	) -> NSView
	{
		let surface = DesktopSurface(
			DesktopTheme.elevated,
			cornerRadius: radius
		)
		surface.addSubview(content)
		content.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			content.leadingAnchor.constraint(
				equalTo: surface.leadingAnchor,
				constant: horizontalInset
			),
			content.trailingAnchor.constraint(
				equalTo: surface.trailingAnchor,
				constant: -horizontalInset
			),
			content.topAnchor.constraint(
				equalTo: surface.topAnchor,
				constant: verticalInset
			),
			content.bottomAnchor.constraint(
				equalTo: surface.bottomAnchor,
				constant: -verticalInset
			),
		])
		return surface
	}

	static func referenceButton(
		_ title: String,
		image: NSImage,
		target: AnyObject?,
		action: Selector?
	) -> NSButton
	{
		let control = NSButton(
			image: image,
			target: target,
			action: action
		)
		styleReferenceButton(control)
		control.toolTip = title
		control.setAccessibilityLabel(title)
		return control
	}

	static func styleReferenceButton(_ control: NSButton)
	{
		control.isBordered = false
		control.focusRingType = .none
		control.contentTintColor = .secondaryLabelColor
		control.widthAnchor.constraint(equalToConstant: 28).isActive = true
		control.heightAnchor.constraint(equalToConstant: 28).isActive = true
	}

	static func spacer() -> NSView
	{
		let space = NSView()
		space.setContentHuggingPriority(
			NSLayoutConstraint.Priority(1),
			for: .horizontal
		)
		return space
	}
}
