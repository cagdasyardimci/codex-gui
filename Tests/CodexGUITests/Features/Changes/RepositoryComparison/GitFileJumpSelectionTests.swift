import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct GitFileJumpSelectionTests
{
	@Test func filteringResetsSelectionAndEmptyResultsCannotChoose() throws
	{
		_ = NSApplication.shared
		let paths = [
			"Sources/One.swift",
			"Sources/Two.swift",
			"Tests/Only.swift",
		]
		let files = paths.map
		{
			path in
			GitComparisonFile(
				oldPath: path,
				newPath: path,
				kind: .modified,
				additions: 1,
				deletions: 1,
				isBinary: false,
				patch: "",
				hunks: []
			)
		}
		let controller = GitFileJumpPopoverController(index: GitFileJumpIndex(files: files))
		let field = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSSearchField
		}.first)
		#expect(field.action == nil)
		var selected: [String] = []
		controller.onSelect =
		{
			selected.append($0)
		}
		#expect(controller.control(
			field,
			textView: NSTextView(),
			doCommandBy: #selector(NSResponder.moveDown(_:))
		))
		setQuery(
			"Only",
			in: field,
			controller: controller
		)
		#expect(selected.isEmpty)
		#expect(controller.control(
			field,
			textView: NSTextView(),
			doCommandBy: #selector(NSResponder.insertNewline(_:))
		))
		#expect(selected == ["Tests/Only.swift"])
		setQuery(
			"absent",
			in: field,
			controller: controller
		)
		#expect(controller.control(
			field,
			textView: NSTextView(),
			doCommandBy: #selector(NSResponder.moveDown(_:))
		))
		#expect(controller.control(
			field,
			textView: NSTextView(),
			doCommandBy: #selector(NSResponder.insertNewline(_:))
		))
		#expect(selected == ["Tests/Only.swift"])
	}

	private func setQuery(
		_ query: String,
		in field: NSSearchField,
		controller: GitFileJumpPopoverController
	)
	{
		field.stringValue = query
		controller.controlTextDidChange(Notification(
			name: NSControl.textDidChangeNotification,
			object: field
		))
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}
}
