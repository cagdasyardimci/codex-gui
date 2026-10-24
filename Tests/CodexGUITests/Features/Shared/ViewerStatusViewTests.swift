import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ViewerStatusViewTests
{
	@Test(arguments: [false, true])
	func longFailureRemainsSelectableAndWithinPaneAcrossAppearanceAndWidth(
		withIconAndTitle: Bool
	) throws
	{
		_ = NSApplication.shared
		let message = "The file could not be loaded. "
			+ "Check access to this folder and retry the operation."
		let status = ViewerStatusView(
			icon: withIconAndTitle ? NSImage(size: NSSize(
				width: 32,
				height: 32
			)) : nil,
			title: withIconAndTitle ? "Cannot open file" : nil,
			message: message
		)
		for appearance in [NSAppearance.Name.aqua, .darkAqua]
		{
			status.appearance = NSAppearance(named: appearance)
			for width in [CGFloat(0), 16, 180, 480, 0, 180]
			{
				status.frame = NSRect(
					x: 0,
					y: 0,
					width: width,
					height: 240
				)
				status.layoutSubtreeIfNeeded()
				let label = status.messageLabel
				let rect = status.convert(
					label.bounds,
					from: label
				)
				#expect(label.stringValue == message)
				#expect(label.isSelectable)
				if width >= 180
				{
					#expect(rect.minX >= 16)
					#expect(rect.maxX <= width - 16)
				}
				#expect(rect.height > 0)
				#expect(abs(try #require(label.superview).frame.midY - status.bounds.midY) < 1)
			}
		}
		status.setMessage("Loading file…")
		#expect(status.messageLabel.stringValue == "Loading file…")
	}
}
