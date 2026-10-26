import AppKit

/// Complete native text prompt with owned field geometry, focus, and response extraction.
@MainActor
final class DesktopTextEntryPrompt
{
	struct Field
	{
		let value: String
		let placeholder: String?
		let accessibilityLabel: String
	}

	enum Layout
	{
		case single, multiple
	}

	private let confirmation: DesktopNativeConfirmation
	let fields: [NSTextField]

	init(
		title: String,
		detail: String = "",
		actionTitle: String,
		fields definitions: [Field],
		layout: Layout
	)
	{
		confirmation = DesktopNativeConfirmation(
			title: title,
			message: detail,
			confirmTitle: actionTitle,
			defaultAction: .confirm
		)
		let alert = confirmation.alert
		fields = definitions.map
		{
			definition in
			let field = NSTextField(string: definition.value)
			field.placeholderString = definition.placeholder
			field.setAccessibilityLabel(definition.accessibilityLabel)
			return field
		}
		switch layout
		{
		case .single:
			precondition(fields.count == 1)
			fields[0].frame = NSRect(
				origin: .zero,
				size: NSSize(
					width: 320,
					height: 24
				)
			)
			alert.accessoryView = fields[0]
			alert.window.initialFirstResponder = fields[0]
		case .multiple:
			for field in fields
			{
				field.widthAnchor.constraint(equalToConstant: 340).isActive = true
			}
			alert.accessoryView = AppKitLayout.verticalStack(
				fields,
				spacing: 8
			)
		}
	}

	func beginSheet(
		in window: NSWindow,
		completion: @escaping ([String]?) -> Void
	)
	{
		confirmation.beginSheet(in: window)
		{
			[fields] confirmed in
			completion(confirmed ? fields.map(\.stringValue) : nil)
		}
	}
}
