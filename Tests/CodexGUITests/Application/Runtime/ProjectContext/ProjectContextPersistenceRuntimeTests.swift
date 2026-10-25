import Foundation
import Testing
@testable import CodexGUI

@MainActor
@Suite
struct ProjectContextPersistenceRuntimeTests
{

	@Test("Cancellation retires result delivery while the captured write remains ordered")
	func cancellationPreservesCapturedWriteAndOwner() async throws
	{
		let fixture = try await ProjectContextPersistenceFixture()
		defer
		{
			fixture.remove()
		}
		let blocker = fixture.blockWorker()
		await blocker.started.wait()
		var actions: [WorkspaceAction] = []
		let runner = fixture.runner(deliver:
			{
				action, completed in
				actions.append(action)
				completed()
			})
		defer
		{
			runner.shutdown()
		}
		var deliveryTasks: [Task<Void, Never>] = []
		func settleDelivery() async
		{
			runner.shutdown()
			await blocker.release.signal()
			for task in deliveryTasks
			{
				await task.value
			}
			do
			{
				try await runner.drainPersistence()
			}
			catch
			{
				Issue.record(error)
			}
		}
		do
		{
			let identity = fixture.identity()
			let edit = ContextSaveOperation(
				context: OperationContext(
					workspace: identity,
					generation: 0,
					requestID: UUID()
				),
				revision: 1,
				value: fixture.context("Original owner")
			)
			runner.accept(
				[.saveProjectContext(edit)],
				workspace: identity
			)
			deliveryTasks = runner.executionTasks(for: edit.context)
			let handle = try #require(runner.operation(for: edit.context))
			try #require(!deliveryTasks.isEmpty)
			runner.cancel(edit.context)
			#expect(handle.completion == .cancelled)
			try #require(actions.count == 1)
			if case .contextNavigation(.contextPersistenceFinished(
				let canceledEdit,
				.failed(let failure)
			)) = actions[0]
			{
				#expect(canceledEdit.context == edit.context)
				#expect(canceledEdit.revision == edit.revision)
				#expect(canceledEdit.value == edit.value)
				#expect(failure.message.contains("cancelled"))
			}
			else
			{
				Issue.record("Canceling the write must publish its captured cancellation outcome.")
			}
			await blocker.release.signal()
			try await runner.drainPersistence()
			for task in deliveryTasks
			{
				await task.value
			}
			#expect(actions.count == 1)
			#expect(try fixture.contexts.load(for: fixture.project) == edit.value)
			#expect(try fixture.contexts.load(for: fixture.directory
					.appendingPathComponent("another-owner")) == ProjectContext())
			await settleDelivery()
		}
		catch
		{
			await settleDelivery()
			throw error
		}
	}
}

private final class ContextIORecordingFileManager: FileManager, @unchecked Sendable
{
	private let accessLock = NSLock()
	private var accessMainThread: [Bool] = []

	var accessesOccurredOffMain: Bool
	{
		accessLock.withLock
		{
			!accessMainThread.isEmpty && accessMainThread.allSatisfy
			{
				!$0
			}
		}
	}

	func resetAccesses()
	{
		accessLock.withLock
		{
			accessMainThread.removeAll()
		}
	}

	override func fileExists(atPath path: String) -> Bool
	{
		accessLock.withLock
		{
			accessMainThread.append(Thread.isMainThread)
		}
		return super.fileExists(atPath: path)
	}
}
