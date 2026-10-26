import AppKit

/// A fixed-size inline icon that updates after its visible host finishes loading the site icon.
@MainActor
final class WebLinkFaviconAttachment: NSTextAttachment
{
	private static let iconSide: CGFloat = 14
	private static let attachmentWidth: CGFloat = 18
	let url: URL
	private(set) var requested = false

	init(url: URL)
	{
		self.url = url
		super.init(
			data: nil,
			ofType: nil
		)
		image = Self.fallbackImage()
		bounds = NSRect(
			x: 0,
			y: -1.5,
			width: Self.attachmentWidth,
			height: Self.iconSide
		)
	}

	@available(
		*,
		unavailable
	)
	required init?(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}

	static func load(
		in text: NSAttributedString,
		invalidate view: NSView
	)
	{
		guard view.window != nil, text.length > 0
		else
		{
			return
		}
		text.enumerateAttribute(
			.attachment,
			in: NSRange(
				location: 0,
				length: text.length
			),
			options: []
		)
		{
			value, _, _ in
			guard let attachment = value as? WebLinkFaviconAttachment,
					!attachment.requested
			else
			{
				return
			}
			attachment.requested = true
			let url = attachment.url
			Task
			{
				[weak attachment, weak view] in
				let data = await WebLinkFaviconLoader.shared.favicon(for: url)
				guard let attachment, let data,
						let favicon = NSImage(data: data), !favicon.representations.isEmpty
				else
				{
					return
				}
				attachment.image = Self.fit(favicon)
				view?.needsDisplay = true
			}
		}
	}

	private static func fallbackImage() -> NSImage
	{
		let icon = DesktopIcons.image(
			.globe,
			size: iconSide
		)
		let color = MarkdownAttributedStringRenderer.linkColor
		return NSImage(
			size: NSSize(
				width: attachmentWidth,
				height: iconSide
			),
			flipped: false
		)
		{
			_ in
			let iconRect = NSRect(
				x: 0,
				y: 0,
				width: iconSide,
				height: iconSide
			)
			icon.draw(in: iconRect)
			color.setFill()
			iconRect.fill(using: .sourceAtop)
			return true
		}
	}

	static func fit(_ source: NSImage) -> NSImage
	{
		let tintInDarkAppearance = isDarkMonochrome(source)
		let size = source.size
		let scale = min(
			iconSide / max(
				size.width,
				1
			),
			iconSide / max(
				size.height,
				1
			)
		)
		let fitted = NSSize(
			width: size.width * scale,
			height: size.height * scale
		)
		return NSImage(
			size: NSSize(
				width: attachmentWidth,
				height: iconSide
			),
			flipped: false
		)
		{
			_ in
			let iconRect = NSRect(
				x: (iconSide - fitted.width) / 2,
				y: (iconSide - fitted.height) / 2,
				width: fitted.width,
				height: fitted.height
			)
			source.draw(in: iconRect)
			if tintInDarkAppearance,
				NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			{
				NSColor.white.setFill()
				iconRect.fill(using: .sourceAtop)
			}
			return true
		}
	}

	private static func isDarkMonochrome(_ source: NSImage) -> Bool
	{
		let side = 32
		guard let bitmap = NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: side,
			pixelsHigh: side,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		), let context = NSGraphicsContext(bitmapImageRep: bitmap)
		else
		{
			return false
		}
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = context
		NSColor.clear.setFill()
		NSRect(
			x: 0,
			y: 0,
			width: side,
			height: side
		).fill()
		source.draw(in: NSRect(
			x: 0,
			y: 0,
			width: side,
			height: side
		))
		NSGraphicsContext.restoreGraphicsState()
		var visible = 0
		var dark = 0
		for y in 0 ..< side
		{
			for x in 0 ..< side
			{
				guard let color = bitmap.colorAt(
					x: x,
					y: y
				)?.usingColorSpace(.deviceRGB),
					color.alphaComponent >= 0.25
				else
				{
					continue
				}
				visible += 1
				let red = color.redComponent
				let green = color.greenComponent
				let blue = color.blueComponent
				let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
				let saturation = max(
					red,
					green,
					blue
				) - min(
					red,
					green,
					blue
				)
				if luminance < 0.25 && saturation < 0.2
				{
					dark += 1
				}
			}
		}
		return visible >= 16 && Double(dark) / Double(visible) >= 0.8
	}
}
