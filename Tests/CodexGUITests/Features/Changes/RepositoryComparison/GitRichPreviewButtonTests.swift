import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitRichPreviewButtonTests
{
	@Test func eyeButtonOnlyAppearsForRichFormatsAndRoutesItsOwnFile() throws
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
			var previewed: [NSButton] = []
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
					previewed.append($0)
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
			#expect(previewed.count == (supported ? 1 : 0))
			if let preview
			{
				let sender = try #require(previewed.first)
				#expect(sender === preview)
				#expect(sender.identifier?.rawValue == path)
			}
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
