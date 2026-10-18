import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct ViewerFileSearchResultTests
{
	@Test func filenameAndDirectoryRemainAvailableInNarrowRows()
	{
		_ = NSApplication.shared
		let path = "Sources/Deeply/Nested/And/Very/Long/Directory/ImportantDocument.swift"
		let row = ViewerFileSearchResultView(relativePath: path)
		row.frame = NSRect(
			x: 0,
			y: 0,
			width: 150,
			height: 34
		)
		row.layoutSubtreeIfNeeded()
		#expect(row.filenameLabel.stringValue == "ImportantDocument.swift")
		#expect(row.directoryLabel.stringValue == "Sources/Deeply/Nested/And/Very/Long/Directory")
		#expect(row.filenameLabel.lineBreakMode == .byTruncatingMiddle)
		#expect(row.directoryLabel.lineBreakMode == .byTruncatingMiddle)
		#expect(row.accessibilityLabel() == path)
		#expect(row.toolTip == path)
		#expect(row.filenameLabel.frame.width <= row.bounds.width)
		#expect(row.directoryLabel.frame.width <= row.bounds.width)

		let topLevel = ViewerFileSearchResultView(relativePath: "README.md")
		#expect(topLevel.filenameLabel.stringValue == "README.md")
		#expect(topLevel.directoryLabel.stringValue == "Top level")
	}

	@Test func navigationClampsAndEmptyResultsHaveNoSelection()
	{
		#expect(ViewerFileSearchSelection.next(
			current: 0,
			count: 0,
			direction: .down
		) == nil)
		#expect(ViewerFileSearchSelection.next(
			current: -1,
			count: 3,
			direction: .first
		) == 0)
		#expect(ViewerFileSearchSelection.next(
			current: -1,
			count: 3,
			direction: .up
		) == 0)
		#expect(ViewerFileSearchSelection.next(
			current: -1,
			count: 3,
			direction: .down
		) == 0)
		#expect(ViewerFileSearchSelection.next(
			current: -1,
			count: 3,
			direction: .last
		) == 2)
		#expect(ViewerFileSearchSelection.next(
			current: 0,
			count: 3,
			direction: .down
		) == 1)
		#expect(ViewerFileSearchSelection.next(
			current: 2,
			count: 3,
			direction: .down
		) == 2)
		#expect(ViewerFileSearchSelection.next(
			current: 2,
			count: 3,
			direction: .up
		) == 1)
		#expect(ViewerFileSearchSelection.next(
			current: 0,
			count: 3,
			direction: .up
		) == 0)
		#expect(ViewerFileSearchSelection.next(
			current: 0,
			count: 3,
			direction: .last
		) == 2)
		#expect(ViewerFileSearchSelection.next(
			current: 99,
			count: 1,
			direction: .down
		) == 0)
	}
}
