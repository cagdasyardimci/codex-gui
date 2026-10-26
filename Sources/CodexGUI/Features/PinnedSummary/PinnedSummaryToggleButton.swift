import AppKit

/// Toolbar summary toggle uses the shared selected-icon presentation.
@MainActor
final class PinnedSummaryToggleButton: DesktopStyledButton
{
	init(
		title: String,
		target: AnyObject?,
		action: Selector?
	)
	{
		super.init(
			title: title,
			presentation: .toggle
		)
		self.target = target
		self.action = action
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
