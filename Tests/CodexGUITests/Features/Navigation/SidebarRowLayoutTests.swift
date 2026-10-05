import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct SidebarRowLayoutTests
{
	@Test func taskTitleUsesSpaceUntilVisibleStatusOrActionsNeedIt() throws
	{
		_ = NSApplication.shared
		let cell = TaskSidebarCellView(frame: NSRect(
			x: 0,
			y: 0,
			width: 240,
			height: 30
		))
		let label = try #require(cell.textField)
		label.stringValue = "A task title long enough to fill the sidebar"
		cell.layoutSubtreeIfNeeded()
		let idleTitle = label.alignmentRect(forFrame: label.frame)
		#expect(idleTitle.maxX == cell.bounds.maxX - 4)

		cell.setTurnRunning(true)
		cell.layoutSubtreeIfNeeded()
		let runningTitle = label.alignmentRect(forFrame: label.frame)
		#expect(runningTitle.maxX == cell.progressRing.frame.minX - 4)
		#expect(runningTitle.width < idleTitle.width)

		cell.setTurnRunning(false)
		cell.setUnread(true)
		cell.layoutSubtreeIfNeeded()
		let unreadTitle = label.alignmentRect(forFrame: label.frame)
		#expect(unreadTitle.maxX == cell.unreadDot.frame.minX - 4)
		#expect(unreadTitle.width > runningTitle.width)
		#expect(unreadTitle.width < idleTitle.width)

		let event = try hoverEvent()
		cell.mouseEntered(with: event)
		let actions = try #require(cell.archiveButton.superview)
		let hoveredTitle = label.alignmentRect(forFrame: label.frame)
		#expect(!actions.isHidden)
		#expect(hoveredTitle.maxX == actions.frame.minX - 4)
		#expect(hoveredTitle.width < unreadTitle.width)

		cell.setTurnRunning(true)
		cell.setUnread(false)
		cell.layoutSubtreeIfNeeded()
		#expect(label.alignmentRect(forFrame: label.frame) == hoveredTitle)
		cell.mouseExited(with: event)
		cell.layoutSubtreeIfNeeded()
		#expect(actions.isHidden)
		#expect(label.alignmentRect(forFrame: label.frame) == runningTitle)
		cell.setTurnRunning(false)
		cell.layoutSubtreeIfNeeded()
		#expect(label.alignmentRect(forFrame: label.frame) == idleTitle)
	}

	@Test func projectTitleReservesActionsOnlyForCurrentOrHoveredProject() throws
	{
		_ = NSApplication.shared
		let cell = ProjectSidebarCellView(frame: NSRect(
			x: 0,
			y: 0,
			width: 240,
			height: 30
		))
		let project = URL(fileURLWithPath: "/tmp/sidebar-layout")
		cell.render(
			project: project,
			name: "A project title long enough to fill the sidebar",
			isCurrent: false,
			isPinned: false,
			canStartChat: true
		)
		let label = try #require(cell.textField)
		let actions = try #require(cell.subviews.compactMap
		{
			$0 as? NSStackView
		}.first)
		cell.layoutSubtreeIfNeeded()
		let idleTitle = label.alignmentRect(forFrame: label.frame)
		#expect(actions.isHidden)
		#expect(idleTitle.maxX == cell.bounds.maxX - 4)

		let event = try hoverEvent()
		cell.mouseEntered(with: event)
		cell.layoutSubtreeIfNeeded()
		let hoveredTitle = label.alignmentRect(forFrame: label.frame)
		#expect(!actions.isHidden)
		#expect(hoveredTitle.maxX == actions.frame.minX - 4)
		#expect(hoveredTitle.width < idleTitle.width)
		cell.mouseExited(with: event)
		cell.layoutSubtreeIfNeeded()
		#expect(label.alignmentRect(forFrame: label.frame) == idleTitle)

		cell.render(
			project: project,
			name: label.stringValue,
			isCurrent: true,
			isPinned: false,
			canStartChat: true
		)
		cell.mouseExited(with: event)
		cell.layoutSubtreeIfNeeded()
		#expect(!actions.isHidden)
		#expect(label.alignmentRect(forFrame: label.frame) == hoveredTitle)
	}

	private func hoverEvent() throws -> NSEvent
	{
		try #require(NSEvent.enterExitEvent(
			with: .mouseEntered,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			eventNumber: 0,
			trackingNumber: 0,
			userData: nil
		))
	}
}
