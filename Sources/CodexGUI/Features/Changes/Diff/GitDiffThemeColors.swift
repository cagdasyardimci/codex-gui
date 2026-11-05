import AppKit

/// Diff views consume the shared semantic palette; native color mixing belongs to Design.
@MainActor
enum GitDiffThemeColors
{
	static var added: NSColor
	{
		AppKitColorTokens.diffAdded
	}
	static var removed: NSColor
	{
		AppKitColorTokens.diffRemoved
	}
	static var addedContent: NSColor
	{
		AppKitColorTokens.diffAddedContent
	}
	static var removedContent: NSColor
	{
		AppKitColorTokens.diffRemovedContent
	}
	static var addedGutter: NSColor
	{
		AppKitColorTokens.diffAddedGutter
	}
	static var removedGutter: NSColor
	{
		AppKitColorTokens.diffRemovedGutter
	}

	static func selected(
		_ color: NSColor,
		gutter: Bool
	) -> NSColor
	{
		AppKitColorTokens.diffSelection(
			over: color,
			gutter: gutter
		)
	}

	static func labMix(
		_ first: NSColor,
		_ second: NSColor,
		amount: Double
	) -> NSColor
	{
		AppKitColorResolution.labMix(
			first,
			second,
			amount: amount
		)
	}
}
