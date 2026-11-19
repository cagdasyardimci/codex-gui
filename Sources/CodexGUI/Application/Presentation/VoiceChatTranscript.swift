import Foundation

/// Projects the realtime conversation into ordinary transcript rows.
enum VoiceChatTranscript
{
	private struct Speech: Hashable
	{
		let isUser: Bool
		let text: String
	}

	private struct Record
	{
		let isHandoff: Bool
		let speech: [Speech]

		// Legacy history stores the same speech as escaped turn context. Recognize
		// the complete envelope before treating its contents as realtime records.
		init?(_ entry: ConversationEntry)
		{
			let prefix = "<realtime_delegation>\n"
			let suffix = "\n</realtime_delegation>"
			let tail = "  <source>transcript_tail_flush</source>\n"
			let input = "  <input>"
			let transcript = "\n  <transcript_delta>"
			let endTranscript = "</transcript_delta>"
			guard entry.kind == .user, entry.body.hasPrefix(prefix), entry.body.hasSuffix(suffix)
			else
			{
				return nil
			}

			var contents = entry.body.dropFirst(prefix.count).dropLast(suffix.count)
			let isTail = contents.hasPrefix(tail)
			if isTail
			{
				contents = contents.dropFirst(tail.count)
			}
			guard contents.hasPrefix(input), let endInput = contents.range(of: "</input>")
			else
			{
				return nil
			}
			isHandoff = !isTail && contents.index(
				contents.startIndex,
				offsetBy: input.count
			)
				< endInput.lowerBound
			contents = contents[endInput.upperBound...]
			if contents.isEmpty
			{
				speech = []
				return
			}
			guard contents.hasPrefix(transcript), contents.hasSuffix(endTranscript)
			else
			{
				return nil
			}
			speech = Self.parseSpeech(
				contents.dropFirst(transcript.count).dropLast(endTranscript.count)
			)
		}

		private static func parseSpeech(_ transcript: Substring) -> [Speech]
		{
			var speech: [Speech] = []
			var isUser: Bool?
			var lines: [Substring] = []
			func closeSpeaker()
			{
				guard let isUser
				else
				{
					return
				}
				let text = lines.joined(separator: "\n")
					.replacingOccurrences(
						of: "&lt;",
						with: "<"
					)
					.replacingOccurrences(
						of: "&gt;",
						with: ">"
					)
					.replacingOccurrences(
						of: "&amp;",
						with: "&"
					)
					.trimmingCharacters(in: .whitespacesAndNewlines)
				if !text.isEmpty
				{
					speech.append(Speech(
						isUser: isUser,
						text: text
					))
				}
			}
			for line in transcript.split(
				separator: "\n",
				omittingEmptySubsequences: false
			)
			{
				let user = line.hasPrefix("user: ")
				if user || line.hasPrefix("assistant: ")
				{
					closeSpeaker()
					isUser = user
					lines = [line.dropFirst(user ? "user: ".count : "assistant: ".count)]
				}
				else
				{
					lines.append(line)
				}
			}
			closeSpeaker()
			return speech
		}
	}

