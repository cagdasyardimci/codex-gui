import AppKit

/// Complete text prompt with owned typography, focus, and once-only response extraction.
@MainActor
final class DesktopTextEntryPrompt: NSObject
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

	private let panel: DesktopTextEntryPanel
	private var hasPresented = false
	let fields: [NSTextField]

	init(
		title: String,
		detail: String = "",
		actionTitle: String,
		fields definitions: [Field],
		layout: Layout
	)
	{
		if case .single = layout
		{
			precondition(definitions.count == 1)
		}
		panel = DesktopTextEntryPanel(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: DesktopDialogShell.preferredWidth,
				height: 200
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		panel.title = title
		panel.isReleasedWhenClosed = false
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		fields = definitions.map
		{
			definition in
			let field = SettingsFormTextField(presentation: .dialog)
			field.stringValue = definition.value
			field.placeholderString = definition.placeholder
			field.setAccessibilityLabel(definition.accessibilityLabel)
			return field
		}
		super.init()
		let content = AppKitLayout.verticalStack(
			fields,
			spacing: 8
		)
		for field in fields
		{
			field.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
		}
		let cancel = DesktopStyledButton(
			title: "Cancel",
			presentation: .dialogCancel,
			size: .regular
		)
		cancel.target = self
		cancel.action = #selector(cancelPrompt)
		cancel.keyEquivalent = "\u{1b}"
		let confirm = DesktopStyledButton(
			title: actionTitle,
			presentation: .dialogPrimary,
			size: .regular
		)
		confirm.target = self
		confirm.action = #selector(confirmPrompt)
		confirm.keyEquivalent = "\r"
		let shell = DesktopDialogShell(
			title: title,
			message: detail.isEmpty ? nil : detail,
			content: content,
			actions: [cancel, confirm],
			style: .textEntry
		)
		shell.onClose =
		{
			[weak self] in self?.finish(false)
		}
		panel.onConfirm =
		{
			[weak self] in self?.finish(true)
		}
		panel.contentView = shell
		shell.resize(window: panel)
		panel.initialFirstResponder = fields.first
		panel.defaultButtonCell = confirm.cell as? NSButtonCell
	}

	func beginSheet(
		in window: NSWindow,
		completion: @escaping ([String]?) -> Void
	)
	{
		guard !hasPresented
		else
		{
			return
		}
		hasPresented = true
		panel.beginSheet(in: window)
		{
			[self] response in
			panel.orderOut(nil)
			completion(response == .OK ? fields.map(\.stringValue) : nil)
		}
	}

	@objc private func confirmPrompt()
	{
		finish(true)
	}

	@objc private func cancelPrompt()
	{
		finish(false)
	}

	private func finish(_ confirmed: Bool)
	{
		guard !panel.hasCompletedDecision, panel.sheetParent != nil
		else
		{
			return
		}
		if confirmed, !panel.makeFirstResponder(nil)
		{
			return
		}
		panel.finishDecision(confirmed)
	}
}

@MainActor
private final class DesktopTextEntryPanel: DesktopConfirmationPanel
{
	var onConfirm: (() -> Void)?

	override func sendEvent(_ event: NSEvent)
	{
		let isComposing = (firstResponder as? NSTextView)?.hasMarkedText() == true
		if sheetParent != nil, event.type == .keyDown,
			event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
			["\r", "\u{3}"].contains(event.charactersIgnoringModifiers ?? ""), !isComposing
		{
			onConfirm?()
			return
		}
		super.sendEvent(event)
	}
}
