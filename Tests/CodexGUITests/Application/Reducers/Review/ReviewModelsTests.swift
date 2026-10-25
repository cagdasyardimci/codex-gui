import Foundation
import Testing

@testable import CodexGUI

struct ReviewModelsTests
{
	@Test func preservesOriginAndFullHunkContextAcrossTurns() throws
	{
		let longLine = String(
			repeating: "a",
			count: 500
		)
		let earlier = try ReviewModelTestFixture.turn(
			"turn-1",
			items: [
				ReviewModelTestFixture.fileItem(
					"file-1",
					path: "Sources/name with spaces.swift",
					kind: "update",
					diff: "@@ -8,1 +8,1 @@ function\n-old\n+\(longLine)\n"
				)
			]
		)
		let later = try ReviewModelTestFixture.turn(
			"turn-2",
			items: [ReviewModelTestFixture.fileItem(
				"file-2",
				path: "other.swift",
				kind: "add",
				diff: "@@ -0,0 +1 @@\n+x"
			)]
		)

		let review = ReviewAnalyzer.review(
			threadID: "thread-A",
			turn: earlier,
			laterTurns: [later]
		)
		let file = try #require(review.files.first)
		let hunk = try #require(file.hunks.first)
		let reference = ReviewReference(
			threadID: review.threadID,
			turnID: review.turnID,
			file: file,
			hunk: hunk
		)
		let prompt = reference.prompt(
			for: .revision,
			file: file,
			hunk: hunk
		)

		#expect(review.threadID == "thread-A")
		#expect(review.turnID == "turn-1")
		#expect(hunk.text.contains(longLine))
		#expect(prompt.contains("Origin thread: thread-A"))
		#expect(prompt.contains("Origin turn: turn-1"))
		#expect(prompt.contains("File: Sources/name with spaces.swift"))
		#expect(prompt.contains(longLine))
	}

	@Test func unknownEarlierHistoryIsExplicitInCodeStateEvidence() throws
	{
		let turn = try ReviewModelTestFixture.turn(
			"turn-B",
			items: [commandItem(
				"test",
				command: "swift test",
				exitCode: 0
			)]
		)
		let partial = ReviewAnalyzer.review(
			threadID: "thread",
			turn: turn,
			laterTurns: [],
			hasEarlierHistory: true
		)
		let complete = ReviewAnalyzer.review(
			threadID: "thread",
			turn: turn,
			laterTurns: []
		)

		#expect(partial.hasUnknownEarlierHistory)
		#expect(partial.codeStateID != complete.codeStateID)
		#expect(partial.validations.first?.scopeDescription.contains("Earlier turns") == true)
	}

	private func commandItem(
		_ id: String,
		command: String,
		output: String? = nil,
		exitCode: Int? = nil,
		status: String = "completed"
	) -> [String: Any]
	{
		var item: [String: Any] = [
			"id": id,
			"type": "commandExecution",
			"status": status,
			"command": command,
		]
		item["aggregatedOutput"] = output
		item["exitCode"] = exitCode
		return item
	}
}
