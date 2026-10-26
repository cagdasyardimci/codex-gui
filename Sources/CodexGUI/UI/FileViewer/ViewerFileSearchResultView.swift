import AppKit

@MainActor
final class ViewerFileSearchResultView: DesktopSearchResultContentView
{
	var filenameLabel: NSTextField
	{
		primaryLabel
	}
	var directoryLabel: NSTextField
	{
		detailLabel
	}

	init(relativePath: String)
	{
		super.init(presentation: .filename(path: relativePath))
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
