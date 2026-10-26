import AppKit

/// Empty status messages do not reserve a row or spacing in settings stacks.
@MainActor
final class SettingsMessageLabel: NSTextField
{
	override var stringValue: String
	{
		didSet
		{
			isHidden = stringValue.isEmpty
		}
	}
}
