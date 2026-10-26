import AppKit

/// The transcript's review action owns its outlined geometry and native text drawing.
@MainActor
final class DesktopFileChangeReviewButton: DesktopLayerButton
{
	init()
	{
		super.init(frame: .zero)
		title = "View changes"
		bezelStyle = .inline
		isBordered = false
		wantsLayer = true
		layer?.cornerRadius = 10
		layer?.borderWidth = 1
		layerBorderColor = AppKitColorTokens.border
		contentTintColor = MarkdownAttributedStringRenderer.proseColor
		font = .systemFont(ofSize: 13)
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: 102),
			heightAnchor.constraint(equalToConstant: 28),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func draw(_ dirtyRect: NSRect)
	{
		MarkdownTextDrawing.withAntialiasing
		{
			super.draw(dirtyRect)
		}
	}
}
