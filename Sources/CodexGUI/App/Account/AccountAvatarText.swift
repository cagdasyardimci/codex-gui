import AppKit
import CoreText

/// Centers the visible initials, independently of native control title insets and baselines.
@MainActor
enum AccountAvatarText
{
	private static func draw(
		_ text: NSAttributedString,
		in view: NSView
	)
	{
		guard let context = NSGraphicsContext.current?.cgContext
		else
		{
			return
		}
		let line = CTLineCreateWithAttributedString(text)
		let glyphBounds = CTLineGetBoundsWithOptions(
			line,
			.useGlyphPathBounds
		)
		context.saveGState()
		context.translateBy(
			x: view.bounds.midX,
			y: view.bounds.midY
		)
		if view.isFlipped
		{
			context.scaleBy(
				x: 1,
				y: -1
			)
		}
		context.textMatrix = .identity
		context.textPosition = NSPoint(
			x: -glyphBounds.midX,
			y: -glyphBounds.midY
		)
		CTLineDraw(
			line,
			context
		)
		context.restoreGState()
	}

	final class Button: NSButton
	{
		override func draw(_ dirtyRect: NSRect)
		{
			if imagePosition == .noImage, !title.isEmpty
			{
				AccountAvatarText.draw(
					attributedTitle,
					in: self
				)
			}
			else
			{
				super.draw(dirtyRect)
			}
		}
	}

	final class Label: NSTextField
	{
		override func draw(_ dirtyRect: NSRect)
		{
			AccountAvatarText.draw(
				NSAttributedString(
					string: stringValue,
					attributes: [
						.font: font ?? NSFont.systemFont(ofSize: 7),
						.foregroundColor: textColor ?? NSColor.white,
					]
				),
				in: self
			)
		}
	}
}
