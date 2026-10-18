import AppKit

@MainActor
final class FileViewerEmptyStateView: ViewerStatusView
{
	init()
	{
		super.init(
			icon: FileViewerIcons.image(
				.navigator,
				size: 32
			),
			title: "Open file",
			message: "Select a file from the workspace tree"
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
