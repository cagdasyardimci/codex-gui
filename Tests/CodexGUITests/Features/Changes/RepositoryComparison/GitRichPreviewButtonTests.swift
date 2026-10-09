import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitRichPreviewButtonTests
{
	@Test func eyeButtonOnlyAppearsForRichFormatsAndRoutesItsOwnFile()
	{
		_ = NSApplication.shared
		for path in ["README.MD",
						"image.png",
						"diagram.svg",
						"document.pdf",
						"code.swift",
						"settings.json",
						"plain.txt",
						"index.html"]
		{
			var previewed = false
			let patch = "index " + String(
				repeating: "a",
				count: 40
			) + ".."
				+ String(
					repeating: "b",
					count: 40
				) + " 100644\n"
			let section = GitDiffFileSectionView(
				file: GitComparisonFile(
					oldPath: path,
					newPath: path,
					kind: .modified,
					additions: 1,
					deletions: 1,
					isBinary: false,
					patch: patch,
					hunks: []
				),
				rows: nil,
				isCollapsed: true,
				layoutPreference: .unified,
				wrapsCode: false,
				onToggleFileDiff:
				{
					_ in
				},
				onExpandGap:
				{
					_ in
				},
				onRichPreview:
				{
					_ in previewed = true
				}
			)
			let preview = buttons(section).first
			{
				$0.toolTip ==
					"Rich preview of the compared file version"
			}
			let supported = ["README.MD", "image.png", "diagram.svg", "document.pdf"].contains(path)
			#expect((preview != nil) == supported)
			preview?.performClick(nil)
			#expect(previewed == supported)
		}
	}

	private func buttons(_ view: NSView) -> [NSButton]
	{
		(view as? NSButton).map
		{
			[$0]
		} ?? view.subviews.flatMap
		{
			buttons($0)
		}
	}
}
