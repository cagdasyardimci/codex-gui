import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationTurnChangeSummaryLoaderTests
{
	@Test func runningTurnReadsBaselineChangesMadeOutsideFileChangeReports() async throws
	{
		let service = TurnChangeSummaryServiceStub()
		let loader = ConversationTurnChangeSummaryLoader(service: service)
		var snapshot = ConversationTurnChangeSummaryTestFixture.makeSnapshot(reports: false)
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
