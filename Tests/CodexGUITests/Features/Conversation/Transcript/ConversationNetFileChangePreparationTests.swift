import Foundation
import Testing

@testable import CodexGUI

struct ConversationNetFileChangePreparationTests
{
	@Test func unchangedTurnsReusePreparationAndOnlyChangedContentIsRecomputed() async
	{
		let probe = Probe()
		let cache = preparation(probe: probe)
		let first = source(
			"first",
			after: "first-result"
		)
		let second = source(
			"second",
			after: "second-result"
		)
		let initial = await cache.prepare(
			[first, second],
			context: "thread"
		)
		#expect(await probe.calls == 2)
		let unchanged = await cache.prepare(
			[first, second],
			context: "thread"
		)
		#expect(unchanged == initial)
		#expect(await probe.calls == 2)
		let revised = source(
			"second",
			after: "revised-result"
		)
		let updated = await cache.prepare(
			[first, revised],
			context: "thread"
		)
		#expect(updated?[first.turnID] == initial?[first.turnID])
		#expect(updated?[revised.turnID]?.source == revised)
		#expect(await probe.calls == 3)
	}

	@Test func canonicallyEquivalentStringsAreDifferentPreparationInputs() async
	{
		let probe = Probe()
		let cache = preparation(probe: probe)
		let composed = source(
			"turn",
			after: "\u{00E9}"
		)
		let decomposed = source(
			"turn",
			after: "e\u{0301}"
		)
		#expect(composed.changes == decomposed.changes)
		#expect(composed != decomposed)
		let initial = await cache.prepare(
			[composed],
			context: "thread"
		)
		#expect(initial?["turn"]?.matches(decomposed.changes) == false)
		let revised = await cache.prepare(
			[decomposed],
			context: "thread"
		)
		#expect(await probe.calls == 2)
		#expect(revised?["turn"]?.matches(decomposed.changes) == true)
		#expect(revised?["turn"]?.changes.first?.diff.utf8.elementsEqual(
			"@@ -1,1 +1,1 @@\n-before\n+e\u{0301}".utf8
		) == true)
	}

	@Test func exactGuardsIncludePathKindRenameAndOptionalMetadata()
	{
		let original = change(diff: "@@ -1 +1 @@\n-a\n+b")
		let prepared = ConversationNetFileChangePreparation.Prepared(
			source: ConversationNetFileChangePreparation.Source(
				turnID: "turn",
				changes: [original]
			),
			changes: [original]
		)
		#expect(prepared.matches([original]))
		#expect(!prepared.matches([]))
		#expect(!prepared.matches([change(
			path: "different",
			diff: original.diff
		)]))
		#expect(!prepared.matches([change(
			kind: "add",
			diff: original.diff
		)]))
		#expect(!prepared.matches([change(
			movePath: "",
			diff: original.diff
		)]))
		#expect(!prepared.matches([change(
			movePath: "renamed",
			diff: original.diff
		)]))
	}

	@Test func netZeroEditsRemainAnAcceptedCachedResult() async
	{
		let probe = Probe()
		let cache = preparation(probe: probe)
		let turn = ConversationNetFileChangePreparation.Source(
			turnID: "turn",
			changes: [
				change(diff: "@@ -1 +1 @@\n-before\n+intermediate"),
				change(diff: "@@ -1 +1 @@\n-intermediate\n+before")
			]
		)
		let initial = await cache.prepare(
			[turn],
			context: "thread"
		)
		#expect(initial?[turn.turnID]?.changes == [])
		#expect(initial?[turn.turnID]?.matches(turn.changes) == true)
		#expect(await cache.prepare(
			[turn],
			context: "thread"
		) == initial)
		#expect(await probe.calls == 1)
	}

	@Test func contextChangesDiscardPreviousRetainedTurns() async
	{
		let probe = Probe()
		let cache = preparation(probe: probe)
		let turn = source(
			"turn",
			after: "result"
		)
		_ = await cache.prepare(
			[turn],
			context: "first"
		)
		_ = await cache.prepare(
			[turn],
			context: "second"
		)
		_ = await cache.prepare(
			[turn],
			context: "first"
		)
		#expect(await probe.calls == 3)
	}

	@Test func itemBudgetKeepsRecentTurnsWithoutDroppingReturnedResults() async
	{
		let probe = Probe()
		let cache = preparation(
			capacity: 1,
			probe: probe
		)
		let first = source(
			"first",
			after: "first-result"
		)
		let second = source(
			"second",
			after: "second-result"
		)
		let result = await cache.prepare(
			[first, second],
			context: "thread"
		)
		#expect(result?.count == 2)
		#expect(await cache.retainedItemCount == 1)
		_ = await cache.prepare(
			[first, second],
			context: "thread"
		)
		#expect(await probe.calls == 3)
	}

	@Test func byteBudgetCountsInputAndOutputAndDoesNotDropThePreparedResult() async
	{
		let probe = Probe()
		let cache = preparation(
			byteCapacity: 400,
			probe: probe
		)
		let turn = source(
			"turn",
			after: String(
				repeating: "x",
				count: 100
			)
		)
		let result = await cache.prepare(
			[turn],
			context: "thread"
		)
		#expect(result?[turn.turnID]?.matches(turn.changes) == true)
		#expect(await cache.retainedItemCount == 0)
		#expect(await cache.retainedByteCount == 0)
		_ = await cache.prepare(
			[turn],
			context: "thread"
		)
		#expect(await probe.calls == 2)
	}

	@Test func cancelledPreparationDoesNotPublishOrCommitItsCache() async
	{
		let probe = Probe(gateFirst: true)
		let cache = preparation(probe: probe)
		let turn = source(
			"turn",
			after: "result"
		)
		let pending = Task
		{
			await cache.prepare(
				[turn],
				context: "thread"
			)
		}
		await probe.waitForGate()
		pending.cancel()
		await probe.release()
		#expect(await pending.value == nil)
		#expect(await cache.retainedItemCount == 0)
		#expect(await cache.prepare(
			[turn],
			context: "thread"
		)?[turn.turnID] != nil)
		#expect(await probe.calls == 2)
	}

	@Test func supersededContextCannotReplaceAcceptedResultsOrRetainedCache() async
	{
		let probe = Probe(gateFirst: true)
		let cache = preparation(probe: probe)
		let old = source(
			"turn",
			after: "old-result"
		)
		let current = source(
			"turn",
			after: "current-result"
		)
		let pending = Task
		{
			await cache.prepare(
				[old],
				context: "old-thread"
			)
		}
		await probe.waitForGate()
		let accepted = await cache.prepare(
			[current],
			context: "current-thread"
		)
		await probe.release()
		#expect(await pending.value == nil)
		#expect(accepted?[current.turnID]?.matches(current.changes) == true)
		#expect(await cache.prepare(
			[current],
			context: "current-thread"
		) == accepted)
		#expect(await probe.calls == 2)
	}

	@MainActor
	@Test func interleavedFileActivitiesKeepTheirPreparedSummaryWhenWorkIsFolded() async
	{
		let first = ConversationEntry(
			id: "turn:first-edit",
			kind: .tool,
			title: "Changed file",
			body: "",
			activity: .fileChanges(
				[change(diff: "@@ -1 +1 @@\n-before\n+intermediate")],
				status: "completed"
			)
		)
		let second = ConversationEntry(
			id: "turn:second-edit",
			kind: .tool,
			title: "Changed file",
			body: "",
			activity: .fileChanges(
				[change(diff: "@@ -1 +1 @@\n-intermediate\n+after")],
				status: "completed"
			)
		)
		let entries = [
			first,
			ConversationEntry(
				id: "turn:comment",
				kind: .agent,
				title: "Codex",
				body: "Working"
			),
			second,
			ConversationEntry(
				id: "turn:reply",
				kind: .agent,
				title: "Codex",
				body: "Done"
			),
			ConversationEntry(
				id: "next:request",
				kind: .user,
				title: "You",
				body: "Next"
			)
		]
		let sources = TranscriptPreparationCoordinator.fileChangeSources(from: entries)
		#expect(sources.count == 1)
		#expect(sources.first?.changes.count == 2)
		let cache = ConversationNetFileChangePreparation()
		let prepared = await cache.prepare(
			sources,
			context: "thread"
		)
		let rows = ConversationTranscriptRow.make(
			entries: entries,
			projectPath: nil,
			preparedNetChanges: prepared ?? [:]
		)
		let timings = [ConversationTurnTiming(
			turnID: "turn",
			status: "completed",
			startedAt: Date(timeIntervalSince1970: 1_000)
		)]
		let collapsed = ConversationTranscriptRow.collapsingWork(
			in: rows,
			workEntryIDs: ConversationTranscriptRow.workEntryIDs(
				entries: entries,
				timings: timings
			),
			expandedTurnIDs: []
		)
		let summaries = collapsed.compactMap
		{
			row -> ConversationEntry? in
			guard case .message(let entry) = row, entry.activity.isFileChange
			else
			{
				return nil
			}
			return entry
		}
		#expect(summaries.map(\.id) == ["turn:file-change-summary"])
		if case .fileChanges(
			let changes,
			_
		) = summaries.first?.activity
		{
			#expect(changes.map(\.diff) == ["@@ -1,1 +1,1 @@\n-before\n+after"])
		}
		else
		{
			Issue.record("Prepared summary was lost during work folding")
		}
	}

	private func preparation(
		capacity: Int = 256,
		byteCapacity: Int = 8 * 1_024 * 1_024,
		probe: Probe
	) -> ConversationNetFileChangePreparation
	{
		ConversationNetFileChangePreparation(
			capacity: capacity,
			byteCapacity: byteCapacity,
			merge:
			{
				await probe.merge($0)
			}
		)
	}

	private func source(
		_ turnID: String,
		after: String
	) -> ConversationNetFileChangePreparation.Source
	{
		ConversationNetFileChangePreparation.Source(
			turnID: turnID,
			changes: [change(diff: "@@ -1 +1 @@\n-before\n+\(after)")]
		)
	}

	private func change(
		path: String = "file.swift",
		kind: String = "update",
		movePath: String? = nil,
		diff: String
	) -> FileChange
	{
		var metadata: [String: String] = ["type": kind]
		metadata["move_path"] = movePath
		return FileChange(json: ["path": path, "kind": metadata, "diff": diff])!
	}

	private actor Probe
	{
		let gateFirst: Bool
		private(set) var calls = 0
		private var suspended: CheckedContinuation<Void, Never>?
		private var gateWaiters: [CheckedContinuation<Void, Never>] = []

		init(gateFirst: Bool = false)
		{
			self.gateFirst = gateFirst
		}

		func merge(_ changes: [FileChange]) async -> [FileChange]
		{
			calls += 1
			if gateFirst, calls == 1
			{
				await withCheckedContinuation
				{
					suspended = $0
					for waiter in gateWaiters
					{
						waiter.resume()
					}
					gateWaiters.removeAll()
				}
			}
			return ConversationNetFileChanges.merge(changes)
		}

		func waitForGate() async
		{
			guard suspended == nil
			else
			{
				return
			}
			await withCheckedContinuation
			{
				gateWaiters.append($0)
			}
		}

		func release()
		{
			suspended?.resume()
			suspended = nil
		}
	}
}
