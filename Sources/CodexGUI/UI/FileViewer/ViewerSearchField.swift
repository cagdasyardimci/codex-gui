import AppKit

/// Compatibility name for the complete viewer search presentation.
@MainActor
final class ViewerSearchField: DesktopSearchField
{
	var drawsSurface: Bool
	{
		get
		{
			presentation == .viewer
		}
		set
		{
			presentation = newValue ? .viewer : .viewerOverlay
		}
	}

	convenience init()
	{
		self.init(frame: .zero)
	}

	override init(frame frameRect: NSRect)
	{
		super.init(
			frame: frameRect,
			presentation: .viewer
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
