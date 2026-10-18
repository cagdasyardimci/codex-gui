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
		ViewerToolbarButton.icon(
			title,
			image: image,
			target: target,
			action: action
		)
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
