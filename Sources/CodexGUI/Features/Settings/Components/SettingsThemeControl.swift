import AppKit

/// Theme selection and its transfer actions share one settings accessory.
@MainActor
final class SettingsThemeControl: NSView
{
	private let picker: SettingsChoicePicker
	private var observation: TypographyObservation?
	init(
		picker: SettingsChoicePicker,
		onExport: @escaping () -> Void,
		onCopy: @escaping () -> Void
	)
	{
		self.picker = picker
		super.init(frame: .zero)
		observation = TypographyObservation(view: self)
		{
			[weak self] in self?.refreshPreview()
		}
		refreshPreview()
		picker.widthAnchor.constraint(equalToConstant: 176).isActive = true
		let export = DesktopActionButton(
			icon: .download,
			label: "Export theme",
			action: onExport
		)
		let copy = DesktopActionButton(
			icon: .copy,
			label: "Copy theme",
			action: onCopy
		)
		let stack = AppKitLayout.horizontalStack(
			[export, copy, picker],
			spacing: 12
		)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: 32),
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	private func refreshPreview()
	{
		let appearance = effectiveAppearance
		let font = AppKitFontResolver.font(
			TypographyTokens.Connections.body,
			appearance: appearance
		)
		picker.leadingIcon = NSImage(
			size: NSSize(
				width: 20,
				height: 20
			),
			flipped: false
		)
		{
			rect in
			appearance.performAsCurrentDrawingAppearance
			{
				AppKitColorTokens.border.setStroke()
				NSBezierPath(ovalIn: rect.insetBy(
					dx: 0.5,
					dy: 0.5
				)).stroke()
				let attributes: [NSAttributedString.Key: Any] = [
					.font: font,
					.foregroundColor: AppKitColorTokens.accent,
				]
				let text = "Aa" as NSString
				let size = text.size(withAttributes: attributes)
				text.draw(
					at: NSPoint(
						x: rect.midX - size.width / 2,
						y: rect.midY - size.height / 2
					),
					withAttributes: attributes
				)
			}
			return true
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
