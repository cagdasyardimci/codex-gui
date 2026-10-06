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

	@Test func classifiesRenameDeletionBinaryAndUnsupportedChanges() throws
	{
		let turn = try ReviewModelTestFixture.turn(
			"turn-special",
			items: [
				ReviewModelTestFixture.fileItem(
					"changes",
					changes: [
						[
							"path": "old.swift",
							"kind": [
								"type": "update",
								"move_path": "new.swift"
							],
							"diff":
								"diff --git a/old.swift b/new.swift\nrename from "
								+ "old.swift\nrename to new.swift\n@@ -1 +1 @@\n-a\n+b",
						],
						[
							"path": "gone.swift",
							"kind": ["type": "delete"],
							"diff": "deleted file mode 100644\n@@ -1 +0,0 @@\n-old",
						],
						[
							"path": "asset.png",
							"kind": ["type": "update"],
							"diff": "Binary files a/asset.png and b/asset.png differ",
						],
						["path": "mystery", "kind": ["type": "unusual"], "diff": "opaque change"],
					]
				)
			]
		)
		let files = ReviewAnalyzer.review(
			threadID: "thread",
			turn: turn,
			laterTurns: []
		).files

		#expect(files.map(\.kind) == [.renamed, .deleted, .binary, .unsupported])
		#expect(files[0].previousPath == "old.swift")
		#expect(files[0].displayName == "old.swift → new.swift")
		#expect(files[1].hunks.count == 1)
		#expect(files[2].hunks.isEmpty)
		#expect(files[2].explanation?.contains("Binary") == true)
		#expect(files[3].explanation?.contains("Unsupported") == true)
	}

	@Test func quotedRenameMetadataUsesCanonicalUnicodeIdentityAndSeparateHunks() throws
	{
		let rename = #"""
		diff --git "a/old\303\247.swift" "b/\303\247.swift"
		rename from "old\303\247.swift"
		rename to "\303\247.swift"
		@@ -1 +1 @@
		-old
		+new
		"""#
		let followup = """
		diff --git a/ç.swift b/ç.swift
		@@ -5 +5 @@
		-old
		+later
		"""
		let reported = try ReviewModelTestFixture.turn(
			"turn",
			items: [
				ReviewModelTestFixture.fileItem(
					"move",
					changes: [
						[
							"path": "oldç.swift",
							"kind": [
								"type": "update",
								"move_path": "ç.swift"
							],
							"diff": rename,
						]
					]
				),
				ReviewModelTestFixture.fileItem(
					"followup",
					path: "ç.swift",
					kind: "update",
					diff: followup
				),
			]
		)
		let file = try #require(
			ReviewAnalyzer.review(
				threadID: "thread",
				turn: reported,
				laterTurns: []
			).files.first
		)
		#expect(file.path == "ç.swift")
		#expect(file.previousPath == "oldç.swift")
		#expect(file.displayName == "oldç.swift → ç.swift")
		#expect(file.hunks.count == 2)
		#expect(!file.hunks[0].text.contains("diff --git"))
		#expect(!file.hunks[0].text.contains("+later"))
		let selected = GitDiffParser.selectedDiff(
			for: file.path,
			in: file.diff
		)
		#expect(selected.contains("+new"))
		#expect(selected.contains("+later"))
	}

	@Test func successiveEditsToOnePathProduceOneReviewFile() throws
	{
		let turn = try ReviewModelTestFixture.turn(
			"turn",
			items: [
				ReviewModelTestFixture.fileItem(
					"first",
					path: "A.swift",
					kind: "update",
					diff: "@@ -1 +1 @@\n-a\n+b"
				),
				ReviewModelTestFixture.fileItem(
					"second",
					path: "A.swift",
					kind: "update",
					diff: "@@ -4 +4 @@\n-c\n+d"
				),
			]
		)
		let files = ReviewAnalyzer.review(
			threadID: "thread",
			turn: turn,
			laterTurns: []
		).files

		#expect(files.count == 1)
		#expect(files[0].hunks.count == 2)
		#expect(files[0].diff.contains("+b"))
		#expect(files[0].diff.contains("+d"))
	}

	@Test func movePathWithoutDiffMetadataIdentifiesSourceAndDestination() throws
	{
		let turn = try ReviewModelTestFixture.turn(
			"turn",
			items: [
				ReviewModelTestFixture.fileItem(
					"move",
					changes: [
						[
							"path": "A.swift",
							"kind": ["type": "update", "move_path": "B.swift"],
							"diff": "@@ -1 +1 @@\n-old\n+new",
						]
					]
				)
			]
		)
		let file = try #require(
			ReviewAnalyzer.review(
				threadID: "thread",
				turn: turn,
				laterTurns: []
			).files.first
		)

		#expect(file.kind == .renamed)
		#expect(file.previousPath == "A.swift")
		#expect(file.path == "B.swift")
		#expect(file.reportedMovePath == "B.swift")
		#expect(file.displayName == "A.swift → B.swift")
	}

	@Test func moveAndFollowingDestinationEditShareOneFile() throws
	{
		let turn = try ReviewModelTestFixture.turn(
			"turn",
			items: [
				ReviewModelTestFixture.fileItem(
					"move",
					changes: [
						[
							"path": "A.swift",
							"kind": ["type": "update", "move_path": "B.swift"],
							"diff": "@@ -1 +1 @@\n-old\n+new",
						]
					]
				),
				ReviewModelTestFixture.fileItem(
					"followup",
					path: "B.swift",
					kind: "update",
					diff: "@@ -2 +2 @@\n-x\n+y"
				),
			]
		)
		let files = ReviewAnalyzer.review(
			threadID: "thread",
			turn: turn,
			laterTurns: []
		).files

		#expect(files.count == 1)
		#expect(files[0].displayName == "A.swift → B.swift")
		#expect(files[0].hunks.count == 2)
	}

	@Test func validationNeedsObservedExitAndBecomesOutdatedAfterReportedEdit() throws
	{
		let turn = try ReviewModelTestFixture.turn(
			"turn-1",
			items: [
				ReviewModelTestFixture.fileItem(
					"edit-1",
					path: "A.swift",
					kind: "update",
					diff: "@@ -1 +1 @@\n-a\n+b"
				),
				commandItem(
					"test",
					command: "swift test",
					output: "2 tests passed",
					exitCode: 0
				),
				commandItem(
					"unknown",
					command: "custom-check",
					output: "done"
				),
				ReviewModelTestFixture.fileItem(
					"edit-2",
					path: "A.swift",
					kind: "update",
					diff: "@@ -1 +1 @@\n-b\n+c"
				),
				commandItem(
					"failure",
					command: "swift test",
					output: "failed",
					exitCode: 1
				),
			]
		)
		let review = ReviewAnalyzer.review(
			threadID: "thread",
			turn: turn,
			laterTurns: []
		)

		#expect(review.validations.map(\.outcome) == [.succeeded, .unknown, .failed])
		#expect(review.validations.map(\.currency) == [.outdated, .outdated, .uncertain])
		#expect(review.validations[0].output == "2 tests passed")
		#expect(review.validations[0].codeStateID != review.codeStateID)
		#expect(review.validations[2].codeStateID == review.codeStateID)
		#expect(review.validations[2].scopeDescription.contains("unknown"))
	}

	@Test func laterTurnEditOutdatesEarlierValidationAndPendingResultIsUnobserved() throws
	{
		let earlier = try ReviewModelTestFixture.turn(
			"turn-1",
			items: [commandItem(
				"pending",
				command: "swift test",
				status: "inProgress"
			)]
		)
		let later = try ReviewModelTestFixture.turn(
			"turn-2",
			items: [ReviewModelTestFixture.fileItem(
				"edit",
				path: "A.swift",
				kind: "update",
				diff: "@@ -1 +1 @@\n-a\n+b"
			)]
		)
		let result = ReviewAnalyzer.review(
			threadID: "thread",
			turn: earlier,
			laterTurns: [later]
		)

		#expect(result.validations.first?.outcome == .unobserved)
		#expect(result.validations.first?.currency == .outdated)
	}

	@Test func laterCommandCanValidateEarlierReportedStateWithoutProvingCoverage() throws
	{
		let edit = try ReviewModelTestFixture.turn(
			"turn-A",
			items: [ReviewModelTestFixture.fileItem(
				"edit",
				path: "A.swift",
				kind: "update",
				diff: "@@ -1 +1 @@\n-a\n+b"
			)]
		)
		let check = try ReviewModelTestFixture.turn(
			"turn-B",
			items: [commandItem(
				"test",
				command: "swift test",
				output: "passed",
				exitCode: 0
			)]
		)

		let editReview = ReviewAnalyzer.review(
			threadID: "thread",
			turn: edit,
			laterTurns: [check]
		)
		let checkReview = ReviewAnalyzer.review(
			threadID: "thread",
			turn: check,
			earlierTurns: [edit],
			laterTurns: []
		)
		let evidence = try #require(editReview.validations.first)

		#expect(evidence.turnID == "turn-B")
		#expect(evidence.outcome == .succeeded)
		#expect(evidence.currency == .uncertain)
		#expect(evidence.codeStateID == editReview.codeStateID)
		#expect(evidence.codeStateID == checkReview.validations.first?.codeStateID)
		#expect(evidence.scopeDescription.contains("not verified repository contents"))
	}

	@Test func commandAfterLaterEditIsNotAttachedToEarlierReview() throws
	{
		let edit = try ReviewModelTestFixture.turn(
			"turn-A",
			items: [ReviewModelTestFixture.fileItem(
				"first",
				path: "A.swift",
				kind: "update",
				diff: "@@ -1 +1 @@\n-a\n+b"
			)]
		)
		let later = try ReviewModelTestFixture.turn(
			"turn-B",
			items: [
				ReviewModelTestFixture.fileItem(
					"second",
					path: "A.swift",
					kind: "update",
					diff: "@@ -1 +1 @@\n-b\n+c"
				),
				commandItem(
					"test",
					command: "swift test",
					output: "passed",
					exitCode: 0
				),
			]
		)
		let review = ReviewAnalyzer.review(
			threadID: "thread",
			turn: edit,
			laterTurns: [later]
		)

		#expect(review.validations.isEmpty)
	}

	@Test func laterLiveChangeOutdatesEarlierCommandImmediately() throws
	{
		let turn = try ReviewModelTestFixture.turn(
			"turn-A",
			items: [commandItem(
				"test",
				command: "swift test",
				output: "passed",
				exitCode: 0
			)]
		)
		let beforeEdit = ReviewAnalyzer.review(
			threadID: "thread",
			turn: turn,
			laterTurns: []
		)
		let afterLiveEdit = ReviewAnalyzer.review(
			threadID: "thread",
			turn: turn,
			laterTurns: [],
			hasLaterLiveChanges: true
		)

		#expect(beforeEdit.validations.first?.currency == .uncertain)
		#expect(afterLiveEdit.validations.first?.currency == .outdated)
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
