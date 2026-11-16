import Foundation
import Testing

@testable import CodexGUI

@Suite
struct ConversationTextIdentityTests
{
	private static let longBody = String(
		repeating: "Forest 🌲 cafe\u{0301}\n",
		count: 4000
	)
	private static let cases: [(String, String, Bool)] = [
		("", "", true),
		("", "a", false),
		("a", "", false),
		("short", "short", true),
		("a\0b", "a\0c", false),
		("é", "e\u{0301}", false),
		("a\u{0301}\u{0323}", "a\u{0323}\u{0301}", false),
		(longBody, longBody, true),
		(longBody, String(
			decoding: Array(longBody.utf8),
			as: UTF8.self
		), true),
		(longBody + "a", longBody + "b", false),
		(longBody, longBody + "more", false),
		((NSString(string: longBody) as String), longBody, true),
	]

	@Test(arguments: cases)
	func transcriptAndPreparationKeysPreserveExactSource(
		first: String,
		second: String,
		equal: Bool
	)
	{
		let firstEntry = ConversationEntry(
			id: "reply",
			kind: .agent,
			title: "Codex",
			body: first
		)
		let secondEntry = ConversationEntry(
			id: "reply",
			kind: .agent,
			title: "Codex",
			body: second
		)
		#expect((firstEntry == secondEntry) == equal)
		let firstKey = TranscriptPreparationCoordinator.ContentKey(
			body: first,
			markdown: true
		)
		let secondKey = TranscriptPreparationCoordinator.ContentKey(
			body: second,
			markdown: true
		)
		#expect((firstKey == secondKey) == equal)
	}
}
