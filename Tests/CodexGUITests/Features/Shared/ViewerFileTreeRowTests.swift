import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ViewerFileTreeRowTests
{
	@Test func sharedGeometryKeepsNamesVisibleAtNarrowWidthsAndDepths()
	{
		_ = NSApplication.shared
		let name = "a-very-long-file-name-with-a-distinct-ending.swift"
		let path = "Sources/Deep/\(name)"
		let icon = WorkspaceFileIcon.image(relativePath: path)
		let cell = ViewerFileTreeRow()
		cell.frame = NSRect(
			x: 0,
			y: 0,
			width: 180,
			height: ViewerFileTreeLayout.rowHeight
		)
		cell.configure(
			name: name,
			path: path,
			depth: 2,
			isDirectory: false,
			isExpanded: false,
			icon: icon
		)
		cell.layoutSubtreeIfNeeded()
		#expect(cell.nameLabel.lineBreakMode == .byTruncatingTail)
		#expect(cell.toolTip == path)
		#expect(cell.nameLabel.frame.width > 0)
		#expect(cell.iconView.frame.maxX <= cell.nameLabel.frame.minX)
		#expect(cell.nameLabel.frame.maxX <= cell.bounds.maxX)
		let nestedX = cell.nameLabel.frame.minX

		cell.configure(
			name: name,
			path: name,
			depth: 0,
			isDirectory: false,
			isExpanded: false,
			icon: icon
		)
		cell.layoutSubtreeIfNeeded()
		#expect(abs(nestedX - cell.nameLabel.frame.minX
				- 2 * ViewerFileTreeLayout.indentation) < 0.5)
	}

	@Test func directoryDisclosureUsesSameGlyphColumnAndCallsAdapterOnce() throws
	{
		_ = NSApplication.shared
		let cell = ViewerFileTreeRow()
		cell.frame = NSRect(
			x: 0,
			y: 0,
			width: 220,
			height: ViewerFileTreeLayout.rowHeight
		)
		var toggles = 0
		cell.configure(
			name: "Sources",
			path: "Sources",
			depth: 0,
			isDirectory: true,
			isExpanded: false,
			icon: nil,
			onToggle:
			{
				toggles += 1
			}
		)
		cell.layoutSubtreeIfNeeded()
		let button = try #require(cell.subviews.compactMap
		{
			$0 as? NSButton
		}.first)
		#expect(button.frame.minX == cell.iconView.frame.minX)
		#expect(button.frame.maxX <= cell.nameLabel.frame.minX)
		let control = button
		#expect(control.sendAction(
			try #require(control.action),
			to: control.target
		))
		#expect(toggles == 1)
	}
}
