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

	@Test("Queued context IO retains its accepted checkout after a symlink is retargeted")
	func queuedCheckoutAliasRetainsItsCapturedProject() async throws
	{
		let fixture = try await ProjectContextPersistenceFixture()
		defer
		{
			fixture.remove()
		}
		let otherProject = fixture.directory.appendingPathComponent("other-project")
		try FileManager.default.createDirectory(
			at: otherProject,
			withIntermediateDirectories: true
		)
		let alias = fixture.directory.appendingPathComponent("checkout")
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: fixture.project
		)
		let blocker = fixture.blockWorker()
		await blocker.started.wait()
		defer
		{
			Task
			{
				await blocker.release.signal()
			}
		}
		let acceptedContext = fixture.context("Accepted owner")
		let save = fixture.contexts.enqueueSave(
			acceptedContext,
			for: alias
		)
		let load = fixture.contexts.enqueueLoad(for: alias)

		try FileManager.default.removeItem(at: alias)
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: otherProject
		)
		#expect(!fixture.contexts.persistenceWorker.hasPendingPersistence(projectPath: alias.path))
		#expect(fixture.contexts.persistenceWorker
			.hasPendingPersistence(projectPath: fixture.project.path))
		await blocker.release.signal()
		try await save.value
		#expect(try await load.value == acceptedContext)
		try await fixture.contexts.persistenceWorker.drain(projectPath: fixture.project.path)
		#expect(try fixture.contexts.load(for: fixture.project) == acceptedContext)
		#expect(try fixture.contexts.load(for: otherProject) == ProjectContext())
	}

	@Test("Accepted IO and its drain retain a bucket when its physical checkout becomes a symlink")
	func queuedPhysicalCheckoutReplacementPreservesItsAcceptedBucketAndDrain() async throws
	{
		let fixture = try await ProjectContextPersistenceFixture()
		defer
		{
			fixture.remove()
		}
		let otherProject = fixture.directory.appendingPathComponent("other-project")
		try FileManager.default.createDirectory(
			at: otherProject,
			withIntermediateDirectories: true
		)
		let capturedPath = fixture.project.path
		let originalDocumentURL = fixture.contexts.fileURL(for: fixture.project)
		let replacementDocumentURL = fixture.contexts.fileURL(for: otherProject)
		let acceptedContext = fixture.context("Keep the accepted bucket")
		let blocker = fixture.blockWorker()
		await blocker.started.wait()
		defer
		{
			Task
			{
				await blocker.release.signal()
			}
		}
		let save = fixture.contexts.enqueueSave(
			acceptedContext,
			for: fixture.project
		)
		let load = fixture.contexts.enqueueLoad(for: fixture.project)

		try FileManager.default.moveItem(
			at: fixture.project,
			to: fixture.directory.appendingPathComponent("moved-project")
		)
		try FileManager.default.createSymbolicLink(
			at: fixture.project,
			withDestinationURL: otherProject
		)
		#expect(fixture.contexts.persistenceWorker
			.hasPendingPersistence(canonicalProjectPath: capturedPath))
		#expect(!fixture.contexts.persistenceWorker
			.hasPendingPersistence(projectPath: fixture.project.path))

		var didFinishDrain = false
		var drain: Task<Void, Error>?
		await withCheckedContinuation
		{
			(started: CheckedContinuation<Void, Never>) in
			drain = Task
			{
				started.resume()
				try await fixture.contexts.persistenceWorker.drain(
					canonicalProjectPath: capturedPath
				)
				didFinishDrain = true
			}
		}
		let acceptedDrain = try #require(drain)
		#expect(!didFinishDrain)

		await blocker.release.signal()
		try await acceptedDrain.value
		try await save.value
		#expect(try await load.value == acceptedContext)
		#expect(didFinishDrain)
		#expect(!fixture.contexts.persistenceWorker
			.hasPendingOperations(canonicalProjectPath: capturedPath))
		let documentData = try Data(contentsOf: originalDocumentURL)
		let document = try #require(
			JSONSerialization.jsonObject(with: documentData) as? [String: Any]
		)
		#expect(document["projectPath"] as? String == capturedPath)
		#expect(!FileManager.default.fileExists(atPath: replacementDocumentURL.path))
		#expect(try fixture.contexts.load(for: fixture.project) == ProjectContext())
		#expect(try fixture.contexts.load(for: otherProject) == ProjectContext())
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
	@Test("Queued writes revalidate external bytes and retain scoped failure barriers until retry")
	func externalProtectedDocumentsRemainUnchanged() async throws
	{
		for field in ["corrupt", "version", "projectPath"]
		{
			let fixture = try await ProjectContextPersistenceFixture()
			defer
			{
				fixture.remove()
			}
			try fixture.contexts.save(
				ProjectContext(),
				for: fixture.project
			)
			let file = fixture.contexts.fileURL(for: fixture.project)
			let original = try Data(contentsOf: file)
			var document = try #require(
				JSONSerialization.jsonObject(with: original) as? [String: Any]
			)
			document[field] = field == "version" ? (999 as Any) : ("/another/project" as Any)
			let external = field == "corrupt" ? Data("{broken".utf8)
				: try JSONSerialization.data(withJSONObject: document)
			let blocker = fixture.blockWorker()
			await blocker.started.wait()
			let edit = fixture.context("Keep this edit")
			let write = fixture.contexts.enqueueSave(
				edit,
				for: fixture.project
			)
			try external.write(to: file)
			await blocker.release.signal()
			let outcome = await write.result
			if case .success = outcome
			{
				Issue.record("The queued write replaced protected external bytes.")
			}
			#expect(try Data(contentsOf: file) == external)
			var failedBarrier = false
			do
			{
				try await fixture.contexts.persistenceWorker
					.drain(projectPath: fixture.project.path)
			}
			catch
			{
				failedBarrier = true
			}
			#expect(failedBarrier)
			#expect(fixture.contexts.persistenceWorker
				.hasPendingPersistence(projectPath: fixture.project.path))
			#expect(!fixture.contexts.persistenceWorker
				.hasPendingPersistence(projectPath: "/unrelated"))
			try await fixture.contexts.persistenceWorker.drain(projectPath: "/unrelated")
			try original.write(to: file)
			try await fixture.contexts.enqueueSave(
				edit,
				for: fixture.project
			).value
			try await fixture.contexts.persistenceWorker.drain(projectPath: fixture.project.path)
			#expect(!fixture.contexts.persistenceWorker
				.hasPendingPersistence(projectPath: fixture.project.path))
			#expect(try fixture.contexts.load(for: fixture.project) == edit)
		}
	}
}
