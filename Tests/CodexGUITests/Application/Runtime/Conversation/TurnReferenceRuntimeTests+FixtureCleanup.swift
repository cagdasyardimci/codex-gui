import Foundation
import Testing

@testable import CodexGUI

@MainActor
extension TurnReferenceRuntimeTests
{
	@Test func independentFixturesKeepContextPersistenceSeparate() async throws
	{
		try await withTurnReferenceTestFixture
		{
			first in
			try await withTurnReferenceTestFixture
			{
				second in
				let firstContexts = first.state.store.factoryDependencies.projectContextStore
				let secondContexts = second.state.store.factoryDependencies.projectContextStore
				let firstFile = firstContexts.fileURL(for: first.project)
				let secondFile = secondContexts.fileURL(for: second.project)
				#expect(firstContexts.persistenceWorker !== secondContexts.persistenceWorker)
				#expect(firstFile.deletingLastPathComponent()
					!= secondFile.deletingLastPathComponent())
				#expect(!firstFile.path.hasPrefix(first.project.path + "/"))
				#expect(!secondFile.path.hasPrefix(second.project.path + "/"))
				var context = ProjectContext()
				context.items = [ProjectContextItem(
					kind: .note,
					title: "Only the first fixture",
					body: "Retain this context in its owned persistence directory."
				)]
				try await firstContexts.enqueueSave(
					context,
					for: first.project
				).value
				#expect(try firstContexts.load(for: first.project).items == context.items)
				#expect(try secondContexts.load(for: first.project).items.isEmpty)
			}
		}
	}

	@Test func aCancelledScenarioStillSettlesWritesAndRemovesOwnedResources() async throws
	{
		var root: URL?
		var defaults: IsolatedUserDefaultsFixture?
		var acceptedWrite: Task<Void, Error>?
		var blockedIO: Task<Void, Error>?
		var contexts: ProjectContextStore?
		var project: URL?
		var expectedContext = ProjectContext()
		let ioStarted = AsyncStream<Void>.makeStream()
		let releaseIO = ProjectContextRuntimeGate()
		let cleanupStarted = AsyncStream<Void>.makeStream()
		var reachedResourceRemoval = false
		var scenarioFinished = false
		let scenario = Task<Void, Error>
		{
			@MainActor in
			defer
			{
				scenarioFinished = true
			}
			try await withTurnReferenceTestFixture(
				onCleanupStarted:
				{
					#expect(contexts?.persistenceWorker.hasPendingOperations() == true)
					cleanupStarted.continuation.yield(())
					cleanupStarted.continuation.finish()
				},
				onBeforeRemovingResources:
				{
					#expect(contexts?.persistenceWorker.hasPendingOperations() == false)
					if let contexts, let project
					{
						#expect((try? contexts.load(for: project)) == expectedContext)
					}
					reachedResourceRemoval = true
				}
			)
			{
				fixture in
				root = fixture.root
				defaults = fixture.defaults
				project = fixture.project
				let contextStore = fixture.state.store.factoryDependencies.projectContextStore
				contexts = contextStore
				blockedIO = contextStore.persistenceWorker.enqueue(
					projectPath: fixture.project.path,
					isWrite: false
				)
				{
					ioStarted.continuation.yield(())
					ioStarted.continuation.finish()
					await releaseIO.wait()
				}
				for await _ in ioStarted.stream
				{
					break
				}
				try Task.checkCancellation()
				fixture.defaults.defaults.set(
					"Owned value",
					forKey: "fixture.cleanup"
				)
				var context = ProjectContext()
				context.items = [ProjectContextItem(
					kind: .note,
					title: "Accepted before cancellation",
					body: "The accepted write must finish before its directory is removed."
				)]
				expectedContext = context
				acceptedWrite = contextStore.enqueueSave(
					context,
					for: fixture.project
				)
				#expect(contextStore.persistenceWorker.hasPendingPersistence())
				// Cancel the scenario itself so cleanup runs with a canceled caller.
				withUnsafeCurrentTask
				{
					$0?.cancel()
				}
				try Task.checkCancellation()
			}
		}
		defer
		{
			cleanupStarted.continuation.finish()
			ioStarted.continuation.finish()
		}
		do
		{
			for await _ in cleanupStarted.stream
			{
				break
			}
			try Task.checkCancellation()
			#expect(!scenarioFinished)
			#expect(!reachedResourceRemoval)
			#expect(contexts?.persistenceWorker.hasPendingOperations() == true)
			await releaseIO.signal()
			let result = await scenario.result
			if case .failure(let error) = result
			{
				#expect(error is CancellationError)
			}
			else
			{
				Issue.record("The canceled scenario should preserve its cancellation outcome.")
			}
			let write = try #require(acceptedWrite)
			try await write.value
			let blocker = try #require(blockedIO)
			try await blocker.value
			#expect(reachedResourceRemoval)
			let directory = try #require(root)
			let ownedDefaults = try #require(defaults)
			#expect(!FileManager.default.fileExists(atPath: directory.path))
			#expect(ownedDefaults.defaults.persistentDomain(forName: ownedDefaults.suiteName)?
				.isEmpty != false)
		}
		catch
		{
			scenario.cancel()
			await releaseIO.signal()
			_ = await scenario.result
			_ = await acceptedWrite?.result
			_ = await blockedIO?.result
			throw error
		}
	}
}
