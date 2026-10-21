import AppKit
import Mermaid
import SwiftMath

/// Native math and diagram adapters, with source-preserving text fallback on any failure.
@MainActor
enum MarkdownRichBlockRenderer
{
	private static let maximumMathLength = 4_096
	private static let maximumDiagramLength = 8_192
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
		code: String,
		source: String
	) -> NSTextAttachment
	{
		var budget = MarkdownRichBlockBudget()
		return diagramAttachment(
			code: code,
			source: source,
			budget: &budget
		)
	}

	static func diagramAttachment(
		code: String,
		source: String,
		budget: inout MarkdownRichBlockBudget
	) -> NSTextAttachment
	{
		guard let images = diagramImages(
			code: code,
			budget: &budget
		)
		else
		{
			return sourceAttachment(source)
		}
		return images.attachment(source: source)
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

	static func diagramImages(
		code: String,
		budget: inout MarkdownRichBlockBudget
	) -> MarkdownRichBlockImageCache.Images?
	{
		guard budget.beginBlock(), code.utf16.count <= maximumDiagramLength
		else
		{
			return nil
		}
		// Diagram rendering always uses the default/dark theme pair and Dagre layout.
		let key = MarkdownRichBlockImageCache.Key(
			kind: .diagram,
			payload: Data(code.utf8),
			parameters: [imageScale]
		)
		if let images = imageCache.images(for: key)
		{
			return budget.reservePixels(images.budgetPixelCost) ? images : nil
		}
		guard let lightScene = diagramScene(
			code,
			dark: false
		),
			let darkScene = diagramScene(
				code,
				dark: true
			)
		else
		{
			return nil
		}
		let pixelCount = MarkdownRichBlockBudget.estimatedPixels(for: lightScene.size)
			+ MarkdownRichBlockBudget.estimatedPixels(for: darkScene.size)
		guard budget.reservePixels(pixelCount)
		else
		{
			return nil
		}
		guard let lightPixels = lightScene.cgImage(scale: imageScale),
				let darkPixels = darkScene.cgImage(scale: imageScale)
		else
		{
			budget.releasePixels(pixelCount)
			return nil
		}
		let images = MarkdownRichBlockImageCache.Images(
			light: lightPixels,
			dark: darkPixels,
			lightSize: lightScene.size,
			darkSize: darkScene.size
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

	static func diagramImage(
		_ source: String,
		dark: Bool
	) -> NSImage?
	{
		guard let scene = diagramScene(
			source,
			dark: dark
		), let pixels = scene.cgImage(scale: imageScale)
		else
		{
			return nil
		}
		return NSImage(
			cgImage: pixels,
			size: scene.size
		)
	}

	private static func diagramScene(
		_ source: String,
		dark: Bool
	) -> MermaidScene?
	{
		guard admitsFlowchart(source),
				let scene = try? Mermaid.render(
				source,
				theme: dark ? .dark : .default,
				layout: .dagre
				), hasBoundedImageSize(
				scene.size,
				scale: imageScale
				)
		else
		{
			return nil
		}
		return scene
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

	private static func admitsFlowchart(_ source: String) -> Bool
	{
		guard source.utf16.count <= maximumDiagramLength,
				!source.unicodeScalars.contains(where:
				{
					scalar in
					CharacterSet.newlines.contains(scalar) && scalar.value != 10 && scalar
						.value != 13
				})
		else
		{
			return false
		}
		// Match upstream's CR/LF normalization; other newline scalars could drop whole edges.
		let normalizedSource = source.replacingOccurrences(
			of: "\r\n",
			with: "\n"
		)
		.replacingOccurrences(
			of: "\r",
			with: "\n"
		)
		let lines = normalizedSource.components(separatedBy: "\n")
		guard lines.count <= 64
		else
		{
			return false
		}
		guard !lines.contains(where:
			{
				$0.trimmingCharacters(in: .whitespaces).hasPrefix("%%{")
			})
		else
		{
			return false
		}
		let trimmedLines = lines.map
		{
			$0.trimmingCharacters(in: .whitespaces)
		}
		let statements = trimmedLines.filter
		{
			!$0.isEmpty && !$0.hasPrefix("%%")
		}
		guard let header = statements.first,
				header.range(
				of: #"\A(?:flowchart|graph) (?:LR|RL|TD|TB|BT)\z"#,
				options: .regularExpression
				) != nil, statements.count > 1
		else
		{
			return false
		}

		// Admission is deliberately narrow: upstream tolerates trailing unsupported syntax.
		// Its parser and Dagre own all node interpretation, edge semantics and layout.
		let reserved = "subgraph|end|direction|classdef|class|style|linkstyle|click|"
			+ "acctitle|accdescr|default|interpolate"
		let node = "(?!(?i:" + reserved + ")\\b)"
			+ #"[A-Za-z_][A-Za-z0-9_]*(?:\[[^\[\]\r\n;<>%]{1,200}\])?"#
		let statement = "\\A" + node + "(?:\\s*-->\\s*" + node + ")*;?\\z"
		var edgeCount = 0
		for line in statements.dropFirst()
		{
			guard !line.contains(":::"), !line.contains("@{"), !line.contains("&"),
					!line.contains("\""), !line.contains("'"), !line.contains("`"),
					!line.contains("\\"),
					line.range(
					of: statement,
					options: .regularExpression
					) != nil
			else
			{
				return false
			}
			edgeCount += line.components(separatedBy: "-->").count - 1
			if edgeCount > 64
			{
				return false
			}
		}
		return true
	}
}
