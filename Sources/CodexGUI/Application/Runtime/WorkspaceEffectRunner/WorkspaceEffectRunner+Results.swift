import Foundation

/// Typed failure results, including commands with uncertain remote outcomes.
extension WorkspaceEffectRunner
{
	func failure(
		forCancelled pending: PendingEffect,
		context: OperationContext
	) -> OperationFailure
	{
		let message = "Local operation cancelled; no remote outcome is established."
		guard case .respond(let operation) = pending.effect,
				pending.hasStartedResponse
		else
		{
			return failure(
				for: pending.effect,
				message: message
			)
		}

		let ownsCurrentTransport = !hasObservedSubscription
			|| (subscription?.workspace == context.workspace
				&& subscription?.generation == context.generation)
		let mayHaveBeenSent = ownsCurrentTransport
			? (service.responseMayHaveBeenSent(to: operation.interactionID) ?? true)
			: true
		return OperationFailure(
			message: message,
			outcomeIsUncertain: mayHaveBeenSent
		)
	}

	func failure(
		for effect: WorkspaceEffect,
		error: Error
	) -> OperationFailure
	{
		if let failure = error as? ServerQueueExecutionFailure
		{
			return failure.failure
		}
		if case AppServerError.requestRejected(let message) = error,
			ConversationLock.isAnotherApp(message)
		{
			return OperationFailure(
				message: message,
				outcomeIsUncertain: false
			)
		}
		if case .prepareSubmission = effect, let rejection = error as? SubmissionPreparationRejected
		{
			return rejection.failure
		}
		if case .respond = effect, let writeFailure = error as? ProtocolWriteFailure
		{
			return OperationFailure(
				message: writeFailure.localizedDescription,
				outcomeIsUncertain: writeFailure.mayHaveBeenSent
			)
		}

		// An unsent final RPC does not disprove mutations from earlier RPCs in a command.
		return failure(
			for: effect,
			message: error.localizedDescription
		)
	}

	func failure(
		for effect: WorkspaceEffect,
		message: String
	) -> OperationFailure
	{
		if case .remoteAccess(let operation) = effect
		{
			return OperationFailure(
				message: BackendDiagnosticsBuffer.displaySafeText(message),
				outcomeIsUncertain: operation.command != .refresh
			)
		}
		let uncertain: Bool
		switch effect
		{
		case .prepareSubmission, .startSubmission, .steer, .forkConversation,
				.compactConversation, .startConversationReview,
				.updateCommandSettings: uncertain = true
		default: uncertain = false
		}
		return OperationFailure(
			message: message,
			outcomeIsUncertain: uncertain
		)
	}

