import AppKit
import Mermaid
import SwiftMath

/// Native math and diagram adapters, with source-preserving text fallback on any failure.
@MainActor
enum ConversationRichBlockRenderer
{
	private static let maximumMathLength = 4_096
	private static let maximumDiagramLength = 8_192
	private static let maximumImageDimension: CGFloat = 4_096
	private static let maximumPixelCount: CGFloat = 8_000_000
	private static let imageScale: CGFloat = 2
	private static let mathFontSize: CGFloat = 20
	private static let imageCache = ConversationRichBlockImageCache()

	static func mathAttachment(
		latex: String,
		source: String
	) -> NSTextAttachment
	{
		var budget = ConversationRichBlockBudget()
		return mathAttachment(
			latex: latex,
			source: source,
			budget: &budget
		)
	}

	static func mathAttachment(
		latex: String,
		source: String,
		budget: inout ConversationRichBlockBudget
	) -> NSTextAttachment
	{
		guard let images = mathImages(
			latex: latex,
			budget: &budget
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
		var budget = ConversationRichBlockBudget()
		return diagramAttachment(
			code: code,
			source: source,
			budget: &budget
		)
	}

	static func diagramAttachment(
		code: String,
		source: String,
		budget: inout ConversationRichBlockBudget
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
		budget: inout ConversationRichBlockBudget
	) -> ConversationRichBlockImageCache.Images?
	{
		guard budget.beginBlock(), !latex.isEmpty, latex.utf16.count <= maximumMathLength,
				hasBoundedBraceNesting(latex)
		else
		{
			return nil
		}
		let lightColor = labelColor(dark: false)
		let darkColor = labelColor(dark: true)
		let key = ConversationRichBlockImageCache.Key(
			kind: .math,
			payload: Data(latex.utf8),
			parameters: [mathFontSize, imageScale] + colorComponents(lightColor)
				+ colorComponents(darkColor)
		)
		if let images = imageCache.images(for: key)
		{
			return budget.reservePixels(images.pixelCount) ? images : nil
		}
		guard let lightImage = mathImage(
			latex,
			textColor: lightColor
		),
			let darkImage = mathImage(
				latex,
				textColor: darkColor
			)
		else
		{
			return nil
		}
		let pixelCount = ConversationRichBlockBudget.estimatedPixels(for: lightImage.size)
			+ ConversationRichBlockBudget.estimatedPixels(for: darkImage.size)
		guard budget.reservePixels(pixelCount)
		else
		{
			return nil
		}
		guard let light = rasterizeMathImage(lightImage), let dark = rasterizeMathImage(darkImage)
		else
		{
			budget.releasePixels(pixelCount)
			return nil
		}
		let images = ConversationRichBlockImageCache.Images(
			light: light,
			dark: dark,
			lightSize: lightImage.size,
			darkSize: darkImage.size
		)
		imageCache.insert(
			images,
			for: key
		)
		return images
	}

	static func diagramImages(
		code: String,
		budget: inout ConversationRichBlockBudget
	) -> ConversationRichBlockImageCache.Images?
	{
		guard budget.beginBlock(), code.utf16.count <= maximumDiagramLength
		else
		{
			return nil
		}
		// Diagram rendering always uses the default/dark theme pair and Dagre layout.
		let key = ConversationRichBlockImageCache.Key(
			kind: .diagram,
			payload: Data(code.utf8),
			parameters: [imageScale]
		)
		if let images = imageCache.images(for: key)
		{
			return budget.reservePixels(images.pixelCount) ? images : nil
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
		let pixelCount = ConversationRichBlockBudget.estimatedPixels(for: lightScene.size)
			+ ConversationRichBlockBudget.estimatedPixels(for: darkScene.size)
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
		let images = ConversationRichBlockImageCache.Images(
			light: lightPixels,
			dark: darkPixels,
			lightSize: lightScene.size,
			darkSize: darkScene.size
		)
		imageCache.insert(
			images,
			for: key
		)
		return images
	}

	private static func sourceAttachment(_ source: String) -> NSTextAttachment
	{
		ConversationRichAttachment(
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
		guard !latex.isEmpty, latex.utf16.count <= maximumMathLength,
				hasBoundedBraceNesting(latex)
		else
		{
			return nil
		}
		var formula = MathImage(
			latex: latex,
			fontSize: mathFontSize,
			textColor: textColor,
			labelMode: .display,
			textAlignment: .center
		)
		let (error, image, _) = formula.asImage()
		guard error == nil, let image, hasBoundedImageSize(
			image.size,
			scale: imageScale
		)
		else
		{
			return nil
		}
		return image
	}

	private static func rasterizeMathImage(_ image: NSImage) -> CGImage?
	{
		guard let context = CGContext(
			data: nil,
			width: Int(ceil(image.size.width * imageScale)),
			height: Int(ceil(image.size.height * imageScale)),
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
