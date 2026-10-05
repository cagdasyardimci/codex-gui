import Foundation

enum SubagentTimeFormatter
{
	static func relativeCompletion(
		completedAt: Date,
		now: Date
	) -> String
	{
		let elapsedSeconds = elapsedSeconds(
			since: completedAt,
			now: now
		)
		let unitSeconds: Int
		let suffix: String
		if elapsedSeconds >= 86400
		{
			unitSeconds = 86400
			suffix = "d"
		}
		else if elapsedSeconds >= 3600
		{
			unitSeconds = 3600
			suffix = "h"
		}
		else if elapsedSeconds >= 60
		{
			unitSeconds = 60
			suffix = "m"
		}
		else
		{
			unitSeconds = 1
			suffix = "s"
		}
		let value = elapsedSeconds / unitSeconds
		return "\(value)\(suffix) ago"
	}

	static func elapsed(
		startedAt: Date,
		now: Date
	) -> String
	{
		let seconds = elapsedSeconds(
			since: startedAt,
			now: now
		)
		let hours = seconds / 3600
		let minutes = seconds % 3600 / 60
		let remainingSeconds = seconds % 60
		if hours > 0
		{
			return "\(hours)h \(minutes)m \(remainingSeconds)s"
		}
		if minutes > 0
		{
			return "\(minutes)m \(remainingSeconds)s"
		}
		return "\(remainingSeconds)s"
	}

	private static func elapsedSeconds(
		since timestamp: Date,
		now: Date
	) -> Int
	{
		Int(max(
			0,
			now.timeIntervalSince(timestamp)
		))
	}

}
