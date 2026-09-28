import Foundation

/// One scheduler per shared LocalStorage instance orders accepted persistence transactions.
@MainActor
final class WorkspacePersistenceScheduler
{
	private enum ValueKey: Hashable
	{
		case draft(ConversationKey)
		case sentReferences
	}

	private struct Key: Hashable
	{
		let projectPath: String
		let value: ValueKey
	}

	private struct PendingWrite
	{
		let sequence: Int
		let task: Task<Void, Error>
	}

	private let writeDraft: (WorkspaceDraftWrite) async throws -> Void
	private let rememberReferences: (WorkspaceSentReferenceWrite) async throws -> Void
	private let reserveContext: ([ComposerContextItem]) -> UUID?
	private let releaseContext: (UUID) -> Void
	private struct FailedTransaction
	{
		var remainingKeys: Set<Key>
		let error: Error
		let retentionID: UUID?
	}
	private var failedTransactions: [FailedTransaction] = []
	private var pending: [Key: PendingWrite] = [:]
	private var sequence = 0

	init(writeDraft: @escaping (WorkspaceDraftWrite) async throws -> Void)
	{
		self.writeDraft = writeDraft
		rememberReferences =
		{
			_ in
		}
		reserveContext =
		{
			_ in nil
		}
		releaseContext =
		{
			_ in
		}
	}

	init(
		writeDraft: @escaping (WorkspaceDraftWrite) async throws -> Void,
		rememberReferences: @escaping (WorkspaceSentReferenceWrite) async throws -> Void,
		reserveContext: @escaping ([ComposerContextItem]) -> UUID? =
		{
			_ in nil
		},
		releaseContext: @escaping (UUID) -> Void =
		{
			_ in
		}
	)
	{
		self.writeDraft = writeDraft
		self.rememberReferences = rememberReferences
		self.reserveContext = reserveContext
		self.releaseContext = releaseContext
	}

	convenience init(storage: LocalStorage)
	{
		self.init(
			writeDraft:
			{
				[weak storage] write in
				guard let storage, let path = write.context.workspace.canonicalCheckoutPath
				else
				{
					throw AppServerError
						.protocolError("Draft persistence requires a checkout and storage.")
				}
				let project = URL(fileURLWithPath: path)
				let threadID: String?
				switch write.conversation
				{
				case .newChat: threadID = nil
				case .thread(let id): threadID = id
				}
				storage.saveDraft(
					write.draft.text,
					for: project,
					threadID: threadID
				)
				storage.saveDraftContext(
					write.draft.context,
					for: project,
					threadID: threadID
				)
			},
			rememberReferences:
			{
				[weak storage] write in
				guard let storage, let path = write.context.workspace.canonicalCheckoutPath
				else
				{
					throw AppServerError
						.protocolError("Reference persistence requires a checkout and storage.")
				}
				let project = URL(fileURLWithPath: path)
				let existingReferences = storage.sentReferences(
					for: project,
					threadID: write.threadID
				)
				let existingReferenceIDs = Set(existingReferences.map(\.id))
				let newReferences = write.items.filter
				{
					!existingReferenceIDs.contains($0.id)
				}

				storage.rememberSentReferences(
					newReferences,
					for: project,
					threadID: write.threadID
				)
			},
			reserveContext:
			{
				[weak storage] items in
				storage?.retainContextForRequest(items)
			},
			releaseContext:
			{
				[weak storage] id in
				storage?.releaseContextForRequest(id)
			}
		)
	}

	/// Registration is synchronous. Multi-key transactions reserve every touched key together.
	func enqueue(_ write: WorkspaceDraftWrite) -> Task<Void, Error>
	{
		enqueue(
			context: write.context,
			values: [.draft(write.conversation)],
			retainedItems: write.draft.context
		)
		{
			[writeDraft] in
			try await writeDraft(write)
		}
	}

	func enqueue(_ write: PreparedConversationWrite) -> Task<Void, Error>
	{
		let context = write.prepared.submission.context
		guard context.threadID == nil, write.prepared.submission.conversation == .newChat
		else
		{
			return Task
			{
			}
		}
		let destination = ConversationKey.thread(write.prepared.thread.summary.id)
		var values: [ValueKey] = [.draft(destination)]
		if write.clearSource
		{
			values.append(.draft(write.prepared.submission.conversation))
		}
		return enqueue(
			context: context,
			values: values,
			retainedItems: write.draft.context
		)
		{
			[writeDraft] in
			try await writeDraft(WorkspaceDraftWrite(
				context: context,
				conversation: destination,
				draft: write.draft
			))
			if write.clearSource
			{
				try await writeDraft(WorkspaceDraftWrite(
					context: context,
					conversation: write.prepared.submission.conversation,
					draft: ComposerDraft()
				))
			}
		}
	}

