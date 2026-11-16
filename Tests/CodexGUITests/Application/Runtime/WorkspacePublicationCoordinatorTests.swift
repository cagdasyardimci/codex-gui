import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct WorkspacePublicationCoordinatorTests
{
	@Test func consecutiveEditsAndPersistenceCompletionsPublishOnlyTheLatestDraft() async throws
	{
		let defaults = try IsolatedUserDefaultsFixture(prefix: "DraftPublication")
		defer
		{
			defaults.cleanup()
		}
		let service = WorkspaceCodexService(
			directory: URL(fileURLWithPath: "/unused"),
			threadID: "thread"
		)
		let gate = PublicationGate()
		let store = WorkspaceStateStore(
			model: WorkspaceModel(identity: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: nil
			)),
			service: service,
			persistence: WorkspacePersistenceScheduler(writeDraft:
				{
					_ in
				}),
			reducers: [WorkspaceFeatureComposition.reducer],
			factoryDependencies: WorkspaceStoreDependencies(
				service: service,
				storage: LocalStorage(defaults: defaults.defaults),
				publicationWait: gate.wait
			)
		)
		defer
		{
			store.shutdown(); gate.onWaitersChanged = nil; gate.release()
		}
		var drafts: [String] = []
		var published: CheckedContinuation<Void, Never>?
		let coordinator = WorkspacePublicationCoordinator(
			store: store,
			render:
			{
				drafts.append($0.draft)
				published?.resume()
				published = nil
			}
		)
		defer
		{
			coordinator.cancel()
		}
		drafts.removeAll()
		store.inputs.updateDraft("First")
		store.inputs.updateDraft("Latest")
		store.dispatch(.composer(.draftPersistenceFinished(
			store.operationContext(),
			.succeeded(())
		)))
		#expect(store.currentSnapshot.draft == "Latest")
		#expect(drafts.isEmpty)
		await withCheckedContinuation
		{
			published = $0
			gate.onWaitersChanged =
			{
				if gate.isWaiting
				{
					gate.release()
				}
			}
		}
		#expect(drafts == ["Latest"])
	}
}