	func failureAction(
		for effect: WorkspaceEffect,
		context: OperationContext,
		failure: OperationFailure
	) -> WorkspaceAction
	{
		switch effect
		{
		case .serverQueue(let operation): return .composer(.serverQueueFinished(
				operation,
				.failed(failure)
			))
		case .bindGitTurnBaseline(let operation):
			return .execution(.gitTurnBaselineBindingFinished(
				context,
				threadID: operation.reference.identity.threadID,
				turnID: operation.turnID,
				.unavailable(.failed(failure.message))
			))
		case .discardGitTurnBaseline(let operation):
			return .execution(.gitTurnBaselineDiscarded(
				context,
				operation.reference.identity.id
			))
		case .forkConversation(let request):
			return .composerCommand(.forkFinished(
				request,
				.failed(failure)
			))
		case .compactConversation(let operation):
			return .composerCommand(.compactAcknowledged(
				operation,
				.failed(failure)
			))
		case .startConversationReview(let operation):
			return .composerCommand(.reviewAcknowledged(
				operation,
				.failed(failure)
			))
		case .updateCommandSettings(let operation):
			return .composerCommand(.settingsFinished(
				operation,
				.failed(failure)
			))
		case .readReviewMarkers(let operation): return .review(.markersReceived(
				operation,
				.failed(failure)
			))
		case .writeReviewMarker(let operation): return .review(.markerPersistenceFinished(
				operation,
				.failed(failure)
			))
		case .remoteAccess(let operation):
			return .remoteAccess(.finished(
				operation,
				.failed(failure),
				usageRuntime.now()
			))
		case .connect: return .connection(.connectionFinished(
				context,
				.failed(failure)
			))
		case .readExecutableVersion: return .connection(.executableVersionReceived(
				context,
				.failed(failure)
			))
		case .validateComposerInput(let operation):
			return .workspaceLifecycle(.inputPreparationFinished(
				operation,
				.failed(failure)
			))
		case .restoreSourceStartup:
			return .workspaceLifecycle(.sourceStartupRestored(
				context,
				.failed(failure)
			))
		case .releaseUnsentSubmission, .restorePreferences:
			return .workspaceLifecycle(.capabilityRejected(
				context,
				reason: failure.message
			))
		case .restoreComposer, .readBackendDiagnostics, .validateReusableReferences:
			return .workspaceLifecycle(.capabilityRejected(
				context,
				reason: failure.message
			))
		case .readConversationHistory(let operation): return .conversations(.historyReceived(
				operation,
				.failed(failure)
			))
		case .readConversationPage(let operation): return .conversations(.earlierTurnsReceived(
				operation,
				.failed(failure)
			))
		case .readTurnReferences(let operation): return .conversations(.turnReferencesReceived(
				operation,
				.failed(failure)
			))
		case .expireTurnPreviews: return .conversations(.cacheExpired(
				context,
				observedAt: usageRuntime.now()
			))
		case .readTurnContents(let operation): return .conversations(.turnContentsReceived(
				operation,
				.failed(failure),
				observedAt: usageRuntime.now()
			))
		case .readConversationList(let operation): return .conversations(.threadListReceived(
				operation,
				.failed(failure)
			))
		case .archiveProjectChats(let operation): return .conversations(.projectArchiveFinished(
				operation,
				ProjectArchiveResult(
					archivedThreadIDs: [],
					failure: failure
				)
			))
		case .manageConversation: return .conversations(.managementFinished(
				context,
				.failed(failure)
			))
		case .persistConversationSelection: return .conversations(.selectionPersistenceFinished(
				context,
				.failed(failure)
			))
		case .readSelection: return .conversations(.selectionReceived(
				context,
				.failed(failure)
			))
		case .loadProjectContext(let operation): return .contextNavigation(.contextReceived(
				operation,
				.failed(failure)
			))
		case .saveProjectContext(let operation): return .contextNavigation(
				.contextPersistenceFinished(
					operation,
					.failed(failure)
				)
			)
		case .readSkills(let operation): return .contextNavigation(.skillsReceived(
				operation,
				.failed(failure)
			))
		case .searchMessages(
			let operation,
			_,
			_
		):
			return .contextNavigation(.messageSearchFinished(
				operation,
				.failed(failure)
			))
		case .readUsage(let operation): return .usage(.limitsReceived(
				operation,
				.failed(failure)
			))
		case .readModels: return .preferences(.modelsReceived(
				context,
				.failed(failure)
			))
		case .signOut: return .preferences(.signOutFinished(
				context,
				.failed(failure)
			))
		case .beginSignIn: return .preferences(.signInURLReceived(
				context,
				.failed(failure)
			))
		case .persistPreference: return .preferences(.persistenceFinished(
				context,
				.failed(failure)
			))
		case .readAccount: return .preferences(.accountReceived(
				context,
				.failed(failure)
			))
		case .prepareSubmission: return .execution(.submissionPrepared(
				context,
				.failed(failure)
			))
		case .interrupt: return .execution(.interruptionFinished(
				context,
				.failed(failure)
			))
		case .respond: return .execution(.interactionResponseFinished(
				context,
				.failed(failure)
			))
		case .steer(let operation): return .execution(.steeringTransportFinished(
				operation,
				.failed(failure)
			))
		case .readRecovery: return .execution(.reconciliationFinished(
				context,
				.failed(failure)
			))
		case .readCompletedHistory(let operation): return .execution(.completedHistoryReceived(
				operation,
				.failed(failure)
			))
		case .persistPreparedConversation: return .execution(.preparedPersistenceFinished(
				context,
				.failed(failure)
			))
		case .releaseSubmission(let operation): return .composer(.submissionReleaseFinished(
				operation,
				.failed(failure)
			))
		case .acknowledgeSubmission: return .execution(.draftAcknowledgementFinished(
				context,
				.failed(failure)
			))
		case .startSubmission: return .execution(.submissionFailed(
				context,
				failure
			))
		case .persistDraft: return .composer(.draftPersistenceFinished(
				context,
				.failed(failure)
			))
		default: preconditionFailure("A finite operation must have a typed failure action.")
		}
	}
}
