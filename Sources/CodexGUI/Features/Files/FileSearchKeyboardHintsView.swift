import AppKit

@MainActor
final class FileSearchKeyboardHintsView: DesktopShortcutHintsView
{
	init()
	{
		super.init(hints: [("↑ ↓", "navigate"), ("↵", "open")])
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
