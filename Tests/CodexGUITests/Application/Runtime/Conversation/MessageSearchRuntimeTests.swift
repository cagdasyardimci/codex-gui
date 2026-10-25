import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct MessageSearchRuntimeTests
{

	@Test func historyRefreshesBoundBookkeepingAndRejectOlderReplay() async throws
	{
		let workspace = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/search-refresh"
		)
		let context = OperationContext(
			workspace: workspace,
			generation: 1,
			requestID: UUID()
		)
		var delivered = 0
		let runner = WorkspaceEffectRunner(
			service: MockCodexService(),
			persistence: WorkspacePersistenceScheduler(
				writeDraft:
				{
					_ in
				},
				waitForDraftEdits:
				{
				}
			),
			completedRequestLimit: 4,
			mapEvent:
			{
				_, _ in []
			},
			deliver:
			{
				_, complete in
				delivered += 1
				complete()
			}
		)
		defer
		{
			runner.shutdown()
		}
		runner.accept(
			[.persistDraft(WorkspaceDraftWrite(
				context: context,
				conversation: .newChat,
				draft: ComposerDraft(text: "keep")
			))],
			workspace: workspace
		)
		let persistence = try #require(runner.operation(for: context))
		#expect(await persistence.wait() == .finished)
		for revision in 1 ... 64
		{
			let search = MessageSearchOperation(
				context: context,
				query: "needle",
				historyRevision: revision
			)
			runner.accept(
				[.searchMessages(
					search,
					threads: [],
					totalThreadCount: 0
				)],
				workspace: workspace
			)
			let handle = try #require(runner.operation(for: context))
			#expect(await handle.wait() == .finished)
			#expect(runner.accepted.count == 2)
			#expect(runner.retainedOperationCount == 1)
		}
		#expect(delivered == 65)
		for revision in [1, 64]
		{
			let replay = MessageSearchOperation(
				context: context,
				query: "needle",
				historyRevision: revision
			)
			runner.accept(
				[.searchMessages(
					replay,
					threads: [],
					totalThreadCount: 0
				)],
				workspace: workspace
			)
		}
		#expect(runner.runningOperationCount == 0)
		#expect(runner.accepted.count == 2)
		#expect(delivered == 65)
	}

}
