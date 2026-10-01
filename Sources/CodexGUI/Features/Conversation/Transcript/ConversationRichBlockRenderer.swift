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
		guard budget.beginBlock(),
				let lightImage = mathImage(
				latex,
				dark: false
				),
				let darkImage = mathImage(
				latex,
				dark: true
				),
				budget.reservePixels(
				ConversationRichBlockBudget.estimatedPixels(for: lightImage.size)
					+ ConversationRichBlockBudget.estimatedPixels(for: darkImage.size)
				)
		else
		{
			return sourceAttachment(source)
		}
		return ConversationRichAttachment(
			source: source,
			lightImage: lightImage,
			darkImage: darkImage
		)
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
		guard budget.beginBlock(),
				let lightScene = diagramScene(
				code,
				dark: false
				),
				let darkScene = diagramScene(
				code,
				dark: true
				)
		else
		{
			return sourceAttachment(source)
		}
		let pixelCount = ConversationRichBlockBudget.estimatedPixels(for: lightScene.size)
			+ ConversationRichBlockBudget.estimatedPixels(for: darkScene.size)
		guard budget.reservePixels(pixelCount)
		else
		{
			return sourceAttachment(source)
		}
		guard let lightPixels = lightScene.cgImage(scale: 2),
				let darkPixels = darkScene.cgImage(scale: 2)
		else
		{
			budget.releasePixels(pixelCount)
			return sourceAttachment(source)
		}
		return ConversationRichAttachment(
			source: source,
			lightImage: NSImage(
				cgImage: lightPixels,
				size: lightScene.size
			),
			darkImage: NSImage(
				cgImage: darkPixels,
				size: darkScene.size
			)
		)
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
		guard !latex.isEmpty, latex.utf16.count <= maximumMathLength,
				hasBoundedBraceNesting(latex)
		else
		{
			return nil
		}
		var formula = MathImage(
			latex: latex,
			fontSize: 20,
			textColor: labelColor(dark: dark),
			labelMode: .display,
			textAlignment: .center
		)
		let (error, image, _) = formula.asImage()
		guard error == nil, let image, hasBoundedImageSize(
			image.size,
			scale: 2
		)
		else
		{
			return nil
		}
		return image
	}

	static func diagramImage(
		_ source: String,
		dark: Bool
	) -> NSImage?
	{
		guard let scene = diagramScene(
			source,
			dark: dark
		), let pixels = scene.cgImage(scale: 2)
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
				scale: 2
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
