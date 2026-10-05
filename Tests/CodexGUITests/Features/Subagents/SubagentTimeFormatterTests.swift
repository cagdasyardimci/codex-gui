import Foundation
import Testing

@testable import CodexGUI

struct SubagentTimeFormatterTests
{
	@Test func elapsedTimeSelectsSecondsMinutesHoursAndDaysAtBoundaries()
	{
		let now = Date(timeIntervalSince1970: 200000)
		let cases: [(TimeInterval, String)] = [
			(0, "0s ago"),
			(59, "59s ago"),
			(60, "1m ago"),
			(3599, "59m ago"),
			(3600, "1h ago"),
			(86399, "23h ago"),
			(86400, "1d ago"),
			(172800, "2d ago"),
		]
		for (elapsedSeconds, expected) in cases
		{
			#expect(SubagentTimeFormatter.relativeCompletion(
				completedAt: now.addingTimeInterval(-elapsedSeconds),
				now: now
			) == expected)
		}
	}

	@Test func futureTimesClampToZeroAndFractionalSecondsRoundDown()
	{
		let now = Date(timeIntervalSince1970: 10000)
		#expect(SubagentTimeFormatter.relativeCompletion(
			completedAt: now.addingTimeInterval(600),
			now: now
		) == "0s ago")
		#expect(SubagentTimeFormatter.relativeCompletion(
			completedAt: now.addingTimeInterval(-59.9),
			now: now
		) == "59s ago")
	}

	@Test func activeElapsedClockShowsWholeSecondsAndClampsFutureStarts()
	{
		let now = Date(timeIntervalSince1970: 10000)
		let cases: [(TimeInterval, String)] = [
			(-30, "0s"),
			(0, "0s"),
			(59.9, "59s"),
			(60, "1m 0s"),
			(3599, "59m 59s"),
			(3600, "1h 0m 0s"),
			(4227, "1h 10m 27s"),
		]
		for (seconds, expected) in cases
		{
			#expect(SubagentTimeFormatter.elapsed(
				startedAt: now.addingTimeInterval(-seconds),
				now: now
			) == expected)
		}
	}

}
