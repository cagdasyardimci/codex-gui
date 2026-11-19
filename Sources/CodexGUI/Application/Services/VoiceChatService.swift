import Foundation

struct VoiceChatSegment: Equatable
{
	let id: String
	let isUser: Bool
	var text: String
	var precedingTurnID: String?

	var entry: ConversationEntry
	{
		ConversationEntry(
			id: "voice-\(id)",
			kind: isUser ? .user : .agent,
			title: isUser ? "You" : "Codex",
			body: text
		)
	}

}

struct VoiceChatHistory
{
	var segments: [VoiceChatSegment] = []
	var voiceTurnIDs: Set<String> = []
	var orderedTurnIDs: [String] = []
}

enum VoiceChatEvent
{
	case started
	case sdp(String)
	case segment(VoiceChatSegment)
	case transcriptDelta(
		itemID: String,
		text: String
	)
	case legacyTranscript(
		isUser: Bool,
		text: String,
		isFinal: Bool
	)
	case audio(ReadAloudAudioChunk)
	case interrupted
	case failed(String)
	case closed
	case requestedStop
}
