import Foundation
import Testing

@testable import CodexGUI

enum ReviewModelTestFixture
{
	static func reviewFile(diff: String) throws -> ReviewFile
	{
		let reviewedTurn = try turn(
			"turn",
			items: [fileItem(
				"edit",
				path: "A.swift",
				kind: "update",
				diff: diff
			)]
		)
		let review = ReviewAnalyzer.review(
			threadID: "thread",
			turn: reviewedTurn,
			laterTurns: []
		)
		return try #require(review.files.first)
	}

	static func turn(
		_ id: String,
		items: [[String: Any]]
	) throws -> CodexTurn
	{
		try #require(CodexTurn(json: ["id": id, "status": "completed", "items": items]))
	}

	static func fileItem(
		_ id: String,
		path: String,
		kind: String,
		diff: String
	) -> [String: Any]
	{
		fileItem(
			id,
			changes: [["path": path, "kind": ["type": kind], "diff": diff]]
		)
	}

	static func fileItem(
		_ id: String,
		changes: [[String: Any]]
	) -> [String: Any]
	{
		["id": id, "type": "fileChange", "status": "completed", "changes": changes]
	}

}
