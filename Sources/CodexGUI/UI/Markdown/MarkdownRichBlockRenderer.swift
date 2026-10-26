import AppKit
import SwiftMath

/// Native math and prepared diagram attachments, with source-preserving fallback.
@MainActor
enum MarkdownRichBlockRenderer
{
	private static let maximumMathLength = 4_096
	private static let maximumImageDimension: CGFloat = 4_096
	private static let maximumPixelCount: CGFloat = 8_000_000
	private static let imageScale = MarkdownRichBlockRasterSize.scale
	private static let mathFontSize: CGFloat = 20
	private static let imageCache = MarkdownRichBlockImageCache()

	static func mathAttachment(
		latex: String,
		source: String
	) -> NSTextAttachment
	{
		var budget = MarkdownRichBlockBudget()
		return mathAttachment(
			latex: latex,
			source: source,
			budget: &budget
		)
	}

	static func mathAttachment(
		latex: String,
		source: String,
		budget: inout MarkdownRichBlockBudget,
		fontSize: CGFloat? = nil
	) -> NSTextAttachment
	{
		guard let images = mathImages(
			latex: latex,
			budget: &budget,
			fontSize: fontSize ?? mathFontSize
		)
		else
		{
			return sourceAttachment(source)
		}
		return images.attachment(source: source)
	}

	static func diagramAttachment(
		source: String,
		budget: inout MarkdownRichBlockBudget,
		preparedImages: MarkdownRichBlockImageCache.Images? = nil
	) -> NSTextAttachment
	{
		guard budget.beginBlock(), let preparedImages,
				budget.reservePixels(preparedImages.budgetPixelCost)
		else
		{
			return sourceAttachment(source)
		}
		return preparedImages.attachment(
			source: source,
			isDiagram: true
		)
	}

	static func mathImages(
		latex: String,
		budget: inout MarkdownRichBlockBudget,
		fontSize: CGFloat = mathFontSize,
		inline: Bool = false
	) -> MarkdownRichBlockImageCache.Images?
	{
		guard budget.beginBlock(), !latex.isEmpty, latex.utf16.count <= maximumMathLength,
				hasBoundedBraceNesting(latex)
		else
		{
			return nil
		}
		let lightColor = labelColor(dark: false)
		let darkColor = labelColor(dark: true)
		let key = MarkdownRichBlockImageCache.Key(
			kind: .math,
			payload: Data(latex.utf8),
			parameters: [fontSize, imageScale, inline ? 1 : 0] + colorComponents(lightColor)
				+ colorComponents(darkColor)
		)
		if let images = imageCache.images(for: key)
		{
			return budget.reservePixels(images.budgetPixelCost) ? images : nil
		}
		guard let lightLayout = mathImageLayout(
			latex,
			textColor: lightColor,
			fontSize: fontSize,
			inline: inline
		),
			let darkLayout = mathImageLayout(
				latex,
				textColor: darkColor,
				fontSize: fontSize,
				inline: inline
			)
		else
		{
			return nil
		}
		let pixelCount = MarkdownRichBlockBudget.estimatedPixels(for: lightLayout.image.size)
			+ MarkdownRichBlockBudget.estimatedPixels(for: darkLayout.image.size)
		guard budget.reservePixels(pixelCount)
		else
		{
			return nil
		}
		guard let light = rasterizeMathImage(lightLayout.image),
				let dark = rasterizeMathImage(darkLayout.image)
		else
		{
			budget.releasePixels(pixelCount)
			return nil
		}
		let images = MarkdownRichBlockImageCache.Images(
			light: light,
			dark: dark,
			lightSize: lightLayout.image.size,
			darkSize: darkLayout.image.size,
			baselineDescent: lightLayout.descent
		)
		budget.releasePixels(pixelCount)
		guard budget.reservePixels(images.budgetPixelCost)
		else
		{
			return nil
		}
		imageCache.insert(
			images,
			for: key
		)
		return images
	}

	private static func sourceAttachment(_ source: String) -> NSTextAttachment
	{
		MarkdownRichAttachment(
			source: source,
			lightImage: nil,
			darkImage: nil
		)
	}

	static func mathImage(
		_ latex: String,
		dark: Bool
	) -> NSImage?
	{
		mathImage(
			latex,
			textColor: labelColor(dark: dark)
		)
	}

	private static func mathImage(
		_ latex: String,
		textColor: NSColor
	) -> NSImage?
	{
		mathImageLayout(
			latex,
			textColor: textColor,
			fontSize: mathFontSize,
			inline: false
		)?.image
	}

	private static func mathImageLayout(
		_ latex: String,
		textColor: NSColor,
		fontSize: CGFloat,
		inline: Bool
	) -> (image: NSImage, descent: CGFloat)?
	{
		guard !latex.isEmpty, latex.utf16.count <= maximumMathLength,
				hasBoundedBraceNesting(latex)
		else
		{
			return nil
		}
		var formula = MathImage(
			latex: latex,
			fontSize: fontSize,
			textColor: textColor,
			labelMode: inline ? .text : .display,
			textAlignment: .center
		)
		let (error, image, layout) = formula.asImage()
		guard error == nil, let image, let layout, hasBoundedImageSize(
			image.size,
			scale: imageScale
		)
		else
		{
			return nil
		}
		let contentHeight = max(
			layout.ascent + layout.descent,
			fontSize / 2
		)
		return (image, layout.descent + (image.size.height - contentHeight) / 2)
	}

	private static func rasterizeMathImage(_ image: NSImage) -> CGImage?
	{
		guard let raster = MarkdownRichBlockRasterSize(size: image.size),
				let context = CGContext(
				data: nil,
				width: raster.width,
				height: raster.height,
				bitsPerComponent: 8,
				bytesPerRow: 0,
				space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
				)
		else
		{
			return nil
		}
		context.scaleBy(
			x: imageScale,
			y: imageScale
		)
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		NSGraphicsContext.current = NSGraphicsContext(
			cgContext: context,
			flipped: false
		)
		image.draw(in: NSRect(
			origin: .zero,
			size: image.size
		))
		return context.makeImage()
	}

	private static func colorComponents(_ color: NSColor) -> [CGFloat]
	{
		let rgb = color.usingColorSpace(.deviceRGB) ?? .black
		return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
	}

	private static func labelColor(dark: Bool) -> NSColor
	{
		let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
		var color = dark ? NSColor.white : NSColor.black
		appearance?.performAsCurrentDrawingAppearance
		{
			color = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? color
		}
		return color
	}

	private static func hasBoundedBraceNesting(_ source: String) -> Bool
	{
		var depth = 0
		var escaped = false
		for character in source
		{
			if escaped
			{
				escaped = false
				continue
			}
			if character == "\\"
			{
				escaped = true
			}
			else if character == "{"
			{
				depth += 1
				if depth > 32
				{
					return false
				}
			}
			else if character == "}"
			{
				depth -= 1
				if depth < 0
				{
					return false
				}
			}
		}
		return depth == 0
	}

	private static func hasBoundedImageSize(
		_ size: NSSize,
		scale: CGFloat
	) -> Bool
	{
		size.width.isFinite && size.height.isFinite
			&& size.width > 0 && size.height > 0
			&& size.width <= maximumImageDimension && size.height <= maximumImageDimension
			&& size.width * size.height * scale * scale <= maximumPixelCount
	}

}
