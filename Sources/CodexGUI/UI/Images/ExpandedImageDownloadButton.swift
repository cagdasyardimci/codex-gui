import AppKit

/// Circular overlay actions use their full bounds rather than native bezel alignment insets.
@MainActor
final class ExpandedImageDownloadButton: NSButton
{
	override var alignmentRectInsets: NSEdgeInsets
	{
		NSEdgeInsets(
			top: 0,
			left: 0,
			bottom: 0,
			right: 0
		)
	}
}
