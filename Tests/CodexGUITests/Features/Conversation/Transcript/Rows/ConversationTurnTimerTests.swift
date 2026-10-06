import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ConversationTurnTimerTests
{
	@Test func streamingUpdatesPreserveScheduledTickAndHiddenTranscriptStopsTimer() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		controller.requestedTurnTimings = [ConversationTurnTiming(
			turnID: "turn",
			status: "inProgress",
			startedAt: Date()
		)]
		controller.timingExecutionState = .running
		controller.updateTurnStatusTimer()
		defer
		{
			controller.turnStatusTimer?.invalidate()
		}
		let timer = try #require(controller.turnStatusTimer)
		let nextTick = timer.fireDate
		for _ in 0 ..< 20
		{
			controller.updateTurnStatusTimer()
			#expect(controller.turnStatusTimer === timer)
			#expect(timer.fireDate == nextTick)
		}
		controller.transcriptIsVisible = false
		controller.updateTurnStatusTimer()
		#expect(controller.turnStatusTimer == nil)
		#expect(!timer.isValid)
	}

	@Test func clockHeaderPlacesAccessibleLabelAboveFullWidthDivider() throws
	{
		_ = NSApplication.shared
		let item = ConversationTurnStatusCollectionItem()
		let start = Date(timeIntervalSince1970: 1000)
		item.configure(
			ConversationTurnTiming(
				turnID: "turn",
				status: "inProgress",
				startedAt: start
			),
			now: start.addingTimeInterval(48)
		)
		item.view.frame.size = ConversationTurnStatusCollectionItem.itemSize(width: 400)
		item.view.layoutSubtreeIfNeeded()
		let label = try #require(item.view.subviews.compactMap
		{
			$0 as? NSTextField
		}.first)
		let divider = try #require(item.view.subviews.compactMap
		{
			$0 as? NSBox
		}.first)
		#expect(label.stringValue == "Working for 48s")
		#expect(label.accessibilityLabel() == label.stringValue)
		#expect(divider.boxType == .separator)
		#expect(divider.frame.width == item.view.bounds.width)
		#expect(label.frame.minY > divider.frame.maxY)
		item.refresh(now: start.addingTimeInterval(49))
		#expect(label.stringValue == "Working for 49s")
	}
}
