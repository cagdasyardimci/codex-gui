import Foundation
import Testing
@testable import CodexGUI

@MainActor
@Suite
struct ProjectContextStorePersistenceTests
{
	@Test("Shared storage reservations preserve save/load order across facade instances")
	func sharedDirectoryOrdersSaveAndLoad() async throws
	{
		let fixture = try await ProjectContextPersistenceFixture()
		defer
		{
			fixture.remove()
		}
		try FileManager.default.createDirectory(
			at: fixture.storageDirectory,
			withIntermediateDirectories: true
		)
		let storageAlias = fixture.directory.appendingPathComponent("data-alias")
		try FileManager.default.createSymbolicLink(
			at: storageAlias,
			withDestinationURL: fixture.storageDirectory
		)
		let second = ProjectContextStore(directory: storageAlias)
		#expect(fixture.contexts.persistenceWorker === second.persistenceWorker)
		#expect(fixture.contexts.fileURL(for: fixture.project) == second
			.fileURL(for: fixture.project))
		let blocker = fixture.blockWorker()
		await blocker.started.wait()
		let firstValue = fixture.context("First")
		let secondValue = fixture.context("Second")
		let firstSave = fixture.contexts.enqueueSave(
			firstValue,
			for: fixture.project
		)
		let firstRead = second.enqueueLoad(for: fixture.project)
		let secondSave = second.enqueueSave(
			secondValue,
			for: fixture.project
		)
		let secondRead = fixture.contexts.enqueueLoad(for: fixture.project)
		#expect(second.persistenceWorker.hasPendingOperations(projectPath: fixture.project.path))
		await blocker.release.signal()
		try await firstSave.value
		#expect(try await firstRead.value == firstValue)
		try await secondSave.value
		#expect(try await secondRead.value == secondValue)
		try await second.persistenceWorker.drain()
		#expect(!fixture.contexts.persistenceWorker.hasPendingOperations())
	}

	@Test("An alias and canonical checkout share the same failed-write and recovery barrier")
	func checkoutAliasesShareFailureAndRecoveryBarriers() async throws
	{
		let fixture = try await ProjectContextPersistenceFixture()
		defer
		{
			fixture.remove()
		}
		let alias = fixture.directory.appendingPathComponent("checkout")
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: fixture.project
		)
		try fixture.contexts.save(
			ProjectContext(),
			for: fixture.project
		)
		let documentURL = fixture.contexts.fileURL(for: fixture.project)
		let originalData = try Data(contentsOf: documentURL)
		try Data("{broken".utf8).write(to: documentURL)
		let acceptedContext = fixture.context("Retry through the canonical checkout")
		_ = await fixture.contexts.enqueueSave(
			acceptedContext,
			for: alias
		).result

		do
		{
			try await fixture.contexts.persistenceWorker.drain(projectPath: fixture.project.path)
			Issue.record("The canonical checkout lost the alias's failed-write barrier.")
		}
		catch is ProjectContextStoreError
		{
		}
		#expect(fixture.contexts.persistenceWorker.hasPendingPersistence(projectPath: alias.path))
		#expect(fixture.contexts.persistenceWorker
			.hasPendingPersistence(projectPath: fixture.project.path))

		try originalData.write(to: documentURL)
		try await fixture.contexts.enqueueSave(
			acceptedContext,
			for: fixture.project
		).value
		try await fixture.contexts.persistenceWorker.drain(projectPath: alias.path)
		#expect(!fixture.contexts.persistenceWorker.hasPendingPersistence(projectPath: alias.path))
		#expect(!fixture.contexts.persistenceWorker
			.hasPendingPersistence(projectPath: fixture.project.path))
		#expect(try fixture.contexts.load(for: fixture.project) == acceptedContext)
	}
}
