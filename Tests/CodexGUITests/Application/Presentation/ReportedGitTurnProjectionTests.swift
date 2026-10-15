import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ReportedGitTurnProjectionTests
{
	@Test func importedEditingIdentityIsSeededBeforeItsBodyIsEvicted()
	{
		var value = model()
		let turns = [turn(
			"editing",
			items: [fileItem("edit")]
		), turn("reply")]
		value.conversations.content[.thread("thread")] = ConversationContentModel(
			loadedTurns: turns,
			entries: ConversationContentReducer.entries(for: turns)
		)
		removeResidentTurn(
			"editing",
			from: &value
		)
		#expect(value.conversations.content[.thread("thread")]?.hasResolvedReportedGitTurn == true)
		#expect(snapshot(value).reportedGitTurnID == "editing")
		#expect(snapshot(value).reportedGitChanges == nil)
	}

	@Test func noEditImportedHistoryIsResolvedOnceWithoutPresentationDiscovery()
	{
		var value = model()
		value.conversations.content[.thread("thread")] = ConversationContentModel(
			loadedTurns: [turn("reply")]
		)
		ConversationContentReducer.updateContent(
			for: "thread",
			model: &value
		)
		{
			_ in
		}
		#expect(value.conversations.content[.thread("thread")]?.hasResolvedReportedGitTurn == true)
		for _ in 0 ..< 3
		{
			#expect(snapshot(value).reportedGitTurnID == nil)
			#expect(snapshot(value).reportedGitChanges == nil)
		}
		#expect(value.conversations.content[.thread("thread")]?.latestReportedGitTurn == nil)
	}

	@Test func laterRepliesRetainTheLatestCompletedEditingTurn()
	{
		var value = model()
		merge(
			[
				turn(
					"z-earlier",
					items: [fileItem(
						"old",
						path: "old.swift"
					)]
				),
				turn(
					"a-edit",
					items: [fileItem(
						"edit",
						path: "latest.swift"
					)]
				),
				turn("reply"),
			],
			into: &value
		)
		let snapshot = snapshot(value)
		#expect(snapshot.lastGitTurnID == "reply")
		#expect(snapshot.lastReportedGitTurn?.id == "a-edit")
		#expect(snapshot.reportedGitChanges?.map(\.path) == ["latest.swift"])
	}

	@Test func cacheEvictionRetainsEditingIdentityAndUnavailablePayload()
	{
		var value = model()
		let turns = (0 ..< 80).map
		{
			index in
			turn(
				"turn-\(index)",
				items: index == 3 ? [fileItem(
					"edit",
					path: "latest.swift"
				)] : []
			)
		}
		merge(
			turns,
			into: &value
		)
		value.conversations.turnReferenceIndices["thread"] = TurnReferenceIndex(
			references: turns.map
			{
				ConversationTurnReference(
					id: $0.id,
					status: $0.status
				)
			},
			access: Dictionary(uniqueKeysWithValues: turns.enumerated().map
			{
				($0.element.id, $0.offset)
			})
		)
		ConversationReducer.enforceCacheLimits(model: &value)
		#expect(value.conversations.content[.thread("thread")]?.loadedTurns
			.contains(where:
				{
					$0.id == "turn-3"
				}) == false)
		let snapshot = snapshot(value)
		#expect(snapshot.lastReportedGitTurn?.id == "turn-3")
		#expect(snapshot.lastReportedGitTurn?.changes == nil)
		#expect(snapshot.reportedGitChanges == nil)
	}

	@Test func anOlderResidentEditingTurnNeverSubstitutesForTheEvictedLatestEdit()
	{
		var value = model()
		merge(
			[
				turn(
					"old",
					items: [fileItem(
						"old",
						path: "old.swift"
					)]
				),
				turn(
					"latest",
					items: [fileItem(
						"latest",
						path: "latest.swift"
					)]
				),
				turn("reply"),
			],
			into: &value
		)
		removeResidentTurn(
			"latest",
			from: &value
		)
		#expect(snapshot(value).reportedGitTurnID == "latest")
		#expect(snapshot(value).reportedGitChanges == nil)
		// Unknown dates and a missing reference index provide no proof that an insertion is newer.
		ConversationContentReducer.updateContent(
			for: "thread",
			model: &value
		)
		{
			$0.loadedTurns.insert(
				turn(
					"older-page",
					items: [fileItem("page")]
				),
				at: 0
			)
			$0.entries = ConversationContentReducer.entries(for: $0.loadedTurns)
		}
		#expect(snapshot(value).reportedGitTurnID == "latest")
		#expect(snapshot(value).reportedGitChanges == nil)
	}

	@Test func trustedReferenceOrderAdvancesAnEditingIdentityWithoutItsOldBody()
	{
		var value = model()
		merge(
			[turn(
				"z-old",
				items: [fileItem("old")]
			)],
			into: &value
		)
		removeResidentTurn(
			"z-old",
			from: &value
		)
		value.conversations.turnReferenceIndices["thread"] = TurnReferenceIndex(references: [
			ConversationTurnReference(
				id: "z-old",
				status: "completed"
			),
			ConversationTurnReference(
				id: "a-new",
				status: "completed"
			),
		])
		ConversationContentReducer.updateContent(
			for: "thread",
			model: &value
		)
		{
			$0.loadedTurns.append(turn(
				"a-new",
				items: [fileItem(
					"new",
					path: "new.swift"
				)]
			))
			$0.entries = ConversationContentReducer.entries(for: $0.loadedTurns)
		}
		#expect(snapshot(value).reportedGitTurnID == "a-new")
		#expect(snapshot(value).reportedGitChanges?.map(\.path) == ["new.swift"])
	}

	@Test func olderOrUndatedHistoryCannotRollBackCanonicalEditingIdentity()
	{
		var value = model()
		merge(
			[turn(
				"latest",
				items: [fileItem("latest")],
				startedAt: 20
			)],
			into: &value
		)
		merge(
			[turn(
				"old",
				items: [fileItem("old")],
				startedAt: 10
			)],
			into: &value
		)
		#expect(snapshot(value).reportedGitTurnID == "latest")
		#expect(snapshot(value).reportedGitChanges == nil)
		merge(
			[turn(
				"undated",
				items: [fileItem("undated")]
			)],
			into: &value
		)
		#expect(snapshot(value).reportedGitTurnID == "latest")
		#expect(snapshot(value).reportedGitChanges == nil)
	}

	@Test func liveCompletedItemsAggregateAndProposalsDoNotAdvanceSelection()
	{
		var value = model()
		merge(
			[turn(
				"old",
				items: [fileItem("old")]
			)],
			into: &value
		)
		ConversationContentReducer.observe(
			.turnStarted(
				threadId: "thread",
				turn: turn(
					"live",
					status: "inProgress"
				)
			),
			model: &value
		)
		ConversationContentReducer.observe(
			.itemStarted(
				threadId: "thread",
				turnId: "live",
				item: fileItem(
					"proposal",
					status: "inProgress"
				)
			),
			model: &value
		)
		#expect(snapshot(value).reportedGitTurnID == "old")
		let first = fileItem(
			"first",
			path: "first.swift"
		)
		let second = fileItem(
			"second",
			path: "second.swift"
		)
		for item in [first, second]
		{
			ConversationContentReducer.observe(
				.itemCompleted(
					threadId: "thread",
					turnId: "live",
					item: item
				),
				model: &value
			)
		}
		#expect(snapshot(value).reportedGitTurnID == "live")
		#expect(snapshot(value).reportedGitChanges?.map(\.path) == ["first.swift", "second.swift"])
		ConversationContentReducer.observe(
			.turnCompleted(
				threadId: "thread",
				turn: turn(
					"live",
					items: [first, second]
				)
			),
			model: &value
		)
		ConversationContentReducer.observe(
			.turnCompleted(
				threadId: "thread",
				turn: turn("reply")
			),
			model: &value
		)
		#expect(snapshot(value).reportedGitTurnID == "live")
		#expect(snapshot(value).reportedGitChanges?.map(\.path) == ["first.swift", "second.swift"])
	}

	@Test func lateUnorderedOldCompletionCannotReplaceANewerRecordedEdit()
	{
		var value = model()
		ConversationContentReducer.observe(
			.turnStarted(
				threadId: "thread",
				turn: turn(
					"latest",
					status: "inProgress"
				)
			),
			model: &value
		)
		ConversationContentReducer.observe(
			.turnCompleted(
				threadId: "thread",
				turn: turn(
					"latest",
					items: [fileItem("latest")]
				)
			),
			model: &value
		)
		ConversationContentReducer.observe(
			.turnCompleted(
				threadId: "thread",
				turn: turn(
					"old",
					items: [fileItem("old")]
				)
			),
			model: &value
		)
		ConversationContentReducer.observe(
			.turnCompleted(
				threadId: "thread",
				turn: turn(
					"old",
					items: [fileItem("old")]
				)
			),
			model: &value
		)
		ConversationContentReducer.observe(
			.turnCompleted(
				threadId: "thread",
				turn: turn("reply")
			),
			model: &value
		)
		ConversationContentReducer.observe(
			.turnCompleted(
				threadId: "thread",
				turn: turn(
					"old",
					items: [fileItem("old")]
				)
			),
			model: &value
		)
		#expect(snapshot(value).reportedGitTurnID == "latest")
		#expect(snapshot(value).reportedGitChanges?.count == 1)
	}

	@Test func partialItemHistoryStaysUnavailableThroughItemReplacement()
	{
		var value = model()
		merge(
			[turn(
				"partial",
				items: [fileItem("first")],
				itemsAreComplete: false
			)],
			into: &value
		)
		#expect(snapshot(value).reportedGitTurnID == "partial")
		#expect(snapshot(value).reportedGitChanges == nil)
		ConversationContentReducer.observe(
			.itemCompleted(
				threadId: "thread",
				turnId: "partial",
				item: fileItem("second")
			),
			model: &value
		)
		#expect(value.conversations.content[.thread("thread")]?.loadedTurns.first?
			.itemsAreComplete == false)
		#expect(snapshot(value).reportedGitChanges == nil)
		merge(
			[turn(
				"partial",
				items: [fileItem("first"), fileItem("second")]
			)],
			into: &value
		)
		#expect(snapshot(value).reportedGitChanges?.count == 2)
	}

	@Test func completedEmptyRecordedChangesAreDistinctFromUnavailableChanges()
	{
		var value = model()
		merge(
			[turn(
				"empty",
				items: [fileItem(
					"empty",
					changes: []
				)]
			)],
			into: &value
		)
		#expect(snapshot(value).reportedGitTurnID == "empty")
		#expect(snapshot(value).reportedGitChanges == [])
		removeResidentTurn(
			"empty",
			from: &value
		)
		#expect(snapshot(value).reportedGitTurnID == "empty")
		#expect(snapshot(value).reportedGitChanges == nil)
	}

	@Test func baselineFailureAndReportedIdentityStayWithTheirConversation()
	{
		var value = model()
		merge(
			[turn(
				"editing",
				items: [fileItem("edit")]
			), turn("reply")],
			into: &value
		)
		let failure = GitComparisonFailure
			.lastTurnBaselineUnavailable("Captured files exceed the configured limit.")
		value.execution.gitTurnBaselineBindings["thread"] = GitTurnBaselineBindingStatus(
			context: OperationContext(
				workspace: value.identity,
				generation: value.connection.generation,
				requestID: UUID(),
				threadID: "thread",
				turnID: "editing"
			),
			turnID: "editing",
			result: .unavailable(failure)
		)
		removeResidentTurn(
			"editing",
			from: &value
		)
		#expect(snapshot(value).gitTurnBaselineFailure == failure)
		value.conversations.selectedConversation = .thread("other")
		#expect(snapshot(value).reportedGitTurnID == nil)
		#expect(snapshot(value).reportedGitChanges == nil)
		#expect(snapshot(value).gitTurnBaselineFailure == nil)
	}

	@Test func duplicateItemReportsUseTheirLatestPayloadOnly()
	{
		var value = model()
		merge(
			[turn(
				"editing",
				items: [
					fileItem(
						"same-item",
						path: "outdated.swift"
					),
					fileItem(
						"same-item",
						path: "current.swift"
					),
				]
			)],
			into: &value
		)
		#expect(snapshot(value).reportedGitChanges?.map(\.path) == ["current.swift"])
	}

	@Test func anotherTaskOrSubagentThreadCannotContributeToTheSelectedTasksReports()
	{
		var value = model()
		merge(
			[turn(
				"editing",
				items: [fileItem(
					"parent",
					path: "parent.swift"
				)]
			)],
			into: &value
		)
		ConversationContentReducer.observe(
			.itemCompleted(
				threadId: "child-thread",
				turnId: "child-turn",
				item: fileItem(
					"child",
					path: "child.swift"
				)
			),
			model: &value
		)
		ConversationContentReducer.observe(
			.itemCompleted(
				threadId: "unrelated-task",
				turnId: "editing",
				item: fileItem(
					"unrelated",
					path: "unrelated.swift"
				)
			),
			model: &value
		)
		#expect(snapshot(value).reportedGitChanges?.map(\.path) == ["parent.swift"])
	}

	@Test func reportedChangesPreserveItemAndWithinItemOrderAfterDeduplication()
	{
		let content = ConversationContentModel(
			loadedTurns: [turn(
				"editing",
				items: [
					fileItem(
						"same",
						path: "obsolete.swift"
					),
					fileItem(
						"first",
						changes: [
							["path": "first-a.swift", "kind": "update"],
							["path": "first-b.swift", "kind": "update"],
						]
					),
					fileItem(
						"same",
						path: "current.swift"
					),
					fileItem(
						"last",
						path: "last.swift"
					),
				]
			)],
			latestReportedGitTurn: ConversationReportedGitTurn(id: "editing")
		)
		#expect(ConversationReportedGitTurnProjection(content: content).changes?.map(\.path)
			== ["first-a.swift", "first-b.swift", "current.swift", "last.swift"])
	}

	@Test func laterNonReportDuplicateSuppressesAnEarlierCanonicalReport()
	{
		let replacement = CodexItem(json: [
			"id": "same",
			"type": "agentMessage",
			"text": "Replaced",
		])!
		let content = ConversationContentModel(
			loadedTurns: [turn(
				"editing",
				items: [fileItem("same"), replacement]
			)],
			latestReportedGitTurn: ConversationReportedGitTurn(id: "editing")
		)
		#expect(ConversationReportedGitTurnProjection(content: content).changes == nil)
	}

	@Test func provisionalReportsDeduplicateOnlyCompletedReportsAndPreserveOrder()
	{
		let first = fileItem(
			"first",
			changes: [
				["path": "first-a.swift", "kind": "update"],
				["path": "first-b.swift", "kind": "update"],
			]
		)
		let items = [
			fileItem(
				"same",
				path: "obsolete.swift"
			),
			first,
			fileItem(
				"same",
				path: "current.swift"
			),
			fileItem(
				"same",
				path: "proposed.swift",
				status: "inProgress"
			),
		]
		let content = ConversationContentModel(
			latestReportedGitTurn: ConversationReportedGitTurn(id: "editing"),
			entries: items.map
			{
				ConversationContentReducer.entry(
					for: $0,
					id: "editing:" + $0.id
				)
			}
		)
		#expect(ConversationReportedGitTurnProjection(content: content).changes?.map(\.path)
			== ["first-a.swift", "first-b.swift", "current.swift"])
	}

	private func model() -> WorkspaceModel
	{
		var value = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/reported-git-turn"
		))
		value.conversations.selectedConversation = .thread("thread")
		return value
	}

	private func snapshot(_ value: WorkspaceModel) -> ConversationSnapshot
	{
		WorkspaceSelectors(
			model: value,
			now: .distantPast
		).makeSnapshot()
	}

	private func merge(
		_ turns: [CodexTurn],
		into value: inout WorkspaceModel
	)
	{
		ConversationContentReducer.merge(
			ThreadDetail(
				summary: ThreadSummary(json: ["id": "thread", "cwd": "/tmp/reported-git-turn"])!,
				turns: turns,
				nextTurnsCursor: nil
			),
			model: &value
		)
	}

	private func removeResidentTurn(
		_ id: String,
		from value: inout WorkspaceModel
	)
	{
		ConversationContentReducer.updateContent(
			for: "thread",
			model: &value
		)
		{
			$0.loadedTurns.removeAll
			{
				$0.id == id
			}
			$0.entries.removeAll
			{
				$0.id.hasPrefix(id + ":")
			}
		}
	}

	private func turn(
		_ id: String,
		items: [CodexItem] = [],
		status: String = "completed",
		startedAt: TimeInterval? = nil,
		itemsAreComplete: Bool = true
	) -> CodexTurn
	{
		CodexTurn(
			id: id,
			status: status,
			items: items,
			error: nil,
			startedAt: startedAt.map
			{
				Date(timeIntervalSince1970: $0)
			},
			itemsAreComplete: itemsAreComplete
		)
	}

	private func fileItem(
		_ id: String,
		path: String = "file.swift",
		status: String = "completed",
		changes: [[String: Any]]? = nil
	) -> CodexItem
	{
		CodexItem(json: [
			"id": id,
			"type": "fileChange",
			"status": status,
			"changes": changes ?? [[
				"path": path,
				"kind": "update",
				"diff": "@@ -1 +1 @@\n-old\n+new\n",
			]],
		])!
	}
}
