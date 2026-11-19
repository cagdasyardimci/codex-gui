import Testing

@testable import CodexGUI

struct VoiceChatTranscriptTests
{
	@Test func savedVoiceReplyReplacesBackendTextWithoutHidingOrdinaryChat()
	{
		let ordinary = entry(
			"ordinary:reply",
			.agent,
			"[COMPLETE] Literal text in a normal chat."
		)
		let question = entry(
			"voice:question",
			.user,
			"Explain A & B."
		)
		let backend = entry(
			"voice:reply",
			.agent,
			"[COMPLETE] A full explanation that was not read."
		)
		let status = entry(
			"voice:status",
			.agent,
			"[STATUS] Investigating."
		)
		let record = entry(
			"saved:context",
			.user,
			"""
			<realtime_delegation>
			  <source>transcript_tail_flush</source>
			  <input>Session ended.</input>
			  <transcript_delta>assistant: A &lt; B.
			Second line of the same utterance.</transcript_delta>
			</realtime_delegation>
			"""
		)

		let visible = VoiceChatTranscript.present(
			[ordinary, question, status, backend, record],
			segments: []
		)

		#expect(visible.map(\.body) == [
			ordinary.body,
			question.body,
			"A < B.\nSecond line of the same utterance.",
		])
		#expect(visible.map(\.kind) == [.agent, .user, .agent])
		#expect(visible.last?.id != backend.id)
	}

	@Test func legacyRecordKeepsSeparateSpokenMessagesFromEachSpeaker()
	{
		let record = entry(
			"saved:context",
			.user,
			"""
			<realtime_delegation>
			  <input></input>
			  <transcript_delta>user: Explain A &amp; B.
			assistant: A &lt; B.
			assistant: B is greater.</transcript_delta>
			</realtime_delegation>
			"""
		)
		let visible = VoiceChatTranscript.present(
			[record],
			segments: []
		)
		#expect(visible.map(\.body) == ["Explain A & B.", "A < B.", "B is greater."])
		#expect(visible.map(\.kind) == [.user, .agent, .agent])
		#expect(Set(visible.map(\.id)).count == 3)
		#expect(VoiceChatTranscript.present(
			[record],
			segments: []
		) == visible)
	}

	@Test func canonicalSpeechKeepsInlineMarkdownAndHidesItsPersistedMirror()
	{
		let question = entry(
			"voice:question",
			.user,
			"Show the answer."
		)
		let backend = entry(
			"voice:reply",
			.agent,
			"[COMPLETE] Here is the spoken summary."
		)
		let inline = entry(
			"voice:visible",
			.agent,
			"::codex-realtime-inline{}\n### Answer"
		)
		let record = entry(
			"voice:context",
			.user,
			"""
			<realtime_delegation>
			  <input></input>
			  <transcript_delta>assistant: The summary.</transcript_delta>
			</realtime_delegation>
			"""
		)
		let speech = VoiceChatSegment(
			id: "remote",
			isUser: false,
			text: "The summary.",
			precedingTurnID: "voice"
		)

		let visible = VoiceChatTranscript.present(
			[question, backend, inline, record],
			segments: [speech],
			hasCanonicalSpeech: true,
			historyTurnIDs: ["voice"]
		)
		#expect(visible.map(\.body) == [question.body, "### Answer", speech.text])
		#expect(visible.map(\.id) == [question.id, inline.id, speech.entry.id])
	}

	@Test func onlyVoiceTurnsHideBackendTrafficBeforeSpeechArrives()
	{
		let ordinary = entry(
			"other:reply",
			.agent,
			"[COMPLETE] Keep this."
		)
		let unanswered = entry(
			"voice:reply",
			.agent,
			"[COMPLETE] No speech yet."
		)
		let visible = VoiceChatTranscript.present(
			[ordinary, unanswered],
			segments: [],
			liveTurnIDs: ["voice"]
		)
		#expect(visible == [ordinary])
	}

	@Test func historicalSpeechStaysWithinItsOriginalTurnWindow()
	{
		let prompt = entry(
			"current:prompt",
			.user,
			"Current question."
		)
		let later = entry(
			"later:reply",
			.agent,
			"Later written reply."
		)
		let offscreenSpeech = VoiceChatSegment(
			id: "old",
			isUser: false,
			text: "Old reply.",
			precedingTurnID: "past"
		)
		let inWindowSpeech = VoiceChatSegment(
			id: "visible",
			isUser: false,
			text: "Current spoken reply.",
			precedingTurnID: "hidden-context"
		)
		let visible = VoiceChatTranscript.present(
			[prompt, later],
			segments: [offscreenSpeech, inWindowSpeech],
			historicalTurnOrder: ["past", "current", "hidden-context", "later"]
		)
		#expect(visible.map(\.body) == [prompt.body, inWindowSpeech.text, later.body])
	}

	private func entry(
		_ id: String,
		_ kind: ConversationEntryKind,
		_ body: String
	)
		-> ConversationEntry
	{
		ConversationEntry(
			id: id,
			kind: kind,
			title: "",
			body: body
		)
	}
}
