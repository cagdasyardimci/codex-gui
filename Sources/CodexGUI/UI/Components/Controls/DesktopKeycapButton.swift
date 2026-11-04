import AppKit

/// A native shortcut action shares keycap typography, geometry and artwork.
@MainActor
final class DesktopKeycapButton: DesktopAttributedTitleButton
{
	private var widthConstraint: NSLayoutConstraint?
	private var heightConstraint: NSLayoutConstraint?

	init(
		title: String,
		target: AnyObject?,
		action: Selector?,
		configuration: @escaping @MainActor () -> TypographyConfiguration =
		{
			.current
		},
		center: NotificationCenter = .default
	)
	{
		super.init(frame: .zero)
		self.title = title
		self.target = target
		self.action = action
		isBordered = false
		let presentation = DesktopKeycapView.Presentation.fileEscape
		attributedTitle = NSAttributedString(
			string: title,
			attributes: [
				.font: presentation.font,
				.foregroundColor: presentation.foreground,
			]
		)
		widthConstraint = widthAnchor.constraint(equalToConstant: 0)
		heightConstraint = heightAnchor.constraint(equalToConstant: 0)
		widthConstraint?.isActive = true
		heightConstraint?.isActive = true
		setTypographyRole(
			presentation.role,
			configuration: configuration,
			center: center,
			onUpdate:
			{
				[weak self] in self?.refreshSize()
			}
		)
	}

	private func refreshSize()
	{
		let size = DesktopKeycapView.size(
			for: title,
			presentation: .fileEscape,
			font: font
		)
		widthConstraint?.constant = size.width
		heightConstraint?.constant = size.height
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
