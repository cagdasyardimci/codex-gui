import Foundation

extension WorkspaceLifecycleReducer
{
	static func reduceReservations(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceLifecycleAction
	) -> WorkspaceReduction
	{
		let result = WorkspaceReduction()
		switch action
		{
		case .managedRecordRecoveryConflicted(
			let owner,
			let expected,
			let cleanup,
			let message
		):
			guard owner == reference(model), model.lifecycle.managedWorkspace == expected
			else
			{
				return result
			}
			if let cleanup
			{
				guard cleanup.owner == owner, cleanup.expected == expected,
						model.lifecycle.lastCleanupRequestID == cleanup.requestID
				else
				{
					return result
				}
			}
			if let current = model.lifecycle.cleanupReservation
			{
				guard current == cleanup
				else
				{
					return result
				}
				model.lifecycle.cleanupReservation = nil
			}
			model.lifecycle.managedOwnershipConflict = message
			model.lifecycle.statusMessage = message
		case .managedRecordRecovered(
			let owner,
			let expected,
			let recovered
		):
			guard owner == reference(model), model.lifecycle.managedWorkspace == expected,
					recovered.hasSameOwnership(as: expected),
					recovered.threadID == expected.threadID,
					recovered.phase == .active || recovered.phase == .removing || recovered
					.phase == .checkoutRemoved
			else
			{
				return result
			}
			model.lifecycle.managedWorkspace = recovered
			model.lifecycle.managedOwnershipConflict = nil
		case .cleanupReserved(let request):
			guard request.owner == reference(model), model.lifecycle.cleanupReservation == nil,
					model.lifecycle.quitReservation == nil, !blocksCleanup(model),
					case .managed(
					let id,
					_
					) = reference(model).owner,
					let managed = model.lifecycle.managedWorkspace,
					id == managed.id, managed == request.expected,
					(managed.phase == .active || managed.phase == .removing)
			else
			{
				return result
			}
			model.lifecycle.cleanupReservation = request
			model.lifecycle.lastCleanupRequestID = request.requestID
		case .cleanupReleased(let request):
			guard model.lifecycle.cleanupReservation == request,
					request.owner == reference(model)
			else
			{
				return result
			}
			model.lifecycle.cleanupReservation = nil
		case .quitFrozen(
			let request,
			let owner
		):
			guard owner == reference(model), model.lifecycle.cleanupReservation == nil,
					model.lifecycle.quitReservation == nil
			else
			{
				return result
			}
			model.lifecycle.quitReservation = WorkspaceQuitReservation(
				requestID: request.requestID,
				reference: owner
			)
		case .quitThawed(
			let request,
			let owner
		):
			guard model.lifecycle.quitReservation == WorkspaceQuitReservation(
				requestID: request.requestID,
				reference: owner
			), owner == reference(model)
			else
			{
				return result
			}
			model.lifecycle.quitReservation = nil
		default: break
		}
		return result
	}

	static func reduceInputPreparation(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceLifecycleAction
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		switch action
		{
		case .inputPreparationRequested(let operation):
			guard WorkspaceEligibility(model: model).acceptsPreparation(operation)
			else
			{
				return result
			}
			model.lifecycle.pendingInputPreparation = operation
			result.effects = [.validateComposerInput(operation)]
		case .inputPreparationFinished(
			let operation,
			let outcome
		):
			guard model.lifecycle.pendingInputPreparation?.context == operation.context
			else
			{
				return result
			}
			model.lifecycle.pendingInputPreparation = nil
			let captured = operation.submission
			guard WorkspaceEligibility(model: model).acceptsPreparation(operation),
					case .succeeded(let inputs) = outcome
			else
			{
				if case .failed(let failure) = outcome
				{
					model.lifecycle.statusMessage = failure.message
				}
				result.effects = [.releaseUnsentSubmission(captured)]
				return result
			}
			let submission = ComposerSubmission(
				context: captured.context,
				conversation: captured.conversation,
				draft: captured.draft,
				inputs: inputs,
				skills: captured.skills,
				modelID: captured.modelID,
				effort: captured.effort,
				preferences: captured.preferences,
				retainedContextRequestID: captured
					.retainedContextRequestID,
				projectContextRevision: captured
					.projectContextRevision,
				collaborationMode: captured.collaborationMode,
				serviceTier: captured.serviceTier,
				queuedMessageID: captured.queuedMessageID,
				serverQueueEntry: captured.serverQueueEntry,
				queueSteeringTransfer: captured.queueSteeringTransfer,
				queuedSteeringInput: captured.queuedSteeringInput
			)
			let action: WorkspaceAction
			switch operation
			{
			case .submission: action = .execution(.submissionRequested(submission))
			case .steering(let steering): action = .execution(.steeringRequested(
					SteeringOperation(
						context: steering.context,
						submission: submission
					)
				))
			}
			let eligibility = WorkspaceEligibility(model: model)
			let accepted: Bool
			switch operation
			{
			case .submission: accepted = eligibility.acceptsSubmission(submission)
			case .steering(let steering): accepted = eligibility.acceptsSteering(
					SteeringOperation(
						context: steering.context,
						submission: submission
					)
				)
			}
			guard accepted
			else
			{
				result.effects = [.releaseUnsentSubmission(captured)]
				return result
			}
			result = ExecutionReducer.reduce(
				&model,
				action
			)
			let composer = ComposerReducer.reduce(
				&model,
				action
			)
			result.merge(composer)
			if result.effects.isEmpty
			{
				result.effects = [.releaseUnsentSubmission(captured)]
			}
		case .unsentSubmissionReleased: break
		default: break
		}
		return result
	}

}
