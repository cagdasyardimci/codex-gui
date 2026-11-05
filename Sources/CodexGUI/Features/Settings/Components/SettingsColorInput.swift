import AppKit

/// A color swatch and editable hexadecimal value share one appearance control.
@MainActor
final class SettingsColorInput: NSView
{
	private let field: NSTextField
	private var colorObservation: ThemeColorObservation?

	init(
		field: NSTextField,
		well: NSColorWell
	)
	{
		self.field = field
		super.init(frame: .zero)
		field.alignment = .right
		field.setTypographyRole(TypographyTokens.Connections.body)
		field.isBordered = false
		field.isBezeled = false
		field.drawsBackground = false
		well.colorWellStyle = .minimal
		colorObservation = ThemeColorObservation
		{
			[weak self] in self?.refreshColors()
		}
		for name in [
			NSControl.textDidBeginEditingNotification,
			NSControl.textDidEndEditingNotification
		]
		{
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(refreshColors),
				name: name,
				object: field
			)
		}
		refreshColors()
		for view in [well, field]
		{
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: 96),
			heightAnchor.constraint(equalToConstant: 28),
			well.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 8
			),
			well.centerYAnchor.constraint(equalTo: centerYAnchor),
			well.widthAnchor.constraint(equalToConstant: 14),
			well.heightAnchor.constraint(equalToConstant: 14),
			field.leadingAnchor.constraint(
				equalTo: well.trailingAnchor,
				constant: 6
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

	override func draw(_ dirtyRect: NSRect)
	{
		let path = AppKitShapePath.roundedRect(
			bounds.insetBy(
				dx: 0.5,
				dy: 0.5
			),
			radius: bounds.height / 2,
			curve: ShapeTokens.Connections.curve
		)
		AppKitColorTokens.settingsCard.setFill()
		path.fill()
		(field.currentEditor() == nil ? AppKitColorTokens.settingsSelectorEdge
			: AppKitColorTokens.settingsFieldFocus).setStroke()
		path.stroke()
	}

	@objc private func refreshColors()
	{
		field.textColor = AppKitColorTokens.settingsPrimaryText
		needsDisplay = true
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshColors()
	}
}
