import AppKit

/// File search supplies query data; shared result content owns its presentation.
@MainActor
final class FileSearchContentResultView: DesktopSearchResultContentView
{
	var snippetLabel: NSTextField
	{
		primaryLabel
	}
	var locationLabel: NSTextField
	{
		detailLabel
	}

	init(
		result: FileViewerSearchResult,
		query: String
	)
	{
		super.init(presentation: .content(
			result: result,
			query: query
		))
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}

@MainActor
final class FileSearchResultSelectionRow: NSTableRowView
{
	override func drawSelection(in dirtyRect: NSRect)
	{
		guard isSelected
		else
		{
			return
		}
		AppKitColorTokens.fileSearchSelection.setFill()
		NSBezierPath(
			roundedRect: bounds,
			xRadius: ShapeTokens.FileSearch.selectionRadius,
			yRadius: ShapeTokens.FileSearch.selectionRadius
		).fill()
	}
}
