import Foundation

protocol GitTurnBaselineService: Sendable
{
	func capture(_ request: GitTurnBaselineCaptureRequest) async -> GitTurnBaselineResult
	func bind(
		_ reference: GitTurnBaselineReference,
		turnID: String
	) async -> GitTurnBaselineResult
	func lookup(
		repositoryRoot: String,
		threadID: String,
		turnID: String
	) async -> GitTurnBaselineReference?
	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	func discard(_ reference: GitTurnBaselineReference) async
}

/// Files and provenance live outside Git. Only binding an acknowledged turn changes metadata.
/// Capture is repeated and validated, but cannot atomically freeze independently edited files.
actor LocalGitTurnBaselineService: GitTurnBaselineService
{
	static let shared = LocalGitTurnBaselineService()

	private let storageRoot: URL
	private let limits: GitTurnBaselineLimits
	private var records: [UUID: GitTurnBaselineRecord] = [:]
	private var loadTask: Task<[GitTurnBaselineRecord], Never>?
	private var loaded = false

	init(
		storageRoot: URL? = nil,
		limits: GitTurnBaselineLimits = GitTurnBaselineLimits()
	)
	{
		self.storageRoot = storageRoot ?? FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		)[0].appendingPathComponent(
			"CodexGUI/git-turn-baselines",
			isDirectory: true
		)
		self.limits = limits
	}

	func capture(_ request: GitTurnBaselineCaptureRequest) async -> GitTurnBaselineResult
	{
		await loadRecords()
		guard !Task.isCancelled
		else
		{
			return .unavailable(.cancelled)
		}
		let root = storageRoot
		let captureLimits = limits
		let result = await GitSubprocessCancellation.detached
		{
			GitTurnBaselineStorage(
				root: root,
				limits: captureLimits
			).capture(request)
		}
		switch result
		{
		case .failure(let failure): return .unavailable(failure)
		case .success(let record):
			if Task.isCancelled
			{
				await removeRecord(record)
				return .unavailable(.cancelled)
			}
			records[record.reference.identity.id] = record
			await enforceRetention()
			if Task.isCancelled
			{
				records.removeValue(forKey: record.reference.identity.id)
				await removeRecord(record)
				return .unavailable(.cancelled)
			}
			guard records[record.reference.identity.id] != nil
			else
			{
				return .unavailable(
					.lastTurnBaselineUnavailable("The baseline exceeded retention limits.")
				)
			}
			return .captured(record.reference)
		}
	}

	func bind(
		_ reference: GitTurnBaselineReference,
		turnID: String
	) async -> GitTurnBaselineResult
	{
		await loadRecords()
		guard !turnID.isEmpty,
				var record = records[reference.identity.id],
				record.reference.identity == reference.identity,
				record.reference.acceptedTurnID == nil || record.reference.acceptedTurnID == turnID
		else
		{
			return .unavailable(
				.lastTurnBaselineUnavailable("The captured baseline is unavailable.")
			)
		}
		record.reference = record.reference.bound(to: turnID)
		let root = storageRoot
		let writeLimits = limits
		let updated = record
		let saved = await Task.detached
		{
			GitTurnBaselineStorage(
				root: root,
				limits: writeLimits
			).save(updated)
		}.value
		guard saved
		else
		{
			return .unavailable(.lastTurnBaselineUnavailable("Turn binding could not be saved."))
		}
		guard records[reference.identity.id]?.reference.identity == reference.identity
		else
		{
			return .unavailable(.lastTurnBaselineUnavailable("The baseline was evicted."))
		}
		let hasNewerAcceptedBaseline = records.values.contains
		{
			$0.reference.identity.id != reference.identity.id
				&& sameChat(
					$0.reference,
					updated.reference
				)
				&& $0.reference.acceptedTurnID != nil
				&& $0.reference.capturedAt > updated.reference.capturedAt
		}
		if hasNewerAcceptedBaseline
		{
			records.removeValue(forKey: reference.identity.id)
			await removeRecord(updated)
			return .unavailable(.lastTurnBaselineUnavailable("A newer turn baseline is retained."))
		}
		records[reference.identity.id] = updated
		let obsoleteAcceptedBaselines = records.values.filter
		{
			$0.reference.identity.id != reference.identity.id
				&& sameChat(
					$0.reference,
					updated.reference
				)
				&& $0.reference.acceptedTurnID != nil
				&& $0.reference.capturedAt <= updated.reference.capturedAt
		}
		for previous in obsoleteAcceptedBaselines
		{
			records.removeValue(forKey: previous.reference.identity.id)
			await removeRecord(previous)
		}
		await enforceRetention()
		guard records[reference.identity.id] != nil
		else
		{
			return .unavailable(
				.lastTurnBaselineUnavailable("The baseline exceeded retention limits.")
			)
		}
		return .captured(updated.reference)
	}

	func lookup(
		repositoryRoot: String,
		threadID: String,
		turnID: String
	) async -> GitTurnBaselineReference?
	{
		await loadRecords()
		let canonicalRoot = WorkspaceFileIdentity
			.canonicalRootPath(URL(fileURLWithPath: repositoryRoot))
		return records.values.map(\.reference).filter
		{
			$0.identity.repositoryRoot == canonicalRoot
				&& $0.identity.threadID == threadID && $0.acceptedTurnID == turnID
		}.max
		{
			$0.capturedAt < $1.capturedAt
		}
	}

	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		guard request.lastTurnBaseline != nil
			|| (request.lastTurnID != nil && request.owner.selectedThreadID != nil)
		else
		{
			return .unavailable(.lastTurnUnavailable)
		}
		await loadRecords()
		let reference: GitTurnBaselineReference?
		if let explicit = request.lastTurnBaseline
		{
			reference = explicit
		}
		else if let thread = request.owner.selectedThreadID, let turn = request.lastTurnID
		{
			reference = await lookup(
				repositoryRoot: request.repositoryRoot,
				threadID: thread,
				turnID: turn
			)
		}
		else
		{
			reference = nil
		}
		guard let reference
		else
		{
			return .unavailable(.lastTurnUnavailable)
		}
		let canonicalRoot = WorkspaceFileIdentity.canonicalRootPath(
			URL(fileURLWithPath: request.repositoryRoot)
		)
		guard reference.identity.repositoryRoot == canonicalRoot,
				request.owner.selectedThreadID == reference.identity.threadID,
				let ownerPath = request.owner.runtimeOwner?.workspace.canonicalCheckoutPath
		else
		{
			return .unavailable(.baselineOwnershipMismatch)
		}
		let ownerRoot = WorkspaceFileIdentity.canonicalRootPath(URL(fileURLWithPath: ownerPath))
		guard ownerRoot == canonicalRoot
		else
		{
			return .unavailable(.baselineOwnershipMismatch)
		}
		guard let turn = reference.acceptedTurnID, !turn.isEmpty, request.lastTurnID == turn
		else
		{
			return .unavailable(.baselineOwnershipMismatch)
		}
		guard let record = records[reference.identity.id], record.reference == reference
		else
		{
			return .unavailable(
				.lastTurnBaselineUnavailable("The baseline was evicted or is missing.")
			)
		}
		let root = storageRoot
		let comparisonLimits = limits
		return await GitSubprocessCancellation.detached
		{
			GitTurnBaselineStorage(
				root: root,
				limits: comparisonLimits
			).compare(
				record,
				request: request
			)
		}
	}

	func discard(_ reference: GitTurnBaselineReference) async
	{
		await loadRecords()
		guard let record = records[reference.identity.id],
				record.reference.identity == reference.identity
		else
		{
			return
		}
		records.removeValue(forKey: reference.identity.id)
		await removeRecord(record)
	}

	private func sameChat(
		_ lhs: GitTurnBaselineReference,
		_ rhs: GitTurnBaselineReference
	) -> Bool
	{
		lhs.identity.repositoryRoot == rhs.identity.repositoryRoot
			&& lhs.identity.threadID == rhs.identity.threadID
	}

	private func loadRecords() async
	{
		guard !loaded
		else
		{
			return
		}
		if loadTask == nil
		{
			let root = storageRoot
			let storageLimits = limits
			loadTask = Task.detached
			{
				GitTurnBaselineStorage(
					root: root,
					limits: storageLimits
				).load()
			}
		}
		let restored = await loadTask!.value
		guard !loaded
		else
		{
			return
		}
		var obsolete: [GitTurnBaselineRecord] = []
		for record in restored.sorted(by:
			{
				$0.reference.capturedAt > $1.reference.capturedAt
			})
		{
			if records.values.contains(where:
				{
					sameChat(
						$0.reference,
						record.reference
					)
				})
			{
				obsolete.append(record)
			}
			else
			{
				records[record.reference.identity.id] = record
			}
		}
		loaded = true
		loadTask = nil
		for record in obsolete
		{
			await removeRecord(record)
		}
		await enforceRetention()
	}

	private func enforceRetention() async
	{
		for accepted in [true, false]
		{
			while true
			{
				let candidates = records.values.filter
				{
					($0.reference.acceptedTurnID != nil) == accepted
				}
				guard candidates.count > limits.maximumBaselines,
						let oldest = candidates.min(by:
						{
							$0.reference.capturedAt < $1.reference.capturedAt
						})
				else
				{
					break
				}
				records.removeValue(forKey: oldest.reference.identity.id)
				await removeRecord(oldest)
			}
		}
		while retainedBytesExceedLimit(Array(records.values))
		{
			let pending = records.values.filter
			{
				$0.reference.acceptedTurnID == nil
			}
			let candidates = pending.isEmpty ? Array(records.values) : pending
			guard let oldest = candidates.min(by:
				{
					$0.reference.capturedAt < $1.reference.capturedAt
				})
			else
			{
				break
			}
			records.removeValue(forKey: oldest.reference.identity.id)
			await removeRecord(oldest)
		}
	}

	/// Counts logical content and metadata bytes; directory allocation is filesystem-specific.
	private func retainedBytesExceedLimit(_ candidates: [GitTurnBaselineRecord]) -> Bool
	{
		var total = 0
		for record in candidates
		{
			guard let metadata = try? JSONEncoder().encode(record),
					record.reference.byteCount <= limits.maximumRetainedBytes - total
			else
			{
				return true
			}
			total += record.reference.byteCount
			guard metadata.count <= limits.maximumRetainedBytes - total
			else
			{
				return true
			}
			total += metadata.count
		}
		return false
	}

	private func removeRecord(_ record: GitTurnBaselineRecord) async
	{
		let root = storageRoot
		let removalLimits = limits
		await Task.detached
		{
			GitTurnBaselineStorage(
				root: root,
				limits: removalLimits
			)
			.remove(record.reference.identity.id)
		}.value
	}
}
