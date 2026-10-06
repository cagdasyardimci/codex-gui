import Foundation
import Testing

@testable import CodexGUI

@Suite("Project context search and navigation")
struct ProjectContextSearchTests
{
	@Test("Search shows loaded scope and stable references")
	func contentSearch() throws
	{
		let turn = try #require(
			CodexTurn(json: [
				"id": "turn-a",
				"status": "completed",
				"items": [
					[
						"id": "item-user",
						"type": "userMessage",
						"content": [["text": "Choose AppKit"]]
					],
					[
						"id": "item-agent",
						"type": "agentMessage",
						"text": "We chose AppKit for macOS."
					],
				],
			])
		)
		let thread = SearchableThread(
			threadID: "thread-a",
			title: "Architecture",
			turns: [turn],
			hasEarlierTurns: true
		)
		let results = MessageSearch.search(
			query: "appkit",
			threads: [thread],
			totalThreadCount: 3
		)

		#expect(results.hits.count == 2)
		#expect(results.hits[0].threadID == "thread-a")
		#expect(results.hits[0].turnID == "turn-a")
		#expect(results.hits[0].itemID == "item-user")
		#expect(results.scope.loadedThreadCount == 1)
		#expect(results.scope.totalThreadCount == 3)
		#expect(results.scope.threadsWithEarlierTurns == 1)
		#expect(results.scope.canLoadMore)
		#expect(results.scope.description.contains("earlier turns"))
	}

	@Test("Jump targets preserve item and changed-file references")
	func navigationReferences() throws
	{
		let turn = try #require(
			CodexTurn(json: [
				"id": "turn-a",
				"status": "failed",
				"error": ["message": "Request failed"],
				"items": [
					["id": "request", "type": "userMessage", "content": [["text": "Change file"]]],
					[
						"id": "patch",
						"type": "fileChange",
						"changes": [
							["path": "Sources/A.swift", "kind": "update", "diff": ""],
							["path": "Sources/B.swift", "kind": "update", "diff": ""],
						],
					],
				],
			])
		)
		let thread = SearchableThread(
			threadID: "thread-a",
			title: "Work",
			turns: [turn],
			hasEarlierTurns: false
		)
		let targets = ConversationNavigation.targets(in: thread)

		#expect(targets.count == 4)
		#expect(targets[0].itemID == "request")
		#expect(targets[1].itemID == "patch")
		#expect(targets[1].filePath == "Sources/A.swift")
		#expect(targets[2].filePath == "Sources/B.swift")
		#expect(targets[1].id != targets[2].id)
		#expect(targets[3].kind == .failure)
	}
}
