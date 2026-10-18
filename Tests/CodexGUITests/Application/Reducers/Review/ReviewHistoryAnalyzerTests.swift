import Foundation
import Testing

@testable import CodexGUI

struct ReviewHistoryAnalyzerTests
{
	@Test func streamedFingerprintsPreserveUnicodeNULFieldsAndAbsentMoveIdentity() throws
	{
		let diff = "@@ -1,1024 +1,1024 @@\n" + String(
			repeating: "-é\n+e\u{301}\n",
			count: 1_024
		)
		for movePath in [nil, "", "B\u{0}e\u{301}.swift"] as [String?]
		{
			var kind: [String: Any] = ["type": "update\u{0}more"]
			kind["move_path"] = movePath
			let turn = try ReviewModelTestFixture.turn(
				"turn",
				items: [ReviewModelTestFixture.fileItem(
					"edit",
					changes: [["path": "A\u{0}é.swift", "kind": kind, "diff": diff]]
				)]
			)
			var cache: [String: ReviewParsedChanges] = [:]
			let reviews = ReviewAnalyzer.reviews(
				threadID: "thread",
				turns: [turn],
				parsedChanges: &cache
			)
			let review = try #require(reviews.first)
			let file = try #require(review.files.first)
			// Frozen digests use the previous serialized field and part separators.
			#expect(file.fingerprint == (movePath?.isEmpty == false
					? "6c0d617472b36db5" : "28d683beedde2704"))
			#expect(review.codeStateID == (movePath?.isEmpty == false
					? "4df8485d4c9eb67b" : "81b6c401c3e5deaa"))
		}
	}

	@Test func preservesKnownCodeStateFingerprintsAndCommandBoundaries() throws
	{
		let turns = try fixture()
		var cache: [String: ReviewParsedChanges] = [:]
		let reviews = ReviewAnalyzer.reviews(
			threadID: "thread-ç",
			turns: turns,
			parsedChanges: &cache
		)
		#expect(reviews.map(\.codeStateID) == [
			"d18c65727db86f75",
			"d18c65727db86f75",
			"ac6fc4f13c9fecc9",
			"ac6fc4f13c9fecc9"
		])
		#expect(reviews[0].files.first?.fingerprint == "11f2f82bd1ea3144")
		#expect(reviews[0].files.first?.hunks.first?.fingerprint == "79669e29718b7e69")
		#expect(reviews[0].validations.map(\.itemID) == [
			"before",
			"after",
			"failed",
			"unobserved",
			"before-rename"
		])
		#expect(reviews[0].validations.map(\.codeStateID) == [
			"3fe31bbaa9f61400",
			"d18c65727db86f75",
			"d18c65727db86f75",
			"d18c65727db86f75",
			"d18c65727db86f75"
		])
		#expect(reviews[0].validations.allSatisfy
		{
			$0.currency == .outdated
		})
		#expect(reviews[1].files.isEmpty)
		#expect(reviews[1].validations.map(\.outcome) == [.failed, .unobserved])
		#expect(reviews[2].validations.map(\.itemID) == [
			"before-rename",
			"after-rename",
			"after-all"
		])
		#expect(reviews[2].validations.map(\.codeStateID) == [
			"d18c65727db86f75",
			"359586d768ba1475",
			"ac6fc4f13c9fecc9"
		])
		#expect(reviews[2].validations.map(\.currency) == [.outdated, .outdated, .uncertain])
		#expect(reviews[3].validations.first?.outcome == .unknown)
		#expect(reviews[3].validations.first?.currency == .uncertain)
	}

	@Test func batchMatchesStandaloneAnalysisAcrossHistoryAndLiveChangeScopes() throws
	{
		let turns = try fixture()
		for hasEarlierHistory in [false, true]
		{
			for liveTurnID in [nil, "first", "middle", "edit", "last", "not-loaded"] as [String?]
			{
				var cache: [String: ReviewParsedChanges] = [:]
				let batch = ReviewAnalyzer.reviews(
					threadID: "thread-ç",
					turns: turns,
					hasEarlierHistory: hasEarlierHistory,
					liveChangeTurnID: liveTurnID,
					parsedChanges: &cache
				)
				let liveIndex = liveTurnID.map
				{
					id in
					turns.firstIndex(where:
						{
							$0.id == id
						}) ?? turns.count
				}
				let standalone = turns.enumerated().map
				{
					index, turn in
					ReviewAnalyzer.review(
						threadID: "thread-ç",
						turn: turn,
						earlierTurns: Array(turns.prefix(index)),
						laterTurns: Array(turns.dropFirst(index + 1)),
						hasEarlierHistory: hasEarlierHistory,
						hasLaterLiveChanges: liveIndex.map
						{
							$0 > index
						} ?? false
					)
				}
				#expect(batch == standalone)
			}
		}
	}

	@Test func partialHistoryKeepsPersistedDigestAndMarksEvidenceScope() throws
	{
		var cache: [String: ReviewParsedChanges] = [:]
		let reviews = ReviewAnalyzer.reviews(
			threadID: "thread-ç",
			turns: try fixture(),
			hasEarlierHistory: true,
			parsedChanges: &cache
		)
		#expect(reviews.map(\.codeStateID) == [
			"96f1a8e2f1e13c02",
			"96f1a8e2f1e13c02",
			"1fdaa43082d0887e",
			"1fdaa43082d0887e"
		])
		#expect(reviews.allSatisfy
		{
			$0.hasUnknownEarlierHistory
		})
		#expect(reviews.flatMap(\.validations).allSatisfy
		{
			$0.hasUnknownEarlierHistory
		})
	}

	@Test func cacheReusesFilesAcrossCommandChangesAndInvalidatesChangedDiffs() throws
	{
		var turns = try fixture()
		var cache: [String: ReviewParsedChanges] = [:]
		let original = ReviewAnalyzer.reviews(
			threadID: "thread-ç",
			turns: turns,
			parsedChanges: &cache
		)
		let originalParsed = try #require(cache["first"])
		turns[0] = try ReviewModelTestFixture.turn(
			"first",
			items: [
				command(
					"before",
					status: "failed"
				),
				firstChange(),
				command(
					"after",
					exitCode: 1
				),
			]
		)
		let changedCommand = ReviewAnalyzer.reviews(
			threadID: "thread-ç",
			turns: turns,
			parsedChanges: &cache
		)
		#expect(cache["first"] === originalParsed)
		#expect(changedCommand[0].files == original[0].files)
		#expect(changedCommand[0].validations[0].outcome == .failed)
		#expect(changedCommand[0].validations[1].outcome == .failed)
		turns[0] = try ReviewModelTestFixture.turn(
			"first",
			items: [firstChange(diff: "@@ -1 +1 @@\n-old\n+changed")]
		)
		let changedDiff = ReviewAnalyzer.reviews(
			threadID: "thread-ç",
			turns: turns,
			parsedChanges: &cache
		)
		#expect(cache["first"] !== originalParsed)
		#expect(changedDiff[0].files.first?.fingerprint != original[0].files.first?.fingerprint)
		#expect(changedDiff[3].codeStateID != original[3].codeStateID)
	}

	@Test func prependingHistoryReusesFilesButRecomputesCumulativeEvidence() throws
	{
		var turns = try fixture()
		var cache: [String: ReviewParsedChanges] = [:]
		let partial = ReviewAnalyzer.reviews(
			threadID: "thread-ç",
			turns: turns,
			hasEarlierHistory: true,
			parsedChanges: &cache
		)
		let cached = try #require(cache["first"])
		turns.insert(
			try ReviewModelTestFixture.turn(
				"earlier",
				items: [ReviewModelTestFixture.fileItem(
					"earlier-edit",
					path: "Earlier.swift",
					kind: "add",
					diff: "@@ -0,0 +1 @@\n+earlier"
				)]
			),
			at: 0
		)
		let complete = ReviewAnalyzer.reviews(
			threadID: "thread-ç",
			turns: turns,
			parsedChanges: &cache
		)
		#expect(cache["first"] === cached)
		#expect(complete[1].files == partial[0].files)
		#expect(complete[1].codeStateID != partial[0].codeStateID)
		#expect(!complete[1].hasUnknownEarlierHistory)
		#expect(complete[1] == ReviewAnalyzer.review(
			threadID: "thread-ç",
			turn: turns[1],
			earlierTurns: [turns[0]],
			laterTurns: Array(turns.dropFirst(2))
		))
		_ = ReviewAnalyzer.reviews(
			threadID: "thread-ç",
			turns: [turns[1]],
			parsedChanges: &cache
		)
		#expect(Set(cache.keys) == ["first"])
	}

	@Test func cachePreservesByteBasedIdentityAcrossEquivalentUnicodeText() throws
	{
		let composed = "@@ -1 +1 @@\n-old\n+é"
		let decomposed = "@@ -1 +1 @@\n-old\n+e\u{301}"
		#expect(composed == decomposed)
		var cache: [String: ReviewParsedChanges] = [:]
		let first = ReviewAnalyzer.reviews(
			threadID: "thread",
			turns: [try ReviewModelTestFixture.turn(
				"first",
				items: [firstChange(diff: composed)]
			)],
			parsedChanges: &cache
		)
		let cached = try #require(cache["first"])
		let next = ReviewAnalyzer.reviews(
			threadID: "thread",
			turns: [try ReviewModelTestFixture.turn(
				"first",
				items: [firstChange(diff: decomposed)]
			)],
			parsedChanges: &cache
		)
		#expect(cache["first"] !== cached)
		#expect(next[0].files.first?.fingerprint != first[0].files.first?.fingerprint)
		#expect(next[0].codeStateID != first[0].codeStateID)
	}

	@Test func completingAnEditReplacesTheEmptyCacheAndUpdatesEarlierCurrency() throws
	{
		let first = try ReviewModelTestFixture.turn(
			"first",
			items: [command(
				"check",
				exitCode: 0
			)]
		)
		var change = firstChange()
		change["status"] = "inProgress"
		var cache: [String: ReviewParsedChanges] = [:]
		let before = ReviewAnalyzer.reviews(
			threadID: "thread",
			turns: [first, try ReviewModelTestFixture.turn(
				"second",
				items: [change]
			)],
			parsedChanges: &cache
		)
		let cached = try #require(cache["second"])
		change["status"] = "completed"
		let after = ReviewAnalyzer.reviews(
			threadID: "thread",
			turns: [first, try ReviewModelTestFixture.turn(
				"second",
				items: [change]
			)],
			parsedChanges: &cache
		)
		#expect(cache["second"] !== cached)
		#expect(before[0].validations.first?.currency == .uncertain)
		#expect(after[0].validations.first?.currency == .outdated)
		#expect(before[1].files.isEmpty)
		#expect(after[1].files.count == 1)
	}

	private func fixture() throws -> [CodexTurn]
	{
		var unfinished = ReviewModelTestFixture.fileItem(
			"unfinished",
			path: "Ignored.swift",
			kind: "update",
			diff: "@@ -1 +1 @@\n-old\n+ignored"
		)
		unfinished["status"] = "inProgress"
		return try [
			ReviewModelTestFixture.turn(
				"first",
				items: [
					command(
						"before",
						exitCode: 0
					),
					firstChange(),
					command(
						"after",
						exitCode: 0
					)
				]
			),
			ReviewModelTestFixture.turn(
				"middle",
				items: [
					command(
						"failed",
						status: "failed"
					),
					unfinished,
					ReviewModelTestFixture.fileItem(
						"empty",
						changes: []
					),
					["id": "missing-command", "type": "commandExecution", "status": "completed"],
					command(
						"unobserved",
						status: "inProgress"
					),
				]
			),
			ReviewModelTestFixture.turn(
				"edit",
				items: [
					command(
						"before-rename",
						exitCode: 0
					),
					ReviewModelTestFixture.fileItem(
						"rename",
						changes: [[
							"path": "oldç.swift",
							"kind": ["type": "update", "move_path": "ç.swift"],
							"diff": "@@ -2 +2 @@\n-old\n+renamed",
						]]
					),
					command(
						"after-rename",
						exitCode: 1
					),
					ReviewModelTestFixture.fileItem(
						"late-edit",
						path: "C.swift",
						kind: "add",
						diff: "@@ -0,0 +1 @@\n+created"
					),
				]
			),
			ReviewModelTestFixture.turn(
				"last",
				items: [command(
					"after-all",
					output: "done"
				)]
			),
		]
	}

	private func firstChange(diff: String = "@@ -1 +1 @@\n-old\n+new") -> [String: Any]
	{
		ReviewModelTestFixture.fileItem(
			"first-edit",
			path: "A.swift",
			kind: "update",
			diff: diff
		)
	}

	private func command(
		_ id: String,
		exitCode: Int? = nil,
		output: String? = nil,
		status: String = "completed"
	) -> [String: Any]
	{
		var result: [String: Any] = [
			"id": id,
			"type": "commandExecution",
			"command": "check \(id)",
			"status": status
		]
		result["exitCode"] = exitCode
		result["aggregatedOutput"] = output
		return result
	}
}
