import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ViewerStatusViewTests
{
	@Test func longFailureRemainsSelectableAndWithinPaneAcrossAppearanceAndWidth() throws
	{
		_ = NSApplication.shared
		let message = "The file could not be loaded. "
			+ "Check access to this folder and retry the operation."
		let status = ViewerStatusView(message: message)
		for appearance in [NSAppearance.Name.aqua, .darkAqua]
		{
			status.appearance = NSAppearance(named: appearance)
			for width in [CGFloat(180), 480]
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
				#expect(rect.minX >= 0)
				#expect(rect.maxX <= width)
				#expect(rect.height > 0)
				#expect(abs(rect.midY - status.bounds.midY) < 1)
			}
		}
		status.setMessage("Loading file…")
		#expect(status.messageLabel.stringValue == "Loading file…")
	}
}
