import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct WorkspaceStoreFactoryTests
{
	@Test func factoryCapturesLiveTurnTimesWhenBackendOmitsThem() async throws
	{
		let (store, service, _, defaults, suite) = WorkspaceStoreFactoryFixture.make()
		defer
		{
			store.shutdown()
			defaults.removePersistentDomain(forName: suite)
		}
		await store.inputs.connect()
		let before = Date()
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.turn
		))
		let timing = try #require(store.currentSnapshot.turnTimings.first)
		let start = try #require(timing.startedAt)
		#expect(start >= before && start <= Date())
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.turn
		))
		#expect(store.currentSnapshot.turnTimings.first?.startedAt == start)
		service.emit(.turnCompleted(
			threadId: service.thread.id,
			turn: CodexTurn(
				id: service.turn.id,
				status: "completed",
				items: [],
				error: nil
			)
		))
		let completed = try #require(store.currentSnapshot.turnTimings.first)
		#expect(completed.startedAt == start)
		#expect(try #require(completed.completedAt) >= start)
	}

	@Test func bootstrapUsesRealReducersAndRepeatedSelectionHydrationPreservesTheEdit() async throws
	{
		let (store, service, storage, defaults, suite) = WorkspaceStoreFactoryFixture.make()
		defer
		{
			store.shutdown()
			defaults.removePersistentDomain(forName: suite)
		}
		#expect(store.currentSnapshot.selectedThreadID == "factory-thread")
		#expect(store.currentSnapshot.draft == "Persisted draft")
		await store.inputs.connect()
		#expect(service.connectionCount == 1)
		#expect(service.accountReadCount == 1)
		#expect(service.modelReadCount == 1)
		#expect(service.skillReadCount == 1)
		#expect(service.rateLimitReadCount == 1)
		#expect(service.readThreadCount == 1)
		#expect(store.currentSnapshot.canSend)
		store.inputs.updateDraft("Current visible edit")
		try await store.awaitAcceptedPersistence()
		for _ in 0 ..< 2
		{
			storage.saveDraft(
				"Obsolete stored draft",
				for: URL(fileURLWithPath: "/tmp"),
				threadID: "factory-thread"
			)
			let selection = try #require(store.inputs.selectThread("factory-thread"))
			#expect(await selection.wait() == .finished)
			#expect(store.currentSnapshot.draft == "Current visible edit")
			#expect(store.model.composer.drafts[.thread("factory-thread")]?.revision == 1)
		}
		#expect(service.connectionCount == 1)
	}

}
