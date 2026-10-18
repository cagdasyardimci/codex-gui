import Foundation
import Testing

@testable import CodexGUI

@Suite("Workspace lifecycle reductions")
struct WorkspaceCoordinatorReducerTests
{
	@Test func lateCreationPreservesRecordWithoutRedirectingSelection()
	{
		var model = fixture()
		let request = creation(model)
		_ = reduce(
			&model,
			.creationRequested(request)
		)
		_ = reduce(
			&model,
			.sourceSelected
		)
		let result = reduce(
			&model,
			.creationFinished(
				request,
				.succeeded(workspace(taskID: request.taskID))
			)
		)
		#expect(model.workspaces.count == 1)
		#expect(model.pendingCreations.isEmpty)
		#expect(model.selectedOwner == .source(sessionID: model.source.sessionID))
		#expect(result.isEmpty)
	}

	@Test func foreignCreationResultCannotRetireMatchingPendingRequest()
	{
		var model = fixture()
		let request = creation(model)
		_ = reduce(
			&model,
			.creationRequested(request)
		)
		let foreign = WorkspaceCreationRequest(
			requestID: request.requestID,
			source: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: "/tmp/foreign"
			),
			selectionEpoch: request.selectionEpoch,
			taskID: request.taskID,
			name: request.name,
			ownerSessionID: request.ownerSessionID
		)
		_ = reduce(
			&model,
			.creationFinished(
				foreign,
				.succeeded(workspace(taskID: request.taskID))
			)
		)
		#expect(model.pendingCreations[request.requestID] == request)
		#expect(model.workspaces.isEmpty)
	}

	@Test func leavingAndReturningToSourceRejectsOldVerifiedSelection()
	{
		var model = fixture()
		let record = workspace()
		model.workspaces[record.id] = record
		let request = WorkspaceSelectionRequest(
			requestID: UUID(),
			ownerSessionID: UUID(),
			selectionEpoch: 1,
			expected: record
		)
		_ = reduce(
			&model,
			.selectionRequested(request)
		)
		_ = reduce(
			&model,
			.sourceSelected
		)
		#expect(reduce(
			&model,
			.selectionVerified(
				request,
				.succeeded(record)
			)
		).isEmpty)
		#expect(model.pendingSelection == nil)
		#expect(model.selectedOwner == .source(sessionID: model.source.sessionID))
	}

	@Test func lateCommandCancelsReservedCleanupBeforePersistenceCanAuthorizeRemoval()
	{
		var model = fixture()
		let (record, reference) = register(&model)
		var observation = WorkspaceLifecycleObservation(reference: reference)
		observation.executionState = .completed
		observation.pendingLocalWrites = true
		_ = reduce(
			&model,
			.ownerObserved(observation)
		)
		let request = WorkspaceCleanupRequest(
			requestID: UUID(),
			owner: reference,
			expected: record
		)
		let reserved = reduce(
			&model,
			.cleanupRequested(request)
		)
		#expect(reserved.count == 1)
		#expect(model.pendingCleanup[record.id]?.stage == .reserving)
		observation.cleanupReservation = request.requestID
		_ = reduce(
			&model,
			.ownerObserved(observation)
		)
		_ = reduce(
			&model,
			.cleanupReserved(
				request,
				accepted: true
			)
		)
		#expect(model.pendingCleanup[record.id]?.stage == .draining)
		observation.unresolvedCommands = true
		let cancelled = reduce(
			&model,
			.ownerObserved(observation)
		)
		#expect(cancelled.contains
		{
			if case .cancelRequest(request.requestID) = $0
			{
				return true
			}
			return false
		})
		#expect(model.pendingCleanup[record.id] == nil)
		#expect(reduce(
			&model,
			.cleanupPersistenceDrained(
				request,
				.succeeded(())
			)
		).isEmpty)
		#expect(model.workspaces[record.id]?.phase == .active)
	}

	@Test func omittingOwnerCannotBypassUnboundPreparingTaskBarrier()
	{
		var model = fixture()
		let (record, reference) = register(&model)
		var observation = WorkspaceLifecycleObservation(reference: reference)
		observation.executionState = .running
		_ = reduce(
			&model,
			.ownerObserved(observation)
		)
		let request = WorkspaceCleanupRequest(
			requestID: UUID(),
			owner: nil,
			expected: record
		)
		#expect(reduce(
			&model,
			.cleanupRequested(request)
		).isEmpty)
		#expect(model.pendingCleanup.isEmpty)
	}

	@Test func boundUnopenedAndUncertainComposerOwnersCannotBeCleanedUp()
	{
		var model = fixture()
		var record = workspace()
		record.threadID = "bound"
		model.workspaces[record.id] = record
		let unopened = WorkspaceCleanupRequest(
			requestID: UUID(),
			owner: nil,
			expected: record
		)
		#expect(reduce(
			&model,
			.cleanupRequested(unopened)
		).isEmpty)
		let reference = register(
			&model,
			record: record
		).1
		var observation = WorkspaceLifecycleObservation(reference: reference)
		observation.composerOutcomeUncertain = true
		_ = reduce(
			&model,
			.ownerObserved(observation)
		)
		#expect(reduce(
			&model,
			.cleanupRequested(WorkspaceCleanupRequest(
				requestID: UUID(),
				owner: reference,
				expected: record
			))
		).isEmpty)
	}

	@Test func quitWaitsForEveryCommandOwnerThenDrainsLocalWritesWithoutAnotherStop()
	{
		var model = fixture()
		let alpha = register(&model).1
		let beta = register(&model).1
		var a = WorkspaceLifecycleObservation(reference: alpha)
		var b = WorkspaceLifecycleObservation(reference: beta)
		a.executionState = .running
		b.executionState = .completed
		b.unresolvedCommands = true
		b.pendingLocalWrites = true
		_ = reduce(
			&model,
			.ownerObserved(a)
		)
		_ = reduce(
			&model,
			.ownerObserved(b)
		)
		let request = WorkspaceQuitRequest(requestID: UUID())
		_ = reduce(
			&model,
			.quitRequested(request)
		)
		let stop = reduce(
			&model,
			.quitConfirmationFinished(
				request,
				approved: true
			)
		)
		#expect(stop.count == 1)
		if case .stopOwners(
			_,
			let owners
		) = stop.first
		{
			#expect(Set(owners) == [alpha, beta])
		}
		else
		{
			Issue.record("Expected both captured Stop owners")
		}
		a.executionState = .completed
		_ = reduce(
			&model,
			.ownerObserved(a)
		)
		if case .stopping = model.quit
		{
		}
		else
		{
			Issue.record("Command owner still blocks quit")
		}
		b.unresolvedCommands = false
		let drain = reduce(
			&model,
			.ownerObserved(b)
		)
		#expect(drain.contains
		{
			if case .freezeWritesAndDrainQuit = $0
			{
				return true
			}
			return false
		})
		b.pendingLocalWrites = false
		_ = reduce(
			&model,
			.ownerObserved(b)
		)
		let done = reduce(
			&model,
			.quitPersistenceDrained(
				request,
				.succeeded(())
			)
		)
		#expect(done.contains
		{
			if case .completeQuit(
				_,
				approved: true
			) = $0
			{
				return true
			}
			return false
		})
	}

	@Test func obsoleteQuitCompletionCannotApproveNewQuitAndComposerUncertaintyRefusesExit()
	{
		var model = fixture()
		let request = WorkspaceQuitRequest(requestID: UUID())
		_ = reduce(
			&model,
			.quitRequested(request)
		)
		let foreign = WorkspaceQuitRequest(requestID: UUID())
		#expect(reduce(
			&model,
			.quitPersistenceDrained(
				foreign,
				.succeeded(())
			)
		).isEmpty)
		if case .draining(
			let current,
			_
		) = model.quit
		{
			#expect(current == request)
		}
		else
		{
			Issue.record("Original drain was retired by an obsolete result")
		}
		_ = reduce(
			&model,
			.quitPersistenceDrained(
				request,
				.succeeded(())
			)
		)
		let owner = register(&model).1
		var observation = WorkspaceLifecycleObservation(reference: owner)
		observation.composerOutcomeUncertain = true
		_ = reduce(
			&model,
			.ownerObserved(observation)
		)
		_ = reduce(
			&model,
			.quitCompletionRequested(
				request,
				approved: true,
				frozenOwners: []
			)
		)
		let refusal = reduce(
			&model,
			.quitRequested(foreign)
		)
		#expect(refusal.contains
		{
			if case .completeQuit(
				_,
				approved: false
			) = $0
			{
				return true
			}
			return false
		})
		#expect(!model.hasRemoteOwners)
	}

	@Test func quitDrainFreezesNewLifecycleWorkAndRechecksPendingLocalWrites()
	{
		var model = fixture()
		let reference = register(&model).1
		var observation = WorkspaceLifecycleObservation(reference: reference)
		observation.pendingLocalWrites = true
		_ = reduce(
			&model,
			.ownerObserved(observation)
		)
		let request = WorkspaceQuitRequest(requestID: UUID())
		let effects = reduce(
			&model,
			.quitRequested(request)
		)
		#expect(effects.contains
		{
			if case .freezeWritesAndDrainQuit = $0
			{
				return true
			}
			return false
		})
		#expect(!model.acceptsNewWork)
		#expect(reduce(
			&model,
			.creationRequested(creation(model))
		).isEmpty)
		let refused = reduce(
			&model,
			.quitPersistenceDrained(
				request,
				.succeeded(())
			)
		)
		#expect(refused.contains
		{
			if case .completeQuit(
				_,
				approved: false
			) = $0
			{
				return true
			}
			return false
		})
		#expect(model.acceptsNewWork)
	}

	@Test func registeredOwnerWithoutObservationCannotApproveQuit()
	{
		var model = fixture()
		_ = register(&model)
		let request = WorkspaceQuitRequest(requestID: UUID())
		let effects = reduce(
			&model,
			.quitRequested(request)
		)
		#expect(model.hasUncertainOwners)
		#expect(effects.contains
		{
			if case .completeQuit(
				_,
				approved: false
			) = $0
			{
				return true
			}
			return false
		})
	}

	@Test func failedLocalDrainCannotApproveIdleQuit()
	{
		var model = fixture()
		let request = WorkspaceQuitRequest(requestID: UUID())
		_ = reduce(
			&model,
			.quitRequested(request)
		)
		let effects = reduce(
			&model,
			.quitPersistenceDrained(
				request,
				.failed(OperationFailure(
					message: "Draft write failed",
					outcomeIsUncertain: false
				))
			)
		)
		#expect(effects.contains
		{
			if case .completeQuit(
				_,
				approved: false
			) = $0
			{
				return true
			}
			return false
		})
	}

	@Test func interleavedOwnerTransitionsRetainSessionOwnershipAndRetiredSessionIsRejected()
	{
		var model = fixture()
		let alpha = register(&model).1
		let beta = register(&model).1
		var a = WorkspaceLifecycleObservation(reference: alpha)
		a.executionState = .running
		_ = reduce(
			&model,
			.ownerObserved(a)
		)
		_ = reduce(
			&model,
			.ownerObserved(WorkspaceLifecycleObservation(reference: beta))
		)
		a.executionState = .awaitingApproval
		let effects = reduce(
			&model,
			.ownerObserved(a)
		)
		if case .ownerTransition(
			let previous,
			let current
		) = effects.first
		{
			#expect(previous?.reference == alpha)
			#expect(previous?
				.executionState == .running)
			#expect(current.reference == alpha)
		}
		else
		{
			Issue.record("Missing captured owner transition")
		}
		let foreign = WorkspaceLifecycleOwnerReference(
			owner: .managed(
				workspaceID: model.workspaces.keys.first!,
				sessionID: UUID()
			),
			workspace: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: alpha.workspace.canonicalCheckoutPath
			)
		)
		#expect(reduce(
			&model,
			.ownerObserved(WorkspaceLifecycleObservation(reference: foreign))
		).isEmpty)
	}

	@Test func staleRecoveryCannotRemoveNewlyCreatedRecord()
	{
		var model = fixture()
		let recovery = WorkspaceRecoveryRequest(
			requestID: UUID(),
			recordsRevision: 0
		)
		_ = reduce(
			&model,
			.recoveryRequested(recovery)
		)
		let create = creation(model)
		_ = reduce(
			&model,
			.creationRequested(create)
		)
		_ = reduce(
			&model,
			.creationFinished(
				create,
				.succeeded(workspace(taskID: create.taskID))
			)
		)
		_ = reduce(
			&model,
			.recoveryFinished(
				recovery,
				.succeeded([])
			)
		)
		#expect(model.workspaces.count == 1)
		#expect(model.pendingRecovery == nil)
	}

	@Test func failedRemovalRecoversDurablePhaseBeforeReleasingOwner()
	{
		var model = fixture()
		let (record, reference) = register(&model)
		let request = WorkspaceCleanupRequest(
			requestID: UUID(),
			owner: reference,
			expected: record
		)
		var observation = WorkspaceLifecycleObservation(reference: reference)
		_ = reduce(
			&model,
			.ownerObserved(observation)
		)
		_ = reduce(
			&model,
			.cleanupRequested(request)
		)
		observation.cleanupReservation = request.requestID
		_ = reduce(
			&model,
			.ownerObserved(observation)
		)
		_ = reduce(
			&model,
			.cleanupReserved(
				request,
				accepted: true
			)
		)
		_ = reduce(
			&model,
			.cleanupPersistenceDrained(
				request,
				.succeeded(())
			)
		)
		let failed = reduce(
			&model,
			.cleanupFinished(
				request,
				.failed(OperationFailure(
					message: "Git removal failed",
					outcomeIsUncertain: false
				))
			)
		)
		#expect(model.pendingCleanup[record.id]?.stage == .recovering)
		#expect(!failed.contains
		{
			if case .releaseCleanup = $0
			{
				return true
			}
			return false
		})
		guard let recovery = model.pendingRecovery
		else
		{
			Issue.record("Expected captured recovery")
			return
		}
		#expect(recovery.cleanup == request)
		#expect(recovery.requestID == request.requestID)
		#expect(recovery.recordsRevision == model.recordsRevision)
		_ = reduce(
			&model,
			.sourceSelected
		)
		let epoch = model.selectionEpoch
		var durable = record
		durable.phase = .removing
		let accepted = reduce(
			&model,
			.recoveryFinished(
				recovery,
				.succeeded([TaskWorkspaceRecovery(
					workspace: durable,
					kind: .removalInterrupted
				)])
			)
		)
		#expect(model.workspaces[record.id] == durable)
		#expect(model.pendingCleanup[record.id] == nil)
		#expect(model.selectedOwner == .source(sessionID: model.source.sessionID))
		#expect(model.selectionEpoch == epoch)
		#expect(accepted.contains
		{
			if case .managedRecordRecovered(
				let owner,
				let expected,
				let recovered
			) = $0
			{
				return owner == reference && expected == record && recovered == durable
			}
			return false
		})
		#expect(accepted.contains
		{
			if case .releaseCleanup(let released) = $0
			{
				return released == request
			}
			return false
		})
	}

	@Test func failedRecoveryKeepsReservationUntilFreshRetry()
	{
		var model = fixture()
		let (record, reference) = register(&model)
		let request = WorkspaceCleanupRequest(
			requestID: UUID(),
			owner: reference,
			expected: record
		)
		model.pendingCleanup[record.id] = WorkspaceCleanupTransition(
			request: request,
			stage: .removing
		)
		var observation = WorkspaceLifecycleObservation(reference: reference)
		observation.cleanupReservation = request.requestID
		model.owners[reference.owner] = observation
		_ = reduce(
			&model,
			.cleanupFinished(
				request,
				.failed(OperationFailure(
					message: "Git failure",
					outcomeIsUncertain: false
				))
			)
		)
		guard let first = model.pendingRecovery
		else
		{
			Issue.record("Expected recovery")
			return
		}
		_ = reduce(
			&model,
			.recoveryFinished(
				first,
				.failed(OperationFailure(
					message: "Read failure",
					outcomeIsUncertain: false
				))
			)
		)
		#expect(model.pendingCleanup[record.id]?.stage == .recovering)
		let retry = WorkspaceRecoveryRequest(
			requestID: UUID(),
			recordsRevision: model.recordsRevision
		)
		_ = reduce(
			&model,
			.recoveryRequested(retry)
		)
		var durable = record
		durable.phase = .removing
		_ = reduce(
			&model,
			.recoveryFinished(
				retry,
				.succeeded([TaskWorkspaceRecovery(
					workspace: durable,
					kind: .removalInterrupted
				)])
			)
		)
		#expect(model.pendingCleanup[record.id] == nil)
		#expect(model.workspaces[record.id] == durable)
	}

	@Test func recoveryConflictPrevalidatesAllOwnersBeforeThawOrRetirement()
	{
		var model = fixture()
		let first = register(&model)
		let second = register(&model)
		let ordered = model.registeredOwners.keys.filter
		{
			if case .managed = $0
			{
				return true
			}
			return false
		}
		let earlier = ordered[0] == first.1.owner ? first : second
		let later = ordered[1] == first.1.owner ? first : second
		let earlierCleanup = WorkspaceCleanupRequest(
			requestID: UUID(),
			owner: earlier.1,
			expected: earlier.0
		)
		let laterCleanup = WorkspaceCleanupRequest(
			requestID: UUID(),
			owner: later.1,
			expected: later.0
		)
		for (record, reference, request) in [
			(earlier.0, earlier.1, earlierCleanup),
			(later.0, later.1, laterCleanup)
		]
		{
			var observation = WorkspaceLifecycleObservation(reference: reference)
			observation.cleanupReservation = request.requestID
			model.owners[reference.owner] = observation
			model.pendingCleanup[record.id] = WorkspaceCleanupTransition(
				request: request,
				stage: .recovering
			)
		}
		let recovery = WorkspaceRecoveryRequest(
			requestID: UUID(),
			recordsRevision: model.recordsRevision
		)
		_ = reduce(
			&model,
			.recoveryRequested(recovery)
		)
		var removed = earlier.0
		removed.phase = .checkoutRemoved
		var conflicting = later.0
		conflicting.threadID = "Foreign durable binding"
		let effects = reduce(
			&model,
			.recoveryFinished(
				recovery,
				.succeeded([
					TaskWorkspaceRecovery(
						workspace: removed,
						kind: .checkoutRemoved
					),
					TaskWorkspaceRecovery(
						workspace: conflicting,
						kind: .active
					)
				])
			)
		)
		#expect(model.workspaces[earlier.0.id] == earlier.0)
		#expect(model.workspaces[later.0.id] == later.0)
		#expect(model.registeredOwners[earlier.1.owner] == earlier.1.workspace)
		#expect(model.pendingCleanup[earlier.0.id]?.stage == .recovering)
		#expect(model.pendingCleanup[later.0.id] == nil)
		#expect(model.recoveryIssues[later.0.id] == .ownershipConflict)
		#expect(!effects.contains
		{
			if case .managedRecordRecovered = $0
			{
				return true
			}
			if case .removeOwner = $0
			{
				return true
			}
			return false
		})
		#expect(effects.contains
		{
			if case .managedRecordRecoveryConflicted(
				let owner,
				let expected,
				let cleanup,
				_
			) = $0
			{
				return owner == later.1 && expected == later.0 && cleanup == laterCleanup
			}
			return false
		})
		#expect(!effects.contains
		{
			if case .releaseCleanup(let cleanup) = $0
			{
				return cleanup == earlierCleanup
			}
			return false
		})
	}

	@Test func missingDurableOwnerRejectsRecoveryBeforeRetiringAnotherOwner()
	{
		var model = fixture()
		let missing = register(&model)
		let surviving = register(&model)
		model.owners[missing.1.owner] = WorkspaceLifecycleObservation(reference: missing.1)
		model.owners[surviving.1.owner] = WorkspaceLifecycleObservation(reference: surviving.1)
		let recovery = WorkspaceRecoveryRequest(
			requestID: UUID(),
			recordsRevision: model.recordsRevision
		)
		_ = reduce(
			&model,
			.recoveryRequested(recovery)
		)
		var removed = surviving.0
		removed.phase = .checkoutRemoved
		let effects = reduce(
			&model,
			.recoveryFinished(
				recovery,
				.succeeded([TaskWorkspaceRecovery(
					workspace: removed,
					kind: .checkoutRemoved
				)])
			)
		)
		#expect(model.workspaces[missing.0.id] == missing.0)
		#expect(model.workspaces[surviving.0.id] == surviving.0)
		#expect(model.registeredOwners[missing.1.owner] == missing.1.workspace)
		#expect(model.registeredOwners[surviving.1.owner] == surviving.1.workspace)
		#expect(model.recoveryIssues[missing.0.id] == .ownershipConflict)
		#expect(effects.contains
		{
			if case .managedRecordRecoveryConflicted(
				let owner,
				let expected,
				_,
				_
			) = $0
			{
				return owner == missing.1 && expected == missing.0
			}
			return false
		})
		#expect(!effects.contains
		{
			if case .managedRecordRecovered = $0
			{
				return true
			}
			if case .removeOwner = $0
			{
				return true
			}
			return false
		})
	}

	@Test func approvedTerminationRemainsFrozenUntilDeferredDeliveryRevalidatesOwners()
	{
		var model = fixture()
		let request = WorkspaceQuitRequest(requestID: UUID())
		_ = reduce(
			&model,
			.quitRequested(request)
		)
		_ = reduce(
			&model,
			.quitPersistenceDrained(
				request,
				.succeeded(())
			)
		)
		#expect(!model.acceptsNewWork)
		#expect(reduce(
			&model,
			.creationRequested(creation(model))
		).isEmpty)
		let references = Set(model.owners.values.map(\.reference))
		let accepted = reduce(
			&model,
			.quitCompletionRequested(
				request,
				approved: true,
				frozenOwners: references
			)
		)
		#expect(accepted.contains
		{
			if case .notifyQuitCompletion(
				_,
				approved: true
			) = $0
			{
				return true
			}
			return false
		})
		#expect(!model.acceptsNewWork)

		var changed = fixture()
		let second = WorkspaceQuitRequest(requestID: UUID())
		_ = reduce(
			&changed,
			.quitRequested(second)
		)
		_ = reduce(
			&changed,
			.quitPersistenceDrained(
				second,
				.succeeded(())
			)
		)
		var observation = changed.owners.values.first!
		observation.composerOutcomeUncertain = true
		_ = reduce(
			&changed,
			.ownerObserved(observation)
		)
		let refused = reduce(
			&changed,
			.quitCompletionRequested(
				second,
				approved: true,
				frozenOwners: Set(changed.owners.values.map(\.reference))
			)
		)
		#expect(refused.contains
		{
			if case .notifyQuitCompletion(
				_,
				approved: false
			) = $0
			{
				return true
			}
			return false
		})
		#expect(changed.acceptsNewWork)
	}

	@Test func failedStopAllRejectsQuitButKeepsCommandOwnershipUntilItsExit()
	{
		var model = fixture()
		var observation = model.owners.values.first!
		observation.executionState = .running
		observation.unresolvedCommands = true
		_ = reduce(
			&model,
			.ownerObserved(observation)
		)
		let request = WorkspaceQuitRequest(
			requestID: UUID(),
			purpose: .stopAll
		)
		_ = reduce(
			&model,
			.quitRequested(request)
		)
		_ = reduce(
			&model,
			.quitConfirmationFinished(
				request,
				approved: true
			)
		)
		observation.executionState = .failed
		observation.needsReconciliation = true
		let effects = reduce(
			&model,
			.ownerObserved(observation)
		)
		#expect(effects.contains
		{
			if case .completeQuit(
				_,
				approved: false
			) = $0
			{
				return true
			}
			return false
		})
		#expect(model.hasRemoteOwners)
		#expect(model.acceptsNewWork)
	}

	private func fixture() -> WorkspaceCoordinatorModel
	{
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/source"
		)
		var model = WorkspaceCoordinatorModel(source: identity)
		let reference = WorkspaceLifecycleOwnerReference(
			owner: model.selectedOwner,
			workspace: identity
		)
		model.owners[reference.owner] = WorkspaceLifecycleObservation(reference: reference)
		return model
	}

	private func creation(_ model: WorkspaceCoordinatorModel) -> WorkspaceCreationRequest
	{
		WorkspaceCreationRequest(
			requestID: UUID(),
			source: model.source,
			selectionEpoch: model.selectionEpoch,
			taskID: "task",
			name: "Task",
			ownerSessionID: UUID()
		)
	}

	private func workspace(taskID: String = "task") -> TaskWorkspace
	{
		let id = UUID()
		return TaskWorkspace(
			id: id,
			taskID: taskID,
			threadID: nil,
			sourceProjectPath: "/tmp/source",
			repositoryGitDirectory: "/tmp/source/.git",
			branch: "codex/task/\(id)",
			checkoutPath: "/tmp/task/\(id)",
			baseCommit: "base",
			sourceWasDirty: false,
			createdAt: Date(timeIntervalSince1970: 10),
			phase: .active
		)
	}

	private func register(
		_ model: inout WorkspaceCoordinatorModel,
		record: TaskWorkspace? = nil
	)
		-> (TaskWorkspace, WorkspaceLifecycleOwnerReference)
	{
		let record = record ?? workspace()
		let session = UUID()
		let reference = WorkspaceLifecycleOwnerReference(
			owner: .managed(
				workspaceID: record.id,
				sessionID: session
			),
			workspace: WorkspaceIdentity(
				sessionID: session,
				canonicalCheckoutPath: record.checkoutPath
			)
		)
		model.workspaces[record.id] = record
		model.registeredOwners[reference.owner] = reference.workspace
		return (record, reference)
	}

	private func reduce(
		_ model: inout WorkspaceCoordinatorModel,
		_ action: WorkspaceCoordinatorAction
	)
		-> [WorkspaceCoordinatorEffect]
	{
		WorkspaceCoordinatorReducer.reduce(
			&model,
			action
		)
	}
}