	static func present(
		_ entries: [ConversationEntry],
		segments: [VoiceChatSegment],
		hasCanonicalSpeech: Bool = false,
		historyTurnIDs: Set<String> = [],
		historicalTurnOrder: [String] = [],
		liveTurnIDs: Set<String> = []
	) -> [ConversationEntry]
	{
		let turns = entries.map
		{
			ConversationEntryIdentity.turnIDWithFallback($0.id)
		}
		let records = entries.map(Record.init)
		let visibleSegments = placeSpeech(
			segments,
			visibleTurns: Set(turns),
			historicalTurnOrder: historicalTurnOrder
		)
		var voiceTurns = historyTurnIDs.union(liveTurnIDs)
		voiceTurns.formUnion(visibleSegments.compactMap(\.precedingTurnID))
		var previousTurn: String?
		for index in entries.indices
		{
			let turn = turns[index]
			if let record = records[index]
			{
				if record.isHandoff || !record.speech.isEmpty
				{
					voiceTurns.insert(turn)
				}
				// A standalone audio recording turn follows the channel-tagged
				// reply it spoke. The backend often receives that prompt as plain text.
				if !record.isHandoff, record.speech.contains(where:
					{
						!$0.isUser
					}),
					let previousTurn
				{
					voiceTurns.insert(previousTurn)
				}
			}
			if index + 1 < turns.count, turns[index + 1] != turn
			{
				previousTurn = turn
			}
		}

		let segmentsByTurn = Dictionary(
			grouping: visibleSegments,
			by: \.precedingTurnID
		)
		var legacyLiveSpeech = Dictionary(grouping: visibleSegments)
		{
			Speech(
				isUser: $0.isUser,
				text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
			)
		}.mapValues(\.count)
		var result = segmentsByTurn[nil, default: []].map(\.entry)
		var encountered: Set<String> = []
		for (index, entry) in entries.enumerated()
		{
			let turn = turns[index]
			if let record = records[index]
			{
				if !hasCanonicalSpeech
				{
					for (offset, speech) in record.speech.enumerated()
					{
						if liveTurnIDs.contains(turn), legacyLiveSpeech[speech, default: 0] > 0
						{
							legacyLiveSpeech[speech, default: 0] -= 1
							continue
						}
						result.append(VoiceChatSegment(
							id: "\(entry.id):speech-\(offset)",
							isUser: speech.isUser,
							text: speech.text
						).entry)
					}
				}
			}
			else if let visible = present(
				entry,
				isVoiceTurn: voiceTurns.contains(turn)
			)
			{
				result.append(visible)
			}
			if index == entries.count - 1 || turns[index + 1] != turn
			{
				result += segmentsByTurn[turn, default: []].map(\.entry)
				encountered.insert(turn)
			}
		}
		return result + visibleSegments.filter
		{
			$0.precedingTurnID.map
			{
				!encountered.contains($0)
			} == true
		}.map(\.entry)
	}

	private static func placeSpeech(
		_ segments: [VoiceChatSegment],
		visibleTurns: Set<String>,
		historicalTurnOrder: [String]
	) -> [VoiceChatSegment]
	{
		let ranks = Dictionary(uniqueKeysWithValues: historicalTurnOrder.enumerated().map
		{
			($0.element, $0.offset)
		})
		let visibleRanks = historicalTurnOrder.indices.filter
		{
			visibleTurns.contains(historicalTurnOrder[$0])
		}
		return segments.compactMap
		{
			segment in
			guard !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			else
			{
				return nil
			}
			guard let anchor = segment.precedingTurnID, !visibleTurns.contains(anchor),
					let rank = ranks[anchor]
			else
			{
				return segment
			}
			// A filtered turn can sit between two visible turns. Speech outside
			// the loaded history window must wait for its original window to load.
			guard let preceding = visibleRanks.last(where:
				{
					$0 < rank
				}),
				let last = visibleRanks.last, rank < last
			else
			{
				return nil
			}
			var placed = segment
			placed.precedingTurnID = historicalTurnOrder[preceding]
			return placed
		}
	}

	private static func present(
		_ entry: ConversationEntry,
		isVoiceTurn: Bool
	) -> ConversationEntry?
	{
		guard entry.kind == .agent, isVoiceTurn
		else
		{
			return entry
		}
		let channels = ["[STATUS]", "[COMPLETE]", "[analysis]", "[final]"]
		let channel = channels.first
		{
			entry.body == $0 || entry.body.hasPrefix($0 + " ") || entry.body.hasPrefix($0 + "\n")
		}
		let body = channel.map
		{
			entry.body.dropFirst($0.count).drop(while: \.isWhitespace)
		} ?? entry.body[...]
		let directive = "::codex-realtime-inline{}"
		if body == directive
		{
			return nil
		}
		if body.hasPrefix(directive + "\n")
		{
			var entry = entry
			entry.body = String(body.dropFirst(directive.count + 1))
			return entry
		}
		return channel == nil ? entry : nil
	}
}
