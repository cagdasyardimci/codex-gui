import Foundation

extension WorkspaceCoordinatorReducer
{
	static func reduceQuit(
		_ model: inout WorkspaceCoordinatorModel,
		_ action: WorkspaceCoordinatorAction
	) -> [WorkspaceCoordinatorEffect]
	{
		var effects: [WorkspaceCoordinatorEffect] = []
		switch action
		{
		case .quitRequested(let request):
			guard case .idle = model.quit
			else
			{
				return []
			}
			model.pendingQuitCompletion = nil
			model.quitRecoveryFallback = nil
			if model.hasUnobservedOwners
			{
				effects.append(.completeQuit(
					request,
					approved: false
				))
			}
			else if model.hasRemoteOwners
				|| (request.purpose == .termination && model.hasUncertainOwners)
			{
				model.quit = .confirming(request)
				effects.append(.confirmQuit(request))
			}
			else if model.hasUncertainOwners
			{
				effects.append(.completeQuit(
					request,
					approved: false
				))
			}
			else
			{
				beginQuitDrain(
					&model,
					request: request,
					effects: &effects
				)
			}
		case .quitConfirmationFinished(
			let request,
			let approved
		):
			guard case .confirming(let current) = model.quit, current == request
			else
			{
				return []
			}
			if !approved || model.hasUnobservedOwners
				|| (request.purpose == .stopAll && model.hasUncertainOwners)
			{
				model.quit = .idle
				effects.append(.completeQuit(
					request,
					approved: false
				))
			}
			else if model.hasRemoteOwners || model.hasUncertainOwners
			{
				model.quit = .stopping(request)
				effects.append(.stopOwners(
					request,
					model.owners.values.filter(\.requiresRemoteStop).map(\.reference)
				))
				if request.purpose == .termination
				{
					effects.append(.awaitQuitStopDeadline(request))
				}
			}
			else
			{
				beginQuitDrain(
					&model,
					request: request,
					effects: &effects
				)
			}
		case .quitStopDeadlineReached(let request):
			guard request.purpose == .termination,
					case .stopping(let current) = model.quit, current == request
			else
			{
				return []
			}
			// Explicit quit can retire an unresponsive backend, but never clears its
			// unresolved outcomes or command identities. Persistence drains them first.
			model.quitRecoveryFallback = request
			beginQuitDrain(
				&model,
				request: request,
				effects: &effects
			)
		case .quitCancelled(let request):
			guard case .terminating(
				let current,
				_
			) = model.quit, current == request
			else
			{
				return []
			}
			model.quit = .idle
			model.quitRecoveryFallback = nil
			effects.append(.completeQuit(
				request,
				approved: false
			))
		case .quitReservationFailed(
			let request,
			let failure
		):
			let current: WorkspaceQuitRequest?
			switch model.quit
			{
			case .idle:
				current = nil
			case .confirming(let value), .stopping(let value),
					.draining(
					let value,
					_
					), .terminating(
					let value,
					_
					): current = value
			}
			guard current == request
			else
			{
				return []
			}
			model.quit = .idle
			model.message = "Could not save workspace changes before quitting: \(failure.message)"
			effects.append(.completeQuit(
				request,
				approved: false
			))
		case .quitPersistenceDrained(
			let request,
			let result
		):
			guard case .draining(
				let current,
				let capturedOwners
			) = model.quit,
				current == request
			else
			{
				return []
			}
			let ownersUnchanged = capturedOwners == Set(model.owners.values.map(\.reference))
			let allLocalOperationsFinished = model.owners.values.allSatisfy
			{
				!$0.pendingLocalWrites && !$0.managementInProgress
			}
			let approved: Bool
			if case .succeeded = result
			{
				approved = ownersUnchanged && canFinishQuit(
					model,
					request: request
				)
					&& allLocalOperationsFinished
					&& model.pendingCreations.isEmpty && model.pendingCleanup.isEmpty
					&& model.pendingCancellation.isEmpty
			}
			else
			{
				approved = false
			}
			model.quit = approved && request.purpose == .termination ? .terminating(
				request,
				capturedOwners
			) : .idle
			effects.append(.completeQuit(
				request,
				approved: approved
			))
		case .quitCompletionRequested(
			let request,
			let approved,
			let frozenOwners
		):
			guard let pending = model.pendingQuitCompletion, pending.request == request,
					pending.approved == approved
			else
			{
				return []
			}
			model.pendingQuitCompletion = nil
			var accepted = approved && pending
				.owners == Set(model.owners.values.map(\.reference))
				&& canFinishQuit(
					model,
					request: request
				)
			if approved && request.purpose == .termination
			{
				guard case .terminating(
					let current,
					let owners
				) = model.quit,
					current == request
				else
				{
					return []
				}
				accepted = accepted && frozenOwners == owners && model.owners.values.allSatisfy
				{
					!$0.pendingLocalWrites && !$0.managementInProgress
				} && model.pendingCreations.isEmpty && model.pendingCleanup.isEmpty && model
				.pendingCancellation.isEmpty
			}
			if !accepted
			{
				model.quit = .idle
			}
			effects.append(.notifyQuitCompletion(
				request,
				approved: accepted
			))
		default:
			return []
		}
		return effects
	}

	private static func canFinishQuit(
		_ model: WorkspaceCoordinatorModel,
		request: WorkspaceQuitRequest
	) -> Bool
	{
		!model.hasUnobservedOwners
			&& ((!model.hasRemoteOwners && !model.hasUncertainOwners)
				|| (request.purpose == .termination && model.quitRecoveryFallback == request))
	}

	private static func beginQuitDrain(
		_ model: inout WorkspaceCoordinatorModel,
		request: WorkspaceQuitRequest,
		effects: inout [WorkspaceCoordinatorEffect]
	)
	{
		let owners = Set(model.owners.values.map(\.reference))
		model.quit = .draining(
			request,
			owners
		)
		effects.append(.freezeWritesAndDrainQuit(
			request,
			owners
		))
	}

	static func advanceQuit(
		_ model: inout WorkspaceCoordinatorModel,
		effects: inout [WorkspaceCoordinatorEffect]
	)
	{
		guard case .stopping(let request) = model.quit
		else
		{
			return
		}
		let shouldRefuseQuit = model.hasUncertainOwners || model.owners.values.contains
		{
			$0.executionState == .failed && $0.needsReconciliation
		}
		if shouldRefuseQuit && request.purpose == .stopAll
		{
			model.quit = .idle
			effects.append(.completeQuit(
				request,
				approved: false
			))
		}
		else if !model.hasRemoteOwners && !model.hasUncertainOwners
		{
			beginQuitDrain(
				&model,
				request: request,
				effects: &effects
			)
		}
	}
}
