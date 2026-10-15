import Foundation
import Testing
@testable import CodexGUI

@MainActor
struct TurnReferenceTestFixture
{
	let state: WorkspaceTestFixture
	let service: MockCodexService
	let project: URL
	let root: URL
	let defaults: IsolatedUserDefaultsFixture
	let onCleanupStarted: @MainActor () -> Void
	let onBeforeRemovingResources: @MainActor () -> Void

	fileprivate func close() async
	{
		// Keep cleanup independent of scenario cancellation while retaining its test context.
		await Task
		{
			@MainActor in
			onCleanupStarted()
			state.shutdown()
			service.pendingTurnContentRead?.resume(throwing: CancellationError())
			service.pendingTurnContentRead = nil
			// Shutdown stops new reservations, but accepted writes retain their IO ownership.
			// Drain both context and defaults persistence before deleting the fixture's resources.
			do
			{
				try await state.store.drainPersistence()
			}
			catch
			{
				Issue.record(error)
				// A defaults-write failure can skip the context drain; still wait for accepted IO.
				try? await state.store.factoryDependencies.projectContextStore.persistenceWorker
					.drain()
			}
			onBeforeRemovingResources()
			defaults.cleanup()
			do
			{
				try await BackgroundTestWork.perform
				{
					[root] in
					try FileManager.default.removeItem(at: root)
				}
			}
			catch
			{
				Issue.record(error)
			}
		}.value
	}
}

@MainActor
func withTurnReferenceTestFixture<Result>(
	pagedReferences: Bool = false,
	totalTurns: Int = 66,
	previewPreparer: any ConversationPreviewPreparing = ConversationMarkdownPreviewPreparer(),
	onCleanupStarted: @escaping @MainActor () -> Void =
	{
	},
	onBeforeRemovingResources: @escaping @MainActor () -> Void =
	{
	},
	operation: @MainActor (TurnReferenceTestFixture) async throws -> Result
) async throws -> Result
{
	let fixture = try await makeTurnReferenceTestFixture(
		pagedReferences: pagedReferences,
		totalTurns: totalTurns,
		previewPreparer: previewPreparer,
		onCleanupStarted: onCleanupStarted,
		onBeforeRemovingResources: onBeforeRemovingResources
	)
	// Async cleanup must finish even when a requirement aborts the scenario.
	do
	{
		let result = try await operation(fixture)
		await fixture.close()
		return result
	}
	catch
	{
		await fixture.close()
		throw error
	}
}

@MainActor
private func makeTurnReferenceTestFixture(
	pagedReferences: Bool = false,
	totalTurns: Int = 66,
	previewPreparer: any ConversationPreviewPreparing = ConversationMarkdownPreviewPreparer(),
	onCleanupStarted: @escaping @MainActor () -> Void,
	onBeforeRemovingResources: @escaping @MainActor () -> Void
) async throws -> TurnReferenceTestFixture
{
	// Files and immutable turn data can be prepared before constructing actor-bound services.
	let (root, turns) = try await BackgroundTestWork.perform
	{
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(
			"TurnReferenceTests-\(UUID())",
			isDirectory: true
		).standardizedFileURL.resolvingSymlinksInPath()
		do
		{
			try FileManager.default.createDirectory(
				at: root.appendingPathComponent("checkout/.git"),
				withIntermediateDirectories: true
			)
		}
		catch
		{
			try? FileManager.default.removeItem(at: root)
			throw error
		}
		let turns = (0 ..< totalTurns).map
		{
			index in
			CodexTurn(json: ["id": "turn-\(index)", "status": "completed", "items": [
				[
					"id": "request",
					"type": "userMessage",
					"content": [["type": "text", "text": "Request \(index)"]]
				],
				["id": "reply", "type": "agentMessage", "text": "Reply \(index)"],
			]])!
		}
		return (root, turns)
	}
	let project = root.appendingPathComponent("checkout")
	let defaults: IsolatedUserDefaultsFixture
	do
	{
		defaults = try IsolatedUserDefaultsFixture(prefix: "TurnReferenceTests")
	}
	catch
	{
		await Task
		{
			@MainActor in
			do
			{
				try await BackgroundTestWork.perform
				{
					try FileManager.default.removeItem(at: root)
				}
			}
			catch
			{
				Issue.record(error)
			}
		}.value
		throw error
	}
	// Independent fixtures need independent workers.
	// Keep context files outside the indexed checkout.
	let contexts = ProjectContextStore(directory: root.appendingPathComponent("contexts"))
	let service = MockCodexService()
	service.configureCheckout(project)
	let references = turns.map
	{
		ConversationTurnReference(
			id: $0.id,
			status: $0.status
		)
	}
	service.savedTurns = Array(turns.suffix(25))
	service.readNextCursor = "older-content"
	service.referencedTurnContents = Dictionary(uniqueKeysWithValues: turns.map
	{
		($0.id, $0)
	})
	service.turnReferencePages[""] = TurnReferencePage(
		references: pagedReferences ? Array(references.suffix(50)) : references,
		nextCursor: pagedReferences ? "older-references" : nil
	)
	service.turnReferencePages["older-references"] = TurnReferencePage(
		references: Array(references.prefix(16)),
		nextCursor: nil
	)
	let state = WorkspaceTestFixture(store: WorkspaceStoreFactory.makeSource(
		dependencies: WorkspaceStoreDependencies(
			service: service,
			storage: LocalStorage(defaults: defaults.defaults),
			projectContextStore: contexts,
			previewPreparer: previewPreparer
		)
	))
	let fixture = TurnReferenceTestFixture(
		state: state,
		service: service,
		project: project,
		root: root,
		defaults: defaults,
		onCleanupStarted: onCleanupStarted,
		onBeforeRemovingResources: onBeforeRemovingResources
	)
	do
	{
		await state.inputs.connect()
		state.inputs.openProject(project)
		// Startup and metadata hydration publish independently; await this store's readiness.
		await awaitWorkspaceSnapshot(state.store)
		{
			$0.canManageThreads
		}
		try #require(state.currentSnapshot.canManageThreads)
		let selection = try #require(state.inputs.selectThread(service.thread.id))
		try #require(await selection.wait() == .finished)
		await awaitWorkspaceSnapshot(state.store)
		{
			$0.entries.count == 50 && $0.turnReferences.count == (pagedReferences ? 50 : totalTurns)
		}
		try #require(state.currentSnapshot.entries.count == 50 && state.currentSnapshot
			.turnReferences
			.count == (pagedReferences ? 50 : totalTurns))
		return fixture
	}
	catch
	{
		await fixture.close()
		throw error
	}
}

@MainActor
extension TurnReferenceTestFixture
{
	func awaitSnapshot(matching predicate: @escaping @MainActor () -> Bool) async -> Bool
	{
		await awaitWorkspaceSnapshot(state.store)
		{
			_ in predicate()
		}
		return predicate()
	}
}
