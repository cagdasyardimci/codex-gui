import AppKit

/// A complete labeled form field, including its description, input, validation, and accessibility.
@MainActor
final class SettingsFormField: NSView, NSTextFieldDelegate
{
	var onChange: ((String) -> Void)?
	var onEndEditing: ((String) -> Void)?
	let input: SettingsFormTextField?
	let content: NSView
	private let titleLabel: NSTextField
	private let detailLabel: SettingsMessageLabel
	private let errorLabel: SettingsFormErrorLabel
	private let statusLabel = SettingsMessageLabel(wrappingLabelWithString: "")
	private let feedback = NSStackView()
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
			errorLabel.stringValue = newValue
			input?.hasValidationError = !newValue.isEmpty
			refreshFeedback()
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
			statusLabel.stringValue = newValue
			refreshFeedback()
		}
	}

	convenience init(
		title: String,
		detail: String? = nil,
		placeholder: String? = nil,
		accessibilityLabel: String? = nil,
		presentation: SettingsFormTextField.Presentation = .outlined,
		showsTitle: Bool = true
	)
	{
		let field = SettingsFormTextField(presentation: presentation)
		field.placeholderString = placeholder ?? title
		field.setAccessibilityLabel(accessibilityLabel ?? title)
		self.init(
			title: title,
			detail: detail,
			content: field,
			showsTitle: showsTitle
		)
	}

	init(
		title: String,
		detail: String? = nil,
		content: NSView,
		showsTitle: Bool = true
	)
	{
		self.content = content
		input = content as? SettingsFormTextField
		titleLabel = NSTextField(labelWithString: title)
		detailLabel = SettingsMessageLabel(wrappingLabelWithString: detail ?? "")
		errorLabel = SettingsFormErrorLabel()
		super.init(frame: .zero)
		titleLabel.font = AppKitFontResolver.font(TypographyTokens.Connections.body)
		titleLabel.textColor = AppKitColorTokens.settingsSecondaryText
		titleLabel.isHidden = !showsTitle
		detailLabel.font = .systemFont(ofSize: 12)
		detailLabel.textColor = AppKitColorTokens.settingsSecondaryText
		detailLabel.isHidden = (detail ?? "").isEmpty
		errorLabel.setAccessibilityLabel("\(title) validation error")
		statusLabel.font = .systemFont(ofSize: 12)
		statusLabel.textColor = AppKitColorTokens.settingsSecondaryText
		feedback.orientation = .vertical
		feedback.alignment = .leading
		feedback.spacing = 0
		for label in [errorLabel, statusLabel]
		{
			feedback.addArrangedSubview(label)
			label.widthAnchor.constraint(equalTo: feedback.widthAnchor).isActive = true
		}
		let stack = AppKitLayout.verticalStack(
			[titleLabel, detailLabel, content, feedback],
			spacing: 4
		)
		AppKitLayout.pin(
			stack,
			to: self,
			inset: 0
		)
		for view in [titleLabel, detailLabel, content, feedback]
		{
			view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		input?.delegate = self
		refreshFeedback()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	private func refreshFeedback()
	{
		statusLabel.isHidden = supportingStatus.isEmpty || !validationError.isEmpty
		feedback.isHidden = validationError.isEmpty && supportingStatus.isEmpty
		let help = validationError.isEmpty ? supportingStatus : validationError
		input?.setAccessibilityHelp(help.isEmpty ? nil : help)
		feedback.invalidateIntrinsicContentSize()
		invalidateIntrinsicContentSize()
		needsLayout = true
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

/// Validation text used by complete field components and form-level validation summaries.
@MainActor
final class SettingsFormErrorLabel: NSTextField
{
	override var stringValue: String
	{
		didSet
		{
			isHidden = stringValue.isEmpty
		}
	}

	init()
	{
		super.init(frame: .zero)
		isEditable = false
		isSelectable = false
		isBordered = false
		drawsBackground = false
		usesSingleLineMode = false
		cell?.wraps = true
		cell?.isScrollable = false
		font = .systemFont(ofSize: 12)
		textColor = AppKitColorTokens.settingsFieldError
		isHidden = true
		setAccessibilityRole(.staticText)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
