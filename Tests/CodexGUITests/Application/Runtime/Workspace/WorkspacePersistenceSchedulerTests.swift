import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
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
