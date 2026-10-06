import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct WorkspacePersistenceSchedulerTests
{
	private let sessionID = UUID()

	@Test func consecutiveEditsPersistTheLatestDraftAndReleaseSupersededAttachmentLeases(
	) async throws
	{
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let suite = "WorkspacePersistenceSchedulerTests.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(
			defaults: defaults,
			imageStore: DraftImageStore(directory: directory)
		)
		let firstImage = directory.appendingPathComponent("\(UUID().uuidString).png")
		let latestImage = directory.appendingPathComponent("\(UUID().uuidString).png")
		try Data([0x89, 0x50, 0x4E, 0x47]).write(to: firstImage)
		try Data([0x89, 0x50, 0x4E, 0x47]).write(to: latestImage)
		let firstAttachment = ComposerContextItem(
			kind: .image,
			title: "First",
			path: firstImage.path
		)
		let latestAttachment = ComposerContextItem(
			kind: .image,
			title: "Latest",
			path: latestImage.path
		)
		var written: [WorkspaceDraftWrite] = []
		var retained: Set<UUID> = []
		let scheduler = WorkspacePersistenceScheduler(
			writeDraft:
			{
				write in
				written.append(write)
				storage.saveDraft(
					write.draft.text,
					for: directory,
					threadID: "thread"
				)
				storage.saveDraftContext(
					write.draft.context,
					for: directory,
					threadID: "thread"
				)
			},
			rememberReferences:
			{
				_ in
			},
			waitForDraftEdits:
			{
				try? await Task.sleep(for: .seconds(30))
			},
			reserveContext:
			{
				let id = storage.retainContextForRequest($0)
				retained.insert(id)
				return id
			},
			releaseContext:
			{
				retained.remove($0)
				storage.releaseContextForRequest($0)
			}
		)
		var tasks: [Task<Void, Error>] = []
		for revision in 1 ... 20
		{
			tasks.append(scheduler.enqueue(write(
				path: directory.path,
				conversation: .thread("thread"),
				text: "edit \(revision)",
				context: revision == 20 ? [latestAttachment] : [firstAttachment]
			)))
		}
		#expect(FileManager.default.fileExists(atPath: firstImage.path))
		try await scheduler.drain()
		for task in tasks
		{
			try await task.value
		}
		#expect(written.map(\.draft.text) == ["edit 20"])
		#expect(storage.draft(
			for: directory,
			threadID: "thread"
		) == "edit 20")
		#expect(storage.draftContext(
			for: directory,
			threadID: "thread"
		) == [latestAttachment])
		#expect(retained.isEmpty)
		#expect(!FileManager.default.fileExists(atPath: firstImage.path))
		#expect(FileManager.default.fileExists(atPath: latestImage.path))
		#expect(!scheduler.hasPendingWrites())
	}

	@Test func independentConversationsAndCheckoutsKeepTheirOwnLatestDraft() async throws
	{
		var written: [WorkspaceDraftWrite] = []
		let scheduler = WorkspacePersistenceScheduler(
			writeDraft:
			{
				written.append($0)
			},
			waitForDraftEdits:
			{
				try? await Task.sleep(for: .seconds(30))
			}
		)
		let tasks = [
			scheduler.enqueue(write(
				path: "/alpha",
				conversation: .thread("a"),
				text: "old a"
			)),
			scheduler.enqueue(write(
				path: "/alpha",
				conversation: .thread("b"),
				text: "b"
			)),
			scheduler.enqueue(write(
				path: "/beta",
				conversation: .thread("a"),
				text: "beta a"
			)),
			scheduler.enqueue(write(
				path: "/alpha",
				conversation: .thread("a"),
				text: "latest a"
			)),
		]
		try await scheduler.drain()
		for task in tasks
		{
			try await task.value
		}
		#expect(Set(written.map(\.draft.text)) == ["b", "beta a", "latest a"])
		#expect(written.count == 3)
		#expect(written.first(where:
			{
				$0.draft.text == "b"
			})?.conversation == .thread("b"))
		#expect(written.first(where:
			{
				$0.draft.text == "beta a"
			})?.context.workspace
			.canonicalCheckoutPath
			== "/beta")
	}

	@Test func preparedTransferIsAnOrderingBarrierForBothDraftKeys() async throws
	{
		var written: [WorkspaceDraftWrite] = []
		let scheduler = WorkspacePersistenceScheduler(
			writeDraft:
			{
				written.append($0)
			},
			waitForDraftEdits:
			{
				try? await Task.sleep(for: .seconds(30))
			}
		)
		let original = write(
			conversation: .newChat,
			text: "before"
		)
		let submission = submission(
			for: original,
			text: "submitted"
		)
		let thread = MockCodexService().thread
		let prepared = PreparedSubmission(
			submission: submission,
			thread: ThreadDetail(
				summary: thread,
				turns: [],
				nextTurnsCursor: nil
			)
		)
		let tasks = [
			scheduler.enqueue(original),
			scheduler.enqueue(PreparedConversationWrite(
				prepared: prepared,
				draft: submission.draft,
				selectThread: false
			)),
			scheduler.enqueue(write(
				conversation: .newChat,
				text: "after"
			)),
			scheduler.enqueue(write(
				conversation: .thread(thread.id),
				text: "destination edit"
			)),
		]
		try await scheduler.drain()
		for task in tasks
		{
			try await task.value
		}
		#expect(written.filter
		{
			$0.conversation == .newChat
		}.map(\.draft.text)
		== ["before", "", "after"])
		#expect(written.filter
		{
			$0.conversation == .thread(thread.id)
		}.map(\.draft.text)
		== ["submitted", "destination edit"])
	}

	@Test func anotherWorkspaceOrGenerationFormsAnOrderingBoundaryForTheSameDraftKey() async throws
	{
		var written: [String] = []
		let scheduler = WorkspacePersistenceScheduler(
			writeDraft:
			{
				written.append($0.draft.text)
			},
			waitForDraftEdits:
			{
				try? await Task.sleep(for: .seconds(30))
			}
		)
		let tasks = [
			scheduler.enqueue(write(text: "first owner")),
			scheduler.enqueue(write(
				text: "second owner",
				sessionID: UUID()
			)),
			scheduler.enqueue(write(text: "first owner again")),
			scheduler.enqueue(write(
				text: "older generation edit",
				generation: 1
			)),
			scheduler.enqueue(write(
				text: "latest generation edit",
				generation: 1
			)),
		]
		try await scheduler.drain()
		for task in tasks
		{
			try await task.value
		}
		#expect(written == [
			"first owner",
			"second owner",
			"first owner again",
			"latest generation edit"
		])
	}

	@Test func submissionAcknowledgementKeepsReferencesBeforeTheDraftClearAndLaterEdit(
	) async throws
	{
		var events: [String] = []
		let scheduler = WorkspacePersistenceScheduler(
			writeDraft:
			{
				events.append("draft:\($0.draft.text)")
			},
			rememberReferences:
			{
				events.append("references:\($0.threadID)")
			},
			waitForDraftEdits:
			{
				try? await Task.sleep(for: .seconds(30))
			}
		)
		let original = write(
			conversation: .thread("thread"),
			text: "before"
		)
		let tasks = [
			scheduler.enqueue(original),
			scheduler.enqueue(SubmissionAcknowledgementWrite(
				submission: submission(
					for: original,
					text: "submitted"
				),
				threadID: "thread",
				draft: ComposerDraft()
			)),
			scheduler.enqueue(write(
				conversation: .thread("thread"),
				text: "after"
			)),
		]
		try await scheduler.drain()
		for task in tasks
		{
			try await task.value
		}
		#expect(events == ["draft:before", "references:thread", "draft:", "draft:after"])
	}

	@Test func drainCancelsAnActiveDebounceAndFlushesItsDraft() async throws
	{
		let started = PersistenceTestSignal()
		var debounceWasCancelled = false
		var written: [String] = []
		let scheduler = WorkspacePersistenceScheduler(
			writeDraft:
			{
				written.append($0.draft.text)
			},
			waitForDraftEdits:
			{
				started.signal()
				try? await Task.sleep(for: .seconds(30))
				debounceWasCancelled = Task.isCancelled
			}
		)
		let pending = scheduler.enqueue(write(text: "flush me"))
		await started.wait()
		try await scheduler.drain()
		try await pending.value
		#expect(debounceWasCancelled)
		#expect(written == ["flush me"])
	}

	@Test func nestedFlushScopesIncludeChildWritesAndExcludeOtherCheckouts() async throws
	{
		var debounceCalls = 0
		let scheduler = WorkspacePersistenceScheduler(
			writeDraft:
			{
				_ in
			},
			waitForDraftEdits:
			{
				debounceCalls += 1
				try? await Task.sleep(for: .milliseconds(10))
			}
		)
		let outer = scheduler.beginFlushing(projectPaths: ["/alpha"])
		let inner = scheduler.beginFlushing(projectPaths: ["/alpha"])
		scheduler.endFlushing(outer)
		try await scheduler.enqueue(write(
			path: "/alpha",
			text: "child"
		)).value
		#expect(debounceCalls == 0)
		try await scheduler.enqueue(write(
			path: "/beta",
			text: "unrelated"
		)).value
		#expect(debounceCalls == 1)
		scheduler.endFlushing(inner)
		try await scheduler.enqueue(write(
			path: "/alpha",
			text: "after barrier"
		)).value
		#expect(debounceCalls == 2)
		try await scheduler.drain()
	}

	@Test func supersededEditsCannotEraseAnEarlierFailedWrite() async throws
	{
		var attempts = 0
		var written: [String] = []
		let scheduler = WorkspacePersistenceScheduler(
			writeDraft:
			{
				write in
				attempts += 1
				if attempts == 1
				{
					throw PersistenceTestFailure.failed
				}
				if attempts == 2
				{
					throw PersistenceTestFailure.replacementFailed
				}
				written.append(write.draft.text)
			},
			waitForDraftEdits:
			{
				try? await Task.sleep(for: .seconds(30))
			}
		)
		let failed = scheduler.enqueue(write(text: "failed"))
		scheduler.flush()
		_ = await failed.result
		let superseded = scheduler.enqueue(write(text: "superseded"))
		let latest = scheduler.enqueue(write(text: "latest"))
		try await superseded.value
		do
		{
			try await scheduler.drain()
			Issue.record("Expected the original completed failure to remain visible")
		}
		catch let failure as PersistenceTestFailure
		{
			#expect(failure == .failed)
		}
		_ = await latest.result
		let recovered = scheduler.enqueue(write(text: "recovered"))
		try await scheduler.drain()
		try await recovered.value
		#expect(written == ["recovered"])
		#expect(!scheduler.hasPendingWrites())
	}

	@Test func completedTextWriteFailureRemainsVisibleToDrainUntilSameKeySucceeds() async throws
	{
		var shouldFail = true
		let scheduler = WorkspacePersistenceScheduler(writeDraft:
			{
				_ in
				if shouldFail
				{
					throw AppServerError.protocolError("text write failed")
				}
			})
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/drain"
		)
		func write(_ threadID: String) -> WorkspaceDraftWrite
		{
			WorkspaceDraftWrite(
				context: OperationContext(
					workspace: identity,
					generation: 0,
					requestID: UUID()
				),
				conversation: .thread(threadID),
				draft: ComposerDraft(text: "text only")
			)
		}
		let failed = await scheduler.enqueue(write("original")).result
		if case .success = failed
		{
			Issue.record("Expected failed text persistence")
		}
		do
		{
			try await scheduler.drain()
			Issue.record("Drain forgot the completed text-only failure")
		}
		catch
		{
		}
		shouldFail = false
		try await scheduler.enqueue(write("unrelated")).value
		do
		{
			try await scheduler.drain()
			Issue.record("An unrelated key cleared the failed transaction")
		}
		catch
		{
		}
		try await scheduler.enqueue(write("original")).value
		try await scheduler.drain()
	}

	@Test func partialReplacementCannotClearCompletedMultiKeyTransferFailure() async throws
	{
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/drain"
		)
		let context = OperationContext(
			workspace: identity,
			generation: 0,
			requestID: UUID()
		)
		let submission = ComposerSubmission(
			context: context,
			conversation: .newChat,
			draft: ComposerDraft(text: "transfer"),
			inputs: [.text("transfer")],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		let prepared = PreparedSubmission(
			submission: submission,
			thread: ThreadDetail(
				summary: MockCodexService().thread,
				turns: [],
				nextTurnsCursor: nil
			)
		)
		var failDestination = true
		let scheduler = WorkspacePersistenceScheduler(writeDraft:
			{
				write in
				if failDestination, case .thread = write.conversation
				{
					throw AppServerError.protocolError("destination failed")
				}
			})
		let transfer = PreparedConversationWrite(
			prepared: prepared,
			draft: submission.draft,
			selectThread: false
		)
		let failed = await scheduler.enqueue(transfer).result
		if case .success = failed
		{
			Issue.record("Expected failed transfer")
		}
		failDestination = false
		try await scheduler.enqueue(WorkspaceDraftWrite(
			context: context,
			conversation: .newChat,
			draft: ComposerDraft(text: "source only")
		)).value
		do
		{
			try await scheduler.drain()
			Issue.record("Replacing only the source cleared a multi-key failure")
		}
		catch
		{
		}
		try await scheduler.enqueue(transfer).value
		try await scheduler.drain()
	}

	@Test("Scoped drain excludes another checkout's continuing write and completed failure")
	func scopedDrainIsolation() async throws
	{
		let started = PersistenceTestSignal()
		let release = PersistenceTestSignal()
		var failBeta = false
		let scheduler = WorkspacePersistenceScheduler(writeDraft:
			{
				write in
				if write.context.workspace.canonicalCheckoutPath == "/beta"
				{
					started.signal()
					await release.wait()
					if failBeta
					{
						throw PersistenceTestFailure.failed
					}
				}
			})
		let beta = scheduler.enqueue(write(
			path: "/beta",
			text: "beta",
			sessionID: UUID()
		))
		await started.wait()
		let alpha = scheduler.enqueue(write(
			path: "/alpha",
			text: "alpha",
			sessionID: UUID()
		))
		try await alpha.value
		try await scheduler.drain(projectPath: "/alpha")
		#expect(scheduler.hasPendingWrites(projectPath: "/beta"))
		failBeta = true
		release.signal()
		_ = await beta.result
		try await scheduler.drain(projectPath: "/alpha")
		var failed = false
		do
		{
			try await scheduler.drain(projectPath: "/beta")
		}
		catch
		{
			failed = true
		}
		#expect(failed)
		failBeta = false
		try await scheduler.enqueue(write(
			path: "/beta",
			text: "retry",
			sessionID: UUID()
		)).value
		try await scheduler.drain()
		#expect(!scheduler.hasPendingWrites())
	}

	private func write(
		path: String = "/tmp/persistence-scheduler",
		conversation: ConversationKey = .newChat,
		text: String,
		context: [ComposerContextItem] = [],
		sessionID: UUID? = nil,
		generation: Int = 0
	) -> WorkspaceDraftWrite
	{
		WorkspaceDraftWrite(
			context: OperationContext(
				workspace: WorkspaceIdentity(
					sessionID: sessionID ?? self.sessionID,
					canonicalCheckoutPath: path
				),
				generation: generation,
				requestID: UUID()
			),
			conversation: conversation,
			draft: ComposerDraft(
				text: text,
				context: context
			)
		)
	}

	private func submission(
		for write: WorkspaceDraftWrite,
		text: String
	) -> ComposerSubmission
	{
		ComposerSubmission(
			context: write.context,
			conversation: write.conversation,
			draft: ComposerDraft(text: text),
			inputs: [.text(text)],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
	}
}

@MainActor
private final class PersistenceTestSignal
{
	private var signalled = false
	private var continuations: [CheckedContinuation<Void, Never>] = []

	func signal()
	{
		signalled = true
		let pending = continuations
		continuations.removeAll()
		for continuation in pending
		{
			continuation.resume()
		}
	}

	func wait() async
	{
		if signalled
		{
			return
		}
		await withCheckedContinuation
		{
			continuations.append($0)
		}
	}
}

private enum PersistenceTestFailure: Error, Equatable
{
	case failed
	case replacementFailed

}
