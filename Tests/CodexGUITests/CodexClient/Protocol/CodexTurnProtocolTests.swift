import Foundation
import Testing

@testable import CodexGUI

struct CodexTurnProtocolTests
{
	@Test func turnFixtureRetainsMessagesCommandsAndReportedFileDiff() throws
	{
		let fixture: [String: Any] = [
			"id": "turn-1",
			"status": "completed",
			"error": NSNull(),
			"items": [
				[
					"id": "user-1",
					"type": "userMessage",
					"content": [["type": "text", "text": "Update README"]],
				],
				[
					"id": "cmd-1",
					"type": "commandExecution",
					"command": "git status --short",
					"cwd": "/tmp/example",
					"aggregatedOutput": " M README.md\n",
					"status": "completed",
					"exitCode": 0,
					"durationMs": 125.5,
				],
				[
					"id": "change-1",
					"type": "fileChange",
					"status": "completed",
					"changes": [
						[
							"path": "README.md",
							"kind": "update",
							"diff": "@@ -1 +1 @@\n-old\n+new\n",
						]
					],
				],
			],
		]

		let turn = try #require(CodexTurn(json: fixture))
		#expect(turn.id == "turn-1")
		#expect(turn.items[0].text == "Update README")
		#expect(turn.items[1].command == "git status --short")
		#expect(turn.items[1].output == " M README.md\n")
		#expect(turn.items[1].exitCode == 0)
		#expect(turn.items[1].durationMs == 125.5)
		#expect(turn.items[2].changes[0].path == "README.md")
		#expect(turn.items[2].changes[0].diff == "@@ -1 +1 @@\n-old\n+new\n")
	}

}
