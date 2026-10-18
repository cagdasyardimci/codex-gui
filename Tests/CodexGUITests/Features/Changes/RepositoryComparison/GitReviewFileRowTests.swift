import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitReviewFileRowTests
{
	@Test func outlinedSelectionKeepsNormalTextBackgroundStyle()
	{
		_ = NSApplication.shared
		let row = ViewerFileTreeSelectionRow()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 300,
				height: 28
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.contentView = row
		for appearanceName in [NSAppearance.Name.aqua, .darkAqua, .aqua]
		{
			window.appearance = NSAppearance(named: appearanceName)
			for selected in [false, true]
			{
				row.isSelected = selected
				for emphasized in [false, true]
				{
					row.isEmphasized = emphasized
					#expect(row.interiorBackgroundStyle == .normal)
				}
			}
		}
	}
}
