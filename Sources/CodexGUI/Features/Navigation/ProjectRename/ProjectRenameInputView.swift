import AppKit

/// Compatibility container for the complete dialog form-input presentation.
@MainActor
final class ProjectRenameInputView: NSView
{
	private let component = SettingsFormField(
		title: "Project name",
		presentation: .dialog,
		showsTitle: false
	)
	var field: SettingsFormTextField
	{
		component.input!
	}

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		AppKitLayout.pin(
			component,
			to: self,
			inset: 0
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
