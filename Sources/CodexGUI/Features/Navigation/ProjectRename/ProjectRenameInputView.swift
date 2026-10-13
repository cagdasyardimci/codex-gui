import AppKit

@MainActor
final class ProjectRenameInputView: NSView, NSTextFieldDelegate
{
	let field = NSTextField(string: "")
	private var isEditing = false
	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		field.isBordered = false
		field.drawsBackground = false
		field.focusRingType = .none
		field.font = .systemFont(ofSize: 14)
		field.textColor = .labelColor
		field.delegate = self
		field.translatesAutoresizingMaskIntoConstraints = false
		addSubview(field)
		NSLayoutConstraint.activate([
			field.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 10
			),
			field.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -10
			),
			field.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}
	required init?(coder: NSCoder)
	{
		nil
	}
	func controlTextDidBeginEditing(_ obj: Notification)
	{
		isEditing = true; needsDisplay = true
	}
	func controlTextDidEndEditing(_ obj: Notification)
	{
		isEditing = false; needsDisplay = true
	}
	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}
	override func draw(_ dirtyRect: NSRect)
	{
		let outline = NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: 0.5,
				dy: 0.5
			),
			xRadius: 8,
			yRadius: 8
		)
		AppKitColorTokens.elevated.setFill()
		outline.fill()
		let editorHasFocus = field.currentEditor().map
		{
			window?.firstResponder === $0
		} ?? false
		(isEditing || editorHasFocus ? NSColor.controlAccentColor : AppKitColorTokens.border)
			.setStroke()
		outline.lineWidth = 1
		outline.stroke()
	}
}
