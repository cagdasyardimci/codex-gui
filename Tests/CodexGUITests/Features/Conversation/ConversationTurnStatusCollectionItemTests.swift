import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationTurnStatusCollectionItemTests
{
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
