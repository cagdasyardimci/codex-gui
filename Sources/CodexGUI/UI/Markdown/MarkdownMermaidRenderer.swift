import AppKit
import WebKit

/// Prepares offline Mermaid SVGs for Markdown without blocking AppKit's event loop.
@MainActor
enum MarkdownMermaidRenderer
{
	typealias Diagnostic = MarkdownWebRendererSession.Diagnostic

	static let maximumPreparedPixels = 16_000_000
	static let transcriptMaximumPreparedPixels = 2_000_000
	private static let maximumDiagramPixels = 2_000_000
	private static let queue = MarkdownWebRendererQueue()
	private static var retainedSession: MarkdownWebRendererSession?
	private static let imageCache = MarkdownRichBlockImageCache()

	static func prepare(
		parsed: ParsedMarkdownContent,
		maximumPreparedPixels: Int = MarkdownMermaidRenderer.maximumPreparedPixels,
		typography: TypographyConfiguration = .current,
		colorTheme: ColorThemeConfiguration = ColorPreferences().configuration,
		onDiagnostic: (@MainActor (Diagnostic) -> Void)? = nil
	) async
		-> [Data: MarkdownRichBlockImageCache.Images]
	{
		var sources: [String] = []
		var seen = Set<Data>()
		for run in parsed.runs
		{
			guard let block = run.style.richBlock, block.kind == .diagram,
					admits(block.payload), seen.insert(Data(block.payload.utf8)).inserted
			else
			{
				continue
			}
			sources.append(block.payload)
			if sources.count == 32
			{
				break
			}
		}
		guard !sources.isEmpty
		else
		{
			return [:]
		}
		guard maximumPreparedPixels > 16_384
		else
		{
			return [:]
		}
		guard await queue.acquire()
		else
		{
			onDiagnostic?(Diagnostic(
				phase: "admission",
				reason: Task.isCancelled ? "cancelled" : "queue full",
				elapsed: .zero,
				errorDomain: nil,
				errorCode: nil
			))
			return [:]
		}
		defer
		{
			queue.release()
		}
		let session: MarkdownWebRendererSession
		if let existing = retainedSession, existing.isValid
		{
			session = existing
		}
		else
		{
			session = MarkdownWebRendererSession(
				resource: .mermaid,
				onDiagnostic: onDiagnostic
			)
		}
		retainedSession = session
		session.setDiagnostics(onDiagnostic)
		defer
		{
			session.setDiagnostics(nil)
			if !session.isValid
			{
				retainedSession = nil
			}
		}
		if !session.isLoaded
		{
			guard await session.load()
			else
			{
				session.invalidate()
				return [:]
			}
		}
		// Both variants are prepared together, independently of the window's forced mode.
		let variantColors = ColorThemeConfiguration(
			light: colorTheme.light,
			dark: colorTheme.dark
		)
		let lightTypography = AppKitFontResolver.diagramTypography(
			appearance: NSAppearance(named: .aqua)!,
			configuration: typography,
			colorConfiguration: variantColors
		)
		let darkTypography = AppKitFontResolver.diagramTypography(
			appearance: NSAppearance(named: .darkAqua)!,
			configuration: typography,
			colorConfiguration: variantColors
		)
		var images: [Data: MarkdownRichBlockImageCache.Images] = [:]
		// Leave the shared attachment budget room for math and local images.
		let reserve = MarkdownRichBlockBudget.mathPreparationPixels(total: maximumPreparedPixels)
		var remainingPixels = max(
			0,
			maximumPreparedPixels - reserve
		)
		for (index, source) in sources.enumerated()
		{
			guard !Task.isCancelled, session.isValid, remainingPixels > 16_384
			else
			{
				break
			}
			let allowance = min(
				maximumDiagramPixels,
				remainingPixels / ((sources.count - index) * 2)
			)
			let key = MarkdownRichBlockImageCache.Key(
				kind: .diagram,
				payload: Data(source.utf8),
				parameters: [CGFloat(allowance)],
				typography: typography,
				colorTheme: colorTheme
			)
			if let cached = imageCache.images(for: key),
				cached.budgetPixelCost <= remainingPixels
			{
				remainingPixels -= cached.budgetPixelCost
				images[key.payload] = cached
				continue
			}
			guard let light = await session.render(
				source,
				dark: false,
				maximumPixels: allowance,
				typography: lightTypography,
				colors: AppKitColorTokens.richContentColors(
					appearance: NSAppearance(named: .aqua)!,
					configuration: colorTheme
				)
			), !Task.isCancelled, let dark = await session.render(
				source,
				dark: true,
				maximumPixels: allowance,
				typography: darkTypography,
				colors: AppKitColorTokens.richContentColors(
					appearance: NSAppearance(named: .darkAqua)!,
					configuration: colorTheme
				)
			)
			else
			{
				continue
			}
			guard let lightImage = MarkdownSVGImage(
				data: light.svg,
				size: light.size,
				pdfData: light.pdf
			),
				let darkImage = MarkdownSVGImage(
					data: dark.svg,
					size: dark.size,
					pdfData: dark.pdf
				)
			else
			{
				continue
			}
			let pair = MarkdownRichBlockImageCache.Images(
				light: lightImage,
				dark: darkImage
			)
			guard pair.budgetPixelCost <= remainingPixels
			else
			{
				continue
			}
			remainingPixels -= pair.budgetPixelCost
			images[key.payload] = pair
			imageCache.insert(
				pair,
				for: key
			)
		}
		return Task.isCancelled ? [:] : images
	}

	static func admits(_ source: String) -> Bool
	{
		!source.isEmpty && source.utf16.count <= 8_192
			&& source.components(separatedBy: .newlines).count <= 256
			&& !source.unicodeScalars.contains
			{
				CharacterSet.newlines.contains($0) && $0.value != 10 && $0.value != 13
			}
	}

}
