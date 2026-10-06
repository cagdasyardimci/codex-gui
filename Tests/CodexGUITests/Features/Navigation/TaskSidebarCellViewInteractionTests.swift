import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TaskSidebarCellViewInteractionTests
{
	@Test func progressRingStopsWhenDetachedOrCellIsReused() throws
	{
		_ = NSApplication.shared
		let cell = TaskSidebarCellView(frame: NSRect(
			x: 0,
			y: 0,
			width: 240,
			height: 30
		))
		let window = NSWindow(
			contentRect: cell.frame,
			styleMask: [],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		defer
		{
			window.close()
		}
		cell.setTurnRunning(true)
		window.contentView?.addSubview(cell)
		cell.layoutSubtreeIfNeeded()
		let ringLayer = try #require(cell.progressRing.layer?.sublayers?.first)
		#expect(ringLayer.animation(forKey: "taskRotation") != nil)
		cell.removeFromSuperview()
		#expect(ringLayer.animation(forKey: "taskRotation") == nil)
		window.contentView?.addSubview(cell)
		#expect(ringLayer.animation(forKey: "taskRotation") != nil)
		cell.setTurnRunning(false)
		#expect(ringLayer.animation(forKey: "taskRotation") == nil)
		#expect(cell.progressRing.isHidden)
		cell.removeFromSuperview()
	}

}
