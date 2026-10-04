import AppKit

/// Shared reference controls for the Changes review surface.
@MainActor
enum GitReviewControls
{
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
