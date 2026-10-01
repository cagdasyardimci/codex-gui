import Foundation
import Testing

@testable import CodexGUI

struct ConversationActivityProtocolTests
{
	@Test func actionVariantsAndFutureActionsRetainCommandMetadata()
	{
		let item = CodexItem(json: [
			"id": "command",
			"type": "commandExecution",
			"command": "combined",
			"commandActions": [
				["type": "read", "command": "cat file", "name": "file", "path": "src/file"],
				["type": "search", "command": "rg needle", "query": "needle", "path": "src"],
				["type": "listFiles", "command": "ls", "path": NSNull()],
				["type": "unknown", "command": "build"],
				["type": "futureAction", "command": "future command"],
			]
		])!
		#expect(item.commandActions.map(\.kind) == [.read, .search, .listFiles, .unknown, .unknown])
		#expect(item.commandActions[0].name == "file")
		#expect(item.commandActions[0].path == "src/file")
		#expect(item.commandActions[1].query == "needle")
		#expect(item.commandActions[2].path == nil)
		#expect(item.commandActions[4].command == "future command")
		#expect(CodexCommandAction(json: ["type": "read"]) == nil)
	}

	@Test func imageAndTurnTimingDecodeUsingUnixSeconds()
	{
		let turn = CodexTurn(json: [
			"id": "turn",
			"status": "completed",
			"startedAt": 100,
			"completedAt": 103,
			"durationMs": 3_000,
			"items": [["id": "image", "type": "imageView", "path": "/tmp/image.png"]]
		])!
		#expect(turn.startedAt == Date(timeIntervalSince1970: 100))
		#expect(turn.completedAt == Date(timeIntervalSince1970: 103))
		#expect(turn.durationMs == 3_000)
		#expect(turn.items.first?.imagePath == "/tmp/image.png")
		#expect(CodexItem(json: [
			"id": "other",
			"type": "agentMessage",
			"path": "/tmp/image.png"
		])?.imagePath == nil)
		let absent = CodexTurn(json: ["id": "empty", "startedAt": NSNull()])!
		#expect(absent.startedAt == nil)
		#expect(absent.completedAt == nil)
		#expect(absent.durationMs == nil)
	}
}
