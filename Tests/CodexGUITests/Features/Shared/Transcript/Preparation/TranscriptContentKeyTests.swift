import Foundation
import Testing

@testable import CodexGUI

@Suite
struct TranscriptContentKeyTests
{
	@Test func canonicallyEquivalentSourcesRemainDistinctHashableKeys()
	{
		let composed = ConversationContentKey(
			body: "é",
			markdown: true
		)
		let decomposed = ConversationContentKey(
			body: "e\u{301}",
			markdown: true
		)
		#expect(composed.body == decomposed.body)
		#expect(composed != decomposed)
		#expect(Set([composed, decomposed, composed]).count == 2)
		#expect(composed != ConversationContentKey(
			body: "é",
			markdown: false
		))
		#expect(composed != ConversationContentKey(
			body: "é",
			markdown: true,
			preserveSoftBreaks: true
		))
	}

	@Test func collapsedPreviewsMatchFoundationForMixedNewlinesAndEmptyComponents()
	{
		let separators = [
			"\n",
			"\r",
			"\u{000B}",
			"\u{000C}",
			"\u{0085}",
			"\u{2028}",
			"\u{2029}",
			"\r\n",
		]
		let fragments = ["", "ASCII", "😀e\u{0301}"]
		for firstSeparator in separators
		{
			for secondSeparator in separators
			{
				for first in fragments
				{
					for second in fragments
					{
						for third in fragments
						{
							let body = first + firstSeparator + second + secondSeparator + third
							assertFoundationPreview(body)
						}
						assertFoundationPreview(first + firstSeparator + second)
					}
					assertFoundationPreview(first)
				}
			}
		}
	}

	@Test func expandedAndNonExpandableBodiesPreserveUserSoftBreaksAndExactText() throws
	{
		let body = "first\r\n\nsecond\u{2028}third e\u{0301} 😀"
		var entry = ConversationEntry(
			id: "turn:request",
			kind: .user,
			title: "You",
			body: body,
			isExpandable: true
		)
		let expanded = try #require(TranscriptPreparationCoordinator.ContentKey.make(
			for: entry,
			expanded: true
		))
		#expect(expanded.body.utf8.elementsEqual(body.utf8))
		#expect(expanded.markdown)
		#expect(expanded.preserveSoftBreaks)

		let collapsed = try #require(TranscriptPreparationCoordinator.ContentKey.make(
			for: entry,
			expanded: false
		))
		#expect(collapsed.body.utf8.elementsEqual("first\n".utf8))
		#expect(collapsed.preserveSoftBreaks)
		entry.isExpandable = false
		let complete = try #require(TranscriptPreparationCoordinator.ContentKey.make(
			for: entry,
			expanded: false
		))
		#expect(complete.body.utf8.elementsEqual(body.utf8))
	}

	private func assertFoundationPreview(_ body: String)
	{
		let expected = body.components(separatedBy: .newlines).prefix(2).joined(separator: "\n")
		let actual = TranscriptPreparationCoordinator.ContentKey.collapsedPreview(of: body)
		#expect(
			actual.utf8.elementsEqual(expected.utf8),
			"Body: \(body.debugDescription)"
		)
	}
}
