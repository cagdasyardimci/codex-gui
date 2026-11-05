import AppKit

/// A complete labeled form field, including its description, input, validation, and accessibility.
@MainActor
final class SettingsFormField: NSView, NSTextFieldDelegate
{
	enum Layout
	{
		case standard, cardRow
	}
	var onChange: ((String) -> Void)?
	var onEndEditing: ((String) -> Void)?
	let input: SettingsFormTextField?
	let content: NSView
	private let titleLabel: NSTextField
	private let detailLabel: SettingsMessageLabel
	private var validationError = ""
	private var supportingStatus = ""

	var title: String
	{
		get
		{
			titleLabel.stringValue
		}
		set
		{
			titleLabel.stringValue = newValue
		}
	}
	var stringValue: String
	{
		get
		{
			input?.stringValue ?? ""
		}
		set
		{
			input?.stringValue = newValue
		}
	}
	var isEditable: Bool
	{
		get
		{
			input?.isEditable ?? false
		}
		set
		{
			input?.isEditable = newValue
		}
	}
	var error: String
	{
		get
		{
			validationError
		}
		set
		{
			validationError = newValue
			input?.hasValidationError = !newValue.isEmpty
		}
	}
	var status: String
	{
		get
		{
			supportingStatus
		}
		set
		{
			supportingStatus = newValue
		}
	}

	convenience init(
		title: String,
		detail: String? = nil,
		placeholder: String? = nil,
		accessibilityLabel: String? = nil,
		presentation: SettingsFormTextField.Presentation = .outlined,
		leadingIcon: DesktopIcon? = nil,
		showsTitle: Bool = true,
		layout: Layout = .standard
	)
	{
		let field = SettingsFormTextField(
			presentation: presentation,
			leadingIcon: leadingIcon
		)
		field.placeholderString = placeholder ?? title
		field.setAccessibilityLabel(accessibilityLabel ?? title)
		self.init(
			title: title,
			detail: detail,
			content: field,
			showsTitle: showsTitle,
			layout: layout
		)
	}

	init(
		title: String,
		detail: String? = nil,
		content: NSView,
		showsTitle: Bool = true,
		layout: Layout = .standard
	)
	{
		self.content = content
		input = content as? SettingsFormTextField
		titleLabel = NSTextField(labelWithString: title)
		detailLabel = SettingsMessageLabel(wrappingLabelWithString: detail ?? "")
		super.init(frame: .zero)
		titleLabel
			.setTypographyRole(layout == .cardRow ? TypographyTokens.Text.control : TypographyTokens
				.Connections.body)
		titleLabel.textColor = layout == .cardRow ? AppKitColorTokens
			.settingsPrimaryText : AppKitColorTokens.settingsSecondaryText
		titleLabel.isHidden = !showsTitle
		detailLabel.setTypographyRole(TypographyTokens.Settings.formDescription)
		detailLabel.textColor = AppKitColorTokens.settingsSecondaryText
		detailLabel.isHidden = (detail ?? "").isEmpty
		let stack = AppKitLayout.verticalStack(
			[titleLabel, detailLabel, content],
			spacing: 4
		)
		AppKitLayout.pin(
			stack,
			to: self,
			inset: layout == .cardRow ? 12 : 0
		)
		for view in [titleLabel, detailLabel, content]
		{
			view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		input?.delegate = self
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func controlTextDidChange(_ notification: Notification)
	{
		onChange?(stringValue)
	}

	func controlTextDidEndEditing(_ notification: Notification)
	{
		onEndEditing?(stringValue)
	}
}
