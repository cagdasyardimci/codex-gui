import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationTurnChangeSummaryTests
{
	@Test func badgeTracksOnlySelectedRunningTurnAndOpensChanges() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		var opened = 0
		controller.onViewChanges =
		{
			opened += 1
		}
		let snapshot = makeSnapshot()
		controller.render(snapshot)
		#expect(controller.turnChangeSummaryButton.isHidden == false)
		#expect(controller.turnChangeSummaryButton.attributedTitle.string
			== "2 files changed +3 -1")
		controller.turnChangeSummaryButton.performClick(nil)
		#expect(opened == 1)

		controller.render(makeSnapshot(selectedThreadID: "elsewhere"))
		#expect(controller.turnChangeSummaryButton.isHidden)

		controller.render(makeSnapshot(executionState: .completed))
		#expect(controller.turnChangeSummaryButton.isHidden)
	}

	@Test func aggregateTurnDiffTakesPrecedenceOverReportedItems() throws
	{
		let diff = "diff --git a/Sources/First.swift b/Sources/First.swift\n"
			+ "--- a/Sources/First.swift\n+++ b/Sources/First.swift\n"
			+ "@@ -1 +1 @@\n-old\n+new\n"
		let summary = try #require(ConversationTurnChangeSummary(
			makeSnapshot(activeTurnDiff: diff)
		))
		#expect(summary.fileCount == 1)
		#expect(summary.additions == 1)
		#expect(summary.deletions == 1)
		#expect(ConversationTurnChangeSummary(makeSnapshot(activeTurnDiff: "")) == nil)
	}

	@Test func runningTurnReadsBaselineChangesMadeOutsideFileChangeReports() async throws
	{
		let service = TurnChangeSummaryServiceStub()
		let loader = ConversationTurnChangeSummaryLoader(service: service)
		var snapshot = makeSnapshot(reports: false)
		snapshot.workspaceOwner = ConversationPresentationTestFixture.presentationOwner(
			sessionID: UUID()
		)
		snapshot.activeExecutionState = .running
		var observed: ConversationTurnChangeSummary?
		loader.onChange =
		{
			observed = $0
		}
		loader.render(ConversationPresentation(snapshot).composer)
		for _ in 0 ..< 100 where observed?.additions != 10
		{
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(observed?.fileCount == 2)
		#expect(observed?.additions == 10)
		#expect(observed?.deletions == 8)
		let request = try #require(await service.lastRequest())
		#expect(request.scope == .lastTurn)
		#expect(request.lastTurnID == "turn")
		#expect(request.repositoryRoot == "/tmp/replay")
		loader.stop()
	}

	@Test func runningTurnReviewDoesNotUsePreviousTurnsReportedChanges() throws
	{
		var snapshot = makeSnapshot()
		snapshot.lastGitTurnID = "previous"
		snapshot.reportedGitTurnID = "previous"
		snapshot.reportedGitChanges = [FileChange(json: [
			"path": "Old.swift",
			"kind": "update",
		])!]
		#expect(snapshot.visibleGitReviewTurn.id == "turn")
		#expect(snapshot.visibleGitReviewTurn.changes == nil)
	}

	private func makeSnapshot(
		selectedThreadID: String = "thread",
		executionState: ExecutionState = .running,
		activeTurnDiff: String? = nil,
		reports: Bool = true
	) -> ConversationSnapshot
	{
		let edit = FileChange(json: [
			"path": "Sources/First.swift",
			"kind": "update",
			"diff": "@@ -1 +1,2 @@\n-old\n+new\n+extra",
		])!
		let secondEdit = FileChange(json: [
			"path": "Sources/First.swift",
			"kind": "update",
			"diff": "@@ -3 +3 @@\n line\n+again",
		])!
		let addition = FileChange(json: [
			"path": "Sources/Second.swift",
			"kind": "add",
			"diff": "",
		])!
		let entry = ConversationEntry(
			id: "turn:item",
			kind: .tool,
			title: "File changes",
			body: "",
			activity: .fileChanges(
				[edit, secondEdit, addition],
				status: "completed"
			)
		)
		let previous = ConversationEntry(
			id: "previous:item",
			kind: .tool,
			title: "Old changes",
			body: "",
			activity: .fileChanges(
				[edit],
				status: "completed"
			)
		)
		var snapshot = ConversationSnapshot(
			projectPath: "/tmp/replay",
			threads: [],
			selectedThreadID: selectedThreadID,
			entries: reports ? [previous, entry] : [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: true,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: executionState,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		snapshot.activeThreadID = "thread"
		snapshot.activeTurnID = "turn"
		snapshot.activeTurnDiff = activeTurnDiff
		return snapshot
	}
}

private actor TurnChangeSummaryServiceStub: GitTurnBaselineService
{
	private var request: GitComparisonRequest?

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

	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		self.request = request
		let files = [
			GitComparisonFile(
				oldPath: "First.swift",
				newPath: "First.swift",
				kind: .modified,
				additions: 6,
				deletions: 5,
				isBinary: false,
				patch: "",
				hunks: []
			),
			GitComparisonFile(
				oldPath: nil,
				newPath: "Second.swift",
				kind: .added,
				additions: 4,
				deletions: 3,
				isBinary: false,
				patch: "",
				hunks: []
			),
		]
		return .snapshot(GitComparisonSnapshot(
			request: request,
			id: "comparison",
			resolvedBase: "before",
			resolvedTarget: "after",
			patch: Data(),
			files: files
		))
	}

	func discard(_ reference: GitTurnBaselineReference) async
	{
	}

	func lastRequest() -> GitComparisonRequest?
	{
		request
	}
}
