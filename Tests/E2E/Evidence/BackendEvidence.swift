import Foundation

func backendErrors(_ run: URL) -> [String]
{
	do
	{
		let data = try String(
			contentsOf: run.appendingPathComponent("backend-trace.jsonl"),
			encoding: .utf8
		)
		let methods = ["turn/start", "turn/interrupt", "turn/completed"]
		var counts = [0, 0, 0]
		var firstEvents: [Object?] = [nil, nil, nil]
		for line in data.split(separator: "\n")
		{
			guard let event = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? Object
			else
			{
				throw EvidenceError.invalid("Invalid backend event")
			}
			if let index = methods.firstIndex(of: text(
				event,
				"method"
			))
			{
				counts[index] += 1
				if counts[index] == 1
				{
					firstEvents[index] = event
				}
			}
		}
		var errors = zip(
			methods,
			counts
		).filter
		{
			$0.1 != 1
		}.map
		{
			$0.0 + ": expected exactly one event"
		}
		if !errors.isEmpty
		{
			return errors
		}
		let start = firstEvents[0]!, interrupt = firstEvents[1]!, complete = firstEvents[2]!
		let fixture = try object(run.appendingPathComponent("fixture.json"))
		let origin = text(
			fixture,
			"runDirectory"
		)
		guard origin.hasPrefix("/")
		else
		{
			throw EvidenceError.invalid("Fixture run directory must be absolute")
		}
		if (start["resolvedCwd"] as? String ?? text(
			start,
			"cwd"
		)) != URL(fileURLWithPath: origin)
			.appendingPathComponent("project with spaces")
			.path
		{
			errors.append("Backend received the wrong project path")
		}
		let expected: [Object] = [[
			"text": "E2E example: stream Markdown — café 日本語 so I can stop it.",
			"text_elements": [],
			"type": "text"
		]]
		if (start["input"] as? NSArray)?
			.isEqual(to: expected) !=
			true
		{
			errors.append("Backend did not receive the exact single text input")
		}
		if [start, interrupt, complete]
			.contains(where:
				{
					text(
						$0,
						"threadId"
					) != "qa-reading"
				})
		{
			errors.append("Backend events belong to the wrong thread")
		}
		if text(
			interrupt,
			"turnId"
		).isEmpty || text(
			interrupt,
			"turnId"
		) != text(
			complete,
			"turnId"
		)
		{
			errors.append("Interrupted and completed turn owners differ")
		}
		if text(
			complete,
			"status"
		) !=
			"interrupted"
		{
			errors.append("Backend completion was not interrupted")
		}
		if !(number(
			start,
			"time"
		) <= number(
			interrupt,
			"time"
		) && number(
			interrupt,
			"time"
		) <=
			number(
				complete,
				"time"
			))
		{
			errors.append("Backend event order is inconsistent")
		}
		return errors
	}
	catch
	{
		return ["Backend outcome evidence is unreadable: " + String(describing: error)]
	}
}
