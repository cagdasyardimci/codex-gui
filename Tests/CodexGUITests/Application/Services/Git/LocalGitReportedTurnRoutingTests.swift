import Foundation
import Testing

@testable import CodexGUI

@Suite
struct LocalGitReportedTurnRoutingTests
{
	@Test func unavailableRecordedPayloadNeverUsesCheckoutAndCompletedEmptyPayloadIsAuthoritative(
	) async
	{
		let service = LocalGitComparisonService()
		let unavailable = GitComparisonRequest(
			owner: owner(),
			repositoryRoot: "/tmp/reported-git-turn",
			scope: .lastTurn,
			generation: 1,
			lastTurnID: "editing",
			reportedChanges: nil
		)
		let resultWithoutReports = await service.compare(unavailable)
		#expect(resultWithoutReports == .unavailable(.lastTurnUnavailable))
		var empty = unavailable
		empty.reportedChanges = []
		let result = await service.compare(empty)
		guard case .snapshot(let snapshot) = result
		else
		{
			Issue.record("Expected authoritative empty recorded comparison")
			return
		}
		#expect(snapshot.files.isEmpty)
		#expect(snapshot.patch.isEmpty)
	}

	@Test func sharedCheckoutChangesCannotEnterEitherTasksLastTurn() async throws
	{
		let fixture = try await BackgroundTestWork.perform
		{
			try GitTurnBaselineFixture()
		}
		defer
		{
			fixture.remove()
		}
		let baselines = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		let captured = try await fixture.capture(baselines)
		let bound = try await fixture.bind(
			captured,
			service: baselines,
			turnID: "turn-a"
		)
		try fixture.write(
			"source.txt",
			"task B changes\ncontext\n"
		)
		try fixture.write(
			"other-task.txt",
			"another task\n"
		)
		try fixture.git(["add", "other-task.txt"])
		var request = fixture.comparisonRequest(
			baseline: bound,
			turnID: "turn-a"
		)
		let service = LocalGitComparisonService()
		#expect(await service.compare(request) == .unavailable(.lastTurnUnavailable))
		let patch = FileChange(json: [
			"path": "source.txt",
			"kind": "update",
			"diff": "@@ -1 +1 @@\n-original\n+task A changes",
		])!
		request.reportedChanges = [patch]
		guard case .snapshot(let first) = await service.compare(request)
		else
		{
			Issue.record("Expected task A's reported edits")
			return
		}
		#expect(first.files.map(\.path) == ["source.txt"])
		#expect(String(
			decoding: first.patch,
			as: UTF8.self
		).contains("task B") == false)
		try fixture.write(
			"source.txt",
			"unrelated later changes\n"
		)
		guard case .snapshot(let after) = await service.compare(request)
		else
		{
			Issue.record("Expected stable task A's reported edits")
			return
		}
		#expect(after.patch == first.patch)
		var second = fixture.comparisonRequest(
			baseline: nil,
			turnID: "turn-b",
			threadID: "task-b"
		)
		second.reportedChanges = [FileChange(json: [
			"path": "other-task.txt",
			"kind": "add",
			"diff": "another task\n",
		])!]
		guard case .snapshot(let other) = await service.compare(second)
		else
		{
			Issue.record("Expected task B's reported edits")
			return
		}
		#expect(other.files.map(\.path) == ["other-task.txt"])
	}

	@Test func incompatibleAndOverBudgetReportsRemainReviewable() async throws
	{
		let cases = [
			["@@ -1 +1 @@\n-before\n+task A", "@@ -1 +1 @@\n-task B\n+task A again"],
			["@@ -1000000 +1000000 @@\n-before\n+after",
				"@@ -1000000 +1000000 @@\n-after\n+final"],
		]
		for diffs in cases
		{
			let changes = diffs.map
			{
				FileChange(json: ["path": "file.swift", "kind": "update", "diff": $0])!
			}
			let request = GitComparisonRequest(
				owner: owner(),
				repositoryRoot: "/nonexistent/reported-edits-only",
				scope: .lastTurn,
				generation: 1,
				lastTurnID: "editing",
				reportedChanges: changes
			)
			let result = await LocalGitComparisonService().compare(request)
			guard case .snapshot(let snapshot) = result
			else
			{
				Issue.record("Expected reported edit fallback")
				continue
			}
			#expect(snapshot.usesReportedEditFallback)
			#expect(snapshot.files.map(\.path) == ["file.swift"])
			#expect(snapshot.additions == 2)
			#expect(snapshot.deletions == 2)
			#expect(snapshot.copyCommand == nil)
			let patch = String(
				decoding: snapshot.patch,
				as: UTF8.self
			)
			for diff in diffs
			{
				#expect(patch.contains(diff))
			}
		}
	}

	@Test func temporaryCopyEditsAreExcludedFromLastTurnFilesAndTotals() async throws
	{
		let changes = ["/tmp/codex-gui-send.copy/File.swift", "File.swift"].map
		{
			FileChange(json: [
				"path": $0,
				"kind": "update",
				"diff": "@@ -1 +1 @@\n-old\n+new",
			])!
		}
		var request = GitComparisonRequest(
			owner: owner(),
			repositoryRoot: "/workspace/repo",
			scope: .lastTurn,
			generation: 1,
			lastTurnID: "turn",
			reportedChanges: changes
		)
		guard case .snapshot(let snapshot) = await LocalGitComparisonService().compare(request)
		else
		{
			Issue.record("Expected repository edits")
			return
		}
		#expect(snapshot.files.map(\.path) == ["File.swift"])
		#expect(snapshot.additions == 1)
		#expect(snapshot.deletions == 1)
		request.reportedChanges = [changes[0]]
		guard case .snapshot(let empty) = await LocalGitComparisonService().compare(request)
		else
		{
			Issue.record("Expected empty comparison for temporary-only edits")
			return
		}
		#expect(empty.files.isEmpty)
		#expect(empty.patch.isEmpty)
	}

	private func owner() -> FeaturePresentationOwner
	{
		FeaturePresentationOwner(
			ConversationSnapshot(
				projectPath: "/tmp/reported-git-turn",
				threads: [],
				selectedThreadID: "thread",
				entries: [],
				canLoadEarlierTurns: false,
				changedFiles: [],
				diff: "",
				draft: "",
				canSend: false,
				accountDescription: "Test",
				backendDescription: "Test",
				executionState: .ready,
				statusMessage: nil,
				models: [],
				selectedModelID: nil,
				selectedEffort: nil,
				pendingInteractions: [],
				recentProjects: []
			),
			storeIdentity: "reported-git-turn-test"
		)
	}
}