	func enqueue(_ write: SubmissionAcknowledgementWrite) -> Task<Void, Error>
	{
		let context = write.submission.context
		var values: [ValueKey] = [.sentReferences]
		if write.draft != nil
		{
			values.append(.draft(.thread(write.threadID)))
		}
		return enqueue(
			context: context,
			values: values,
			retainedItems: write.submission.draft.context + (write.draft?.context ?? [])
		)
		{
			[writeDraft, rememberReferences] in
			// References own the images before clearing an acknowledged draft can prune them.
			try await rememberReferences(WorkspaceSentReferenceWrite(
				context: context,
				threadID: write.threadID,
				items: write.submission.draft.context
			))
			if let draft = write.draft
			{
				try await writeDraft(WorkspaceDraftWrite(
					context: context,
					conversation: .thread(write.threadID),
					draft: draft
				))
			}
		}
	}

	/// Lifecycle callers can await accepted writes before restoring from disk or exiting.
	/// A caller must stop accepting new writes to establish a final shutdown barrier.
	func hasPendingWrites(projectPath: String? = nil) -> Bool
	{
		let path = projectPath.map(canonicalPath)
		return pending.keys.contains
		{
			path == nil || $0.projectPath == path
		}
		|| failedTransactions.contains
		{
			$0.remainingKeys.contains
			{
				path == nil || $0.projectPath == path
			}
		}
	}

	func drain(projectPath: String? = nil) async throws
	{
		let path = projectPath.map(canonicalPath)
		while true
		{
			let writes = pending.filter
			{
				path == nil || $0.key.projectPath == path
			}.values
			guard !writes.isEmpty
			else
			{
				break
			}
			for write in writes
			{
				_ = await write.task.result
			}
		}
		if let failure = failedTransactions.first(where:
			{
				$0.remainingKeys.contains
				{
					path == nil || $0.projectPath == path
				}
			})
		{
			throw failure.error
		}
	}

	private func canonicalPath(_ path: String) -> String
	{
		URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
	}

	private func enqueue(
		context: OperationContext,
		values: [ValueKey],
		retainedItems: [ComposerContextItem],
		operation: @escaping () async throws -> Void
	) -> Task<Void, Error>
	{
		guard let path = context.workspace.canonicalCheckoutPath
		else
		{
			return Task
			{
				throw AppServerError.protocolError("Persistence requires a checkout.")
			}
		}
		let canonicalPath = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
			.path
		let keys = Set(values.map
		{
			Key(
				projectPath: canonicalPath,
				value: $0
			)
		})
		let retentionID = retainedItems.isEmpty ? nil : reserveContext(retainedItems)
		let predecessors = keys.compactMap
		{
			pending[$0]?.task
		}
		sequence += 1
		let currentSequence = sequence
		let task = Task
		{
			// Failed predecessors establish ordering but cannot poison a later independent write.
			for previous in predecessors
			{
				_ = await previous.result
			}
			defer
			{
				for key in keys where self.pending[key]?.sequence == currentSequence
				{
					self.pending.removeValue(forKey: key)
				}
			}
			do
			{
				try await operation()
				self.settleSuccessfulTransaction(
					keys: keys,
					retentionID: retentionID
				)
			}
			catch
			{
				self.failedTransactions.append(FailedTransaction(
					remainingKeys: keys,
					error: error,
					retentionID: retentionID
				))
				throw error
			}
		}
		for key in keys
		{
			pending[key] = PendingWrite(
				sequence: currentSequence,
				task: task
			)
		}
		return task
	}

	private func settleSuccessfulTransaction(
		keys: Set<Key>,
		retentionID: UUID?
	)
	{
		if let retentionID
		{
			releaseContext(retentionID)
		}
		for index in failedTransactions.indices
		{
			failedTransactions[index].remainingKeys.subtract(keys)
		}
		let superseded = failedTransactions.filter
		{
			$0.remainingKeys.isEmpty
		}
		failedTransactions.removeAll
		{
			$0.remainingKeys.isEmpty
		}
		for failure in superseded
		{
			if let id = failure.retentionID
			{
				releaseContext(id)
			}
		}
	}
}
