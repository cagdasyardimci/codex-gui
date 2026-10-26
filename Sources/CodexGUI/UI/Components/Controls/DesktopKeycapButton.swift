import AppKit

/// A native shortcut action shares keycap typography, geometry and artwork.
@MainActor
final class DesktopKeycapButton: DesktopAttributedTitleButton
{
	init(
		title: String,
		target: AnyObject?,
		action: Selector?
	)
	{
		super.init(frame: .zero)
		self.title = title
		self.target = target
		self.action = action
		isBordered = false
		let presentation = DesktopKeycapView.Presentation.fileEscape
		font = presentation.font
		attributedTitle = NSAttributedString(
			string: title,
			attributes: [
				.font: presentation.font,
				.foregroundColor: presentation.foreground,
			]
		)
		let size = DesktopKeycapView.size(
			for: title,
			presentation: presentation
		)
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: size.width),
			heightAnchor.constraint(equalToConstant: size.height),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func draw(_ dirtyRect: NSRect)
	{
		let presentation = DesktopKeycapView.Presentation.fileEscape
		DesktopKeycapDrawing.fill(
			bounds,
			color: presentation.background,
			cornerRadius: presentation.cornerRadius
		)
		DesktopTextRendering.withFontSmoothingDisabled
		{
			super.draw(dirtyRect)
		}
	}
}
