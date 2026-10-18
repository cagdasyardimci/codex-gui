import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ConversationTurnTimerTests
{
	@Test(arguments: ["inProgress", "running"])
	func streamingUpdatesPreserveScheduledTickAndHiddenTranscriptStopsTimer(status: String) throws
	{
		_ = NSApplication.shared
		let controller = TranscriptViewController()
		controller.requestedTurnTimings = [ConversationTurnTiming(
			turnID: "turn",
			status: status,
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

	@Test(arguments: ["inProgress", "running"])
	func historyClockRequiresMatchingLiveExecution(status: String) async
	{
		_ = NSApplication.shared
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/turn-clock"
		))
		model.conversations.selectedConversation = .thread("worker")
		let snapshot = WorkspaceSelectors(
			model: model,
			now: Date()
		).makeSnapshot()
		let timing = ConversationTurnTiming(
			turnID: "turn",
			status: status,
			startedAt: Date()
		)
		let controller = TranscriptViewController()
		defer
		{
			controller.turnStatusTimer?.invalidate()
		}
		for (state, threadID, turnID, expectsRunning) in [
			(ExecutionState.running, "worker", "turn", true),
			(.running, "other", "turn", false),
			(.running, "worker", "other", false),
			(.ready, "worker", "turn", false)
		]
		{
			controller.timingExecutionState = state
			controller.prepareTranscript(TranscriptPresentation(
				owner: FeaturePresentationOwner(snapshot),
				entries: [],
				turnTimings: [timing],
				canLoadEarlierTurns: false,
				navigation: nil,
				executionState: state,
				activeThreadID: threadID,
				activeTurnID: turnID
			))
			await controller.waitForRendering()
			controller.updateTurnStatusTimer()
			#expect(controller.requestedTurnTimings.first?.status
				== (expectsRunning ? status : "statusUnknown"))
			#expect((controller.turnStatusTimer != nil) == expectsRunning)
		}
	}

	@Test(arguments: ["completed", "failed", "interrupted", "stopped", "cancelled"])
	func terminalTurnNeverSchedulesClockWhileExecutionWaits(status: String)
	{
		_ = NSApplication.shared
		let controller = TranscriptViewController()
		controller.requestedTurnTimings = [ConversationTurnTiming(
			turnID: "turn",
			status: status,
			startedAt: Date()
		)]
		controller.timingExecutionState = .stopping
		controller.updateTurnStatusTimer()
		defer
		{
			controller.turnStatusTimer?.invalidate()
		}
		#expect(controller.turnStatusTimer == nil)
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

	@Test(arguments: ["inProgress", "running"])
	func scheduledTickRefreshesVisibleElapsedTextAndRejectsAnotherTranscript(
		status: String
	) async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let controller = TranscriptViewController()
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 600,
					height: 240
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.contentViewController = controller
			window.setContentSize(NSSize(
				width: 600,
				height: 240
			))
			defer
			{
				controller.turnStatusTimer?.invalidate()
				window.contentViewController = nil
				window.close()
			}
			window.orderFront(nil)
			let start = Date(timeIntervalSince1970: 1000)
			let timing = ConversationTurnTiming(
				turnID: "turn",
				status: status,
				startedAt: start
			)
			controller.requestedTurnTimings = [timing]
			controller.timingExecutionState = .running
			controller.view.layoutSubtreeIfNeeded()
			controller.prepareEntries(
				[ConversationEntry(
					id: "turn:user",
					kind: .user,
					title: "You",
					body: "Request"
				)],
				context: "timer:original"
			)
			await controller.waitForRendering()
			controller.turnStatusTimer?.invalidate()
			controller.turnStatusTimer = nil
			controller.view.layoutSubtreeIfNeeded()
			controller.conversationScrollView.tile()
			let layout = try #require(controller.collectionView.collectionViewLayout)
			layout.prepare()
			controller.collectionView.layoutSubtreeIfNeeded()
			window.displayIfNeeded()
			let item = try #require(controller.collectionView.visibleItems().compactMap
			{
				$0 as? ConversationTurnStatusCollectionItem
			}.first)
			item.configure(
				timing,
				now: start.addingTimeInterval(48)
			)
			let label = try #require(item.view.subviews.compactMap
			{
				$0 as? NSTextField
			}.first)
			try #require(!label.isHidden && !item.view.visibleRect.isEmpty)
			#expect(label.stringValue == "Working for 48s")
			var currentTime = start.addingTimeInterval(49)
			controller.updateTurnStatusTimer(now:
				{
					currentTime
				})
			let timer = try #require(controller.turnStatusTimer)
			timer.fire()
			#expect(label.stringValue == "Working for 49s")
			#expect(label.accessibilityLabel() == "Working for 49s")
			currentTime = start.addingTimeInterval(65)
			timer.fire()
			#expect(label.stringValue == "Working for 1m 5s")
			controller.requestedContext = "timer:replacement"
			currentTime = start.addingTimeInterval(70)
			timer.fire()
			#expect(label.stringValue == "Working for 1m 5s")
			controller.requestedContext = "timer:original"
			controller.timingExecutionState = .completed
			timer.fire()
			#expect(label.stringValue == "Working for 1m 5s")
		}
	}
}
