import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct LocalGitReportedTurnRoutingTests
{
	@Test func unavailableRecordedPayloadUsesBaselineAndCompletedEmptyPayloadDoesNot() async
	{
		let baseline = ReportedTurnBaselineSpy()
		let service = LocalGitComparisonService(baselineService: baseline)
		let unavailable = GitComparisonRequest(
			owner: owner(),
			repositoryRoot: "/tmp/reported-git-turn",
			scope: .lastTurn,
			generation: 1,
			lastTurnID: "editing",
			reportedChanges: nil
		)
		let fallback = await service.compare(unavailable)
		#expect(fallback == .unavailable(.lastTurnUnavailable))
		#expect(await baseline.requestCount == 1)
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
		#expect(await baseline.requestCount == 1)
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

private actor ReportedTurnBaselineSpy: GitTurnBaselineService
{
	private(set) var requestCount = 0

	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		requestCount += 1
		return .unavailable(.lastTurnUnavailable)
	}

	func capture(_ request: GitTurnBaselineCaptureRequest) async -> GitTurnBaselineResult
	{
		.unavailable(.lastTurnUnavailable)
	}

	func bind(
		_ reference: GitTurnBaselineReference,
		turnID: String
	) async -> GitTurnBaselineResult
	{
		.unavailable(.lastTurnUnavailable)
	}

	func lookup(
		repositoryRoot: String,
		threadID: String,
		turnID: String
	) async -> GitTurnBaselineReference?
	{
		nil
	}

	func discard(_ reference: GitTurnBaselineReference) async
	{
	}
}
