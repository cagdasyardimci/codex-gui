import AppKit

/// Prepares bounded KaTeX artwork using the shared offline WebKit lifecycle.
@MainActor
enum MarkdownMathRenderer
{
	struct Formula: Hashable
	{
		let latex: String
		let fontSize: CGFloat
		let inline: Bool
	}

	private static let queue = MarkdownWebRendererQueue()
	private static var session: MarkdownWebRendererSession?
	private static let cache = MarkdownRichBlockImageCache()

	static func prepare(
		parsed: ParsedMarkdownContent,
		maximumPreparedPixels: Int = MarkdownMermaidRenderer.maximumPreparedPixels,
		typography: TypographyConfiguration = .current,
		colorTheme: ColorThemeConfiguration = ColorPreferences().configuration,
		filePreview: Bool = false,
		onDiagnostic: (@MainActor (MarkdownWebRendererSession.Diagnostic) -> Void)? = nil
	) async -> [Formula: MarkdownRichBlockImageCache.Images]
	{
		var formulas: [Formula] = []
		var seen = Set<Formula>()
		for run in parsed.runs
		{
			guard let block = run.style.richBlock, block.kind == .math, admits(block.payload)
			else
			{
				continue
			}
			let size = filePreview
				? FileMarkdownStyling.mathFontSize(
					style: run.style,
					inline: block.isInline,
					configuration: typography
				)
				: MarkdownAttributedStringRenderer.mathFontSize(
					style: run.style,
					configuration: typography
				)
			let formula = Formula(
				latex: block.payload,
				fontSize: size,
				inline: block.isInline
			)
			if seen.insert(formula).inserted
			{
				formulas.append(formula)
			}
			if formulas.count == 32
			{
				break
			}
		}
		guard !formulas.isEmpty, maximumPreparedPixels > 16_384, await queue.acquire()
		else
		{
			return [:]
		}
		defer
		{
			queue.release()
		}
		let renderer: MarkdownWebRendererSession
		if let session, session.isValid
		{
			renderer = session
		}
		else
		{
			renderer = MarkdownWebRendererSession(resource: .math)
			session = renderer
		}
		renderer.setDiagnostics(onDiagnostic)
		defer
		{
			renderer.setDiagnostics(nil)
			if !renderer.isValid
			{
				session = nil
			}
		}
		if !renderer.isLoaded, !(await renderer.load())
		{
			renderer.invalidate()
			return [:]
		}
		var remaining = maximumPreparedPixels
		var result: [Formula: MarkdownRichBlockImageCache.Images] = [:]
		for formula in formulas
		{
			guard !Task.isCancelled, renderer.isValid, remaining > 16_384
			else
			{
				break
			}
			let key = MarkdownRichBlockImageCache.Key(
				kind: .math,
				payload: Data(formula.latex.utf8),
				parameters: [formula.fontSize, formula.inline ? 1 : 0],
				typography: typography,
				colorTheme: colorTheme
			)
			if let cached = cache.images(for: key), cached.budgetPixelCost <= remaining
			{
				result[formula] = cached
				remaining -= cached.budgetPixelCost
				continue
			}
			let allowance = min(
				2_000_000,
				remaining / 2
			)
			let metrics: [String: Any] = ["fontSize": formula.fontSize]
			guard let light = await renderer.render(
				formula.latex,
				dark: false,
				maximumPixels: allowance,
				typography: metrics,
				colors: AppKitColorTokens.richContentColors(
					appearance: NSAppearance(named: .aqua)!,
					configuration: colorTheme
				),
				inline: formula.inline
			), !Task.isCancelled, let dark = await renderer.render(
				formula.latex,
				dark: true,
				maximumPixels: allowance,
				typography: metrics,
				colors: AppKitColorTokens.richContentColors(
					appearance: NSAppearance(named: .darkAqua)!,
					configuration: colorTheme
				),
				inline: formula.inline
			),
				let lightImage = MarkdownPDFImage(
					data: light.pdf,
					size: light.size
				),
				let darkImage = MarkdownPDFImage(
					data: dark.pdf,
					size: dark.size
				)
			else
			{
				continue
			}
			let images = MarkdownRichBlockImageCache.Images(
				light: lightImage,
				dark: darkImage,
				baselineDescent: light.baselineDescent
			)
			guard images.budgetPixelCost <= remaining
			else
			{
				continue
			}
			remaining -= images.budgetPixelCost
			result[formula] = images
			cache.insert(
				images,
				for: key
			)
		}
		return Task.isCancelled ? [:] : result
	}

	static func admits(_ source: String) -> Bool
	{
		guard !source.isEmpty, source.utf16.count <= 4096
		else
		{
			return false
		}
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
}
