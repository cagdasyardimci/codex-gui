import AppKit

/// Named shadow presets in AppKit points. Native colors retain main-actor ownership.
@MainActor
enum ShadowTokens
{
	@MainActor
	struct Style
	{
		let color: NSColor
		let offsetY: CGFloat
		let blur: CGFloat
		let spread: CGFloat
		let inset: Bool

		init(
			color: NSColor,
			offsetY: CGFloat,
			blur: CGFloat,
			spread: CGFloat = 0,
			inset: Bool = false
		)
		{
			self.color = color
			self.offsetY = offsetY
			self.blur = blur
			self.spread = spread
			self.inset = inset
		}
	}

	static let fileViewerControl = Style(
		color: .black.withAlphaComponent(0.045),
		offsetY: 2,
		blur: 8
	)
	static let selectedTab = Style(
		color: .black.withAlphaComponent(0.08),
		offsetY: 1,
		blur: 2,
		spread: -1
	)
	static let popover = [Style(
		color: .black.withAlphaComponent(0.12),
		offsetY: 8,
		blur: 16,
		spread: -4
	)]
	static let effortThumb = Style(
		color: .black.withAlphaComponent(0.1),
		offsetY: 0,
		blur: 2
	)
	static let summary = [
		Style(
			color: .black.withAlphaComponent(0.04),
			offsetY: 3,
			blur: 7.5
		),
		Style(
			color: .black.withAlphaComponent(0.05),
			offsetY: 0,
			blur: 20
		),
	]
	static let composer = [
		Style(
			color: AppKitColorResolution.color(
				light: 0,
				dark: 0,
				lightAlpha: 0.04,
				darkAlpha: 0
			),
			offsetY: 2,
			blur: 8
		),
		Style(
			color: AppKitColorResolution.color(
				light: 0,
				dark: 0,
				lightAlpha: 0.024,
				darkAlpha: 0
			),
			offsetY: 4,
			blur: 80,
			spread: 8
		),
		Style(
			color: AppKitColorTokens.composerEdge,
			offsetY: 0,
			blur: 0,
			spread: 1
		),
		Style(
			color: AppKitColorTokens.composerInsetEdge,
			offsetY: 0,
			blur: 1,
			inset: true
		),
	]

}
