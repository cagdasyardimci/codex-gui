import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationTurnStatusCollectionItemTests
{
	@Test func activeClockUsesCurrentTimeEvenWithPartialDuration()
	{
		let start = Date(timeIntervalSince1970: 1000)
		#expect(text(
			timing(
				status: "inProgress",
				start: start,
				duration: 1000
			),
			now: start.addingTimeInterval(48)
		) == "Working for 48s")
	}

	@Test func activeClockAdvancesAndTerminalDurationFreezes()
	{
		let start = Date(timeIntervalSince1970: 1000)
		let active = timing(
			status: "inProgress",
			start: start
		)
		#expect(text(
			active,
			now: start.addingTimeInterval(65)
		) == "Working for 1m 5s")
		let finished = timing(
			status: "completed",
			start: start,
			end: start.addingTimeInterval(10),
			duration: 12345
		)
		#expect(text(
			finished,
			now: start.addingTimeInterval(999)
		) == "Worked for 12s")
	}

	@Test func terminalMissingDurationDoesNotUseCurrentClock()
	{
		let start = Date(timeIntervalSince1970: 1000)
		#expect(text(
			timing(
				status: "statusUnknown",
				start: start
			),
			now: Date()
		) == "Status unavailable")
		#expect(text(
			timing(
				status: "failed",
				start: start
			),
			now: Date()
		) == "Failed")
		#expect(text(
			timing(
				status: "interrupted",
				start: start
			),
			now: Date()
		) == "Interrupted")
		#expect(text(
			timing(
				status: "completed",
				start: nil
			),
			now: Date()
		) == "Worked")
	}

	@Test func terminalTimestampsAndFailedDurationsAreExplicit()
	{
		let start = Date(timeIntervalSince1970: 1000)
		#expect(text(
			timing(
				status: "completed",
				start: start,
				end: start.addingTimeInterval(2)
			),
			now: Date()
		) == "Worked for 2s")
		#expect(text(
			timing(
				status: "failed",
				start: nil,
				duration: 9000
			),
			now: Date()
		)
			== "Failed after 9s")
	}

	@Test func workDisclosureUpdatesAndClearsCallbackOnReuse() throws
	{
		let item = ConversationTurnStatusCollectionItem()
		let finished = timing(
			status: "completed",
			start: nil,
			duration: 184000
		)
		var toggles = 0
		item.configure(
			finished,
			now: Date(),
			onToggle:
			{
				toggles += 1
			}
		)
		let button = try #require(item.view.subviews.compactMap
		{
			$0 as? NSButton
		}.first)
		#expect(!button.isHidden)
		#expect(button.accessibilityLabel() == "Expand Worked for 3m 4s")
		button.performClick(nil)
		#expect(toggles == 1)
		item.configure(
			finished,
			now: Date(),
			expanded: true,
			onToggle:
			{
				toggles += 1
			}
		)
		#expect(button.accessibilityLabel() == "Collapse Worked for 3m 4s")
		item.prepareForReuse()
		button.performClick(nil)
		#expect(toggles == 1)
		item.configure(
			finished,
			now: Date()
		)
		#expect(button.isHidden)
	}

	private func text(
		_ timing: ConversationTurnTiming,
		now: Date
	) -> String
	{
		ConversationTurnStatusCollectionItem.statusText(
			timing: timing,
			now: now
		)
	}

	private func timing(
		status: String,
		start: Date?,
		end: Date? = nil,
		duration: Double? = nil
	) -> ConversationTurnTiming
	{
		ConversationTurnTiming(turn: CodexTurn(
			id: "turn",
			status: status,
			items: [],
			error: nil,
			startedAt: start,
			completedAt: end,
			durationMs: duration
		))
	}
}
