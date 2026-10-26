import AppKit

/// Complete editable text or key/value row with an accessible remove action.
@MainActor
final class SettingsFormEntryRow: NSView, NSTextFieldDelegate
{
	var onChange: (() -> Void)?
	var onRemove: (() -> Void)?
	private let firstInput = SettingsFormTextField(presentation: .nativeRounded)
	private let secondInput: SettingsFormTextField?
	private let remove = DesktopActionButton(
		icon: .xCrossed,
		label: "Remove entry",
		action:
		{
		}
	)
	private let item: String

	var firstValue: String
	{
		firstInput.stringValue
	}
	var secondValue: String?
	{
		secondInput?.stringValue
	}

	init(
		firstValue: String,
		secondValue: String?,
		item: String
	)
	{
		self.item = item
		secondInput = secondValue.map
		{
			_ in SettingsFormTextField(presentation: .nativeRounded)
		}
		super.init(frame: .zero)
		firstInput.stringValue = firstValue
		secondInput?.stringValue = secondValue ?? ""
		firstInput.placeholderString = item.capitalized
		secondInput?.placeholderString = "\(item) value".capitalized
		firstInput.delegate = self
		secondInput?.delegate = self
		let inputs: [NSView] = [firstInput] + (secondInput.map
		{
			[$0]
		} ?? [])
		let stack = AppKitLayout.horizontalStack(
			inputs + [remove],
			spacing: 8
		)
		AppKitLayout.pin(
			stack,
			to: self,
			inset: 0
		)
		firstInput.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		secondInput?.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		if let secondInput
		{
			firstInput.widthAnchor.constraint(equalTo: secondInput.widthAnchor).isActive = true
		}
		remove.onAction =
		{
			[weak self] in self?.onRemove?()
		}
		updatePosition(
			1,
			canRemove: true
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func updatePosition(
		_ position: Int,
		canRemove: Bool
	)
	{
		firstInput.setAccessibilityLabel("\(item) \(position)")
		secondInput?.setAccessibilityLabel("\(item) value \(position)")
		remove.setAccessibilityLabel("Remove \(item) \(position)")
		remove.isEnabled = canRemove
	}

	func controlTextDidChange(_ notification: Notification)
	{
		onChange?()
	}
}
