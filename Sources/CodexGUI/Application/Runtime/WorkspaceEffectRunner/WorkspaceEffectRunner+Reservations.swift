import Foundation

/// Persistence ordering and captured attachment leases before state publication.
extension WorkspaceEffectRunner
{
	var pendingAcceptedPersistenceCount: Int
	{
		tasks.values.filter
		{
			isPersistenceCapable($0.effect)
		}.count + reservedPersistence.count + reservedComposerCommands.values.filter
		{
			!$0.isCancelled
		}.count
	}

	/// Wait whole finite groups so accepted outcomes can reduce and accept their write chains.
	func awaitAcceptedPersistence() async throws
	{
		while true
		{
			let persistenceEffects = tasks.filter
			{
				isPersistenceCapable($0.value.effect)
			}
			let composerCommands = reservedComposerCommands.filter
			{
				!$0.value.isCancelled
			}
			let groups = persistenceEffects.values.map(\.handle)
				+ composerCommands.values.map(\.handle)
			guard !groups.isEmpty
			else
			{
				return
			}
			let paths = Set((Array(persistenceEffects.keys) + Array(composerCommands.keys))
				.compactMap(\.request.workspace.canonicalCheckoutPath))
			let flushScope = persistence.beginFlushing(projectPaths: paths)
			defer
			{
				persistence.endFlushing(flushScope)
			}
			for group in groups
			{
				_ = await group.wait()
			}
		}
	}

	func drainPersistence(projectPath: String? = nil) async throws
	{
		try await persistence.drain(projectPath: projectPath)
	}

	func hasPendingPersistence(projectPath: String? = nil) -> Bool
	{
		pendingAcceptedPersistenceCount > 0 || persistence
			.hasPendingWrites(projectPath: projectPath)
	}

	private func isPersistenceCapable(_ effect: WorkspaceEffect) -> Bool
	{
		switch effect
		{
		case .validateComposerInput, .releaseUnsentSubmission, .prepareSubmission, .startSubmission,
				.bindGitTurnBaseline, .discardGitTurnBaseline,
				.steer, .persistDraft,
				.persistPreparedConversation, .acknowledgeSubmission, .releaseSubmission,
				.persistPreference, .writeReviewMarker, .saveProjectContext,
				.persistConversationSelection:
			return true
		case .restoreSourceStartup, .connect, .readExecutableVersion, .readModels, .readAccount,
				.restorePreferences,
				.restoreComposer, .loadProjectContext, .readConversationList, .manageConversation,
				.readSelection, .readRecovery, .readCompletedHistory: return true
		case .forkConversation, .compactConversation, .startConversationReview,
				.updateCommandSettings: return true
		case .readConversationHistory(let operation):
			return operation.purpose == .selection || operation.purpose == .recovery
				|| operation.purpose == .completion
		default: return false
		}
	}

	/// Reserve submitted images and persistence order before observers can edit another draft.
	func reserve(
		_ effects: [WorkspaceEffect],
		workspace: WorkspaceIdentity,
		managedWorkspace: TaskWorkspace? = nil
	)
	{
		guard !isShutdown
		else
		{
			return
		}
		for effect in effects
		{
			guard let (context, purpose) = identity(of: effect),
					context.workspace == workspace
			else
			{
				continue
			}
			let key = EffectKey(
				request: RequestKey(context),
				purpose: purpose
			)
			guard !accepted.contains(key)
			else
			{
				continue
			}
			switch effect
			{
			case .forkConversation, .compactConversation, .startConversationReview,
					.updateCommandSettings:
				reserveComposerCommand(
					effect,
					context: context,
					key: key
				)
			case .loadProjectContext(let operation):
				if reservedContextLoads[key] == nil
				{
					do
					{
						let project = try conversationDirectory(operation.context)
						reservedContextLoads[key] = .success(try projectContextStore
							.load(for: project))
					}
					catch
					{
						reservedContextLoads[key] = .failure(error)
					}
				}
			case .saveProjectContext(let operation):
				if reservedPersistence[key] == nil
				{
					do
					{
						let project = try conversationDirectory(operation.context)
						try projectContextStore.save(
							operation.value,
							for: project
						)
						reservedPersistence[key] = Task
						{
						}
					}
					catch
					{
						reservedPersistence[key] = Task
						{
							throw error
						}
					}
				}
			case .readReviewMarkers(let operation):
				if reservedReviewResults[key] == nil
				{
					let marked = operation.identities.filter
					{
						identity in
						reviewMarkerStore?.isReviewed(
							projectPath: context.workspace.canonicalCheckoutPath ?? "",
							reference: identity.reference,
							fingerprint: identity.fingerprint
						) == true
					}
					reservedReviewResults[key] = .review(.markersReceived(
						operation,
						.succeeded(marked)
					))
				}
			case .writeReviewMarker(let operation):
				if reservedReviewResults[key] == nil
				{
					if let path = context.workspace.canonicalCheckoutPath, let reviewMarkerStore
					{
						reviewMarkerStore.setReviewed(
							operation.reviewed,
							projectPath: path,
							reference: operation.identity.reference,
							fingerprint: operation.identity.fingerprint
						)
						reservedReviewResults[key] = .review(.markerPersistenceFinished(
							operation,
							.succeeded(())
						))
					}
					else
					{
						reservedReviewResults[key] = failureAction(
							for: effect,
							context: context,
							failure: OperationFailure(
								message: "Review persistence requires a checkout.",
								outcomeIsUncertain: false
							)
						)
					}
				}
			case .persistPreference(let write):
				if reservedPersistence[key] == nil
				{
					if let storage
					{
						storage.applyPreferenceWrite(write)
						reservedPersistence[key] = Task
						{
						}
					}
					else
					{
						reservedPersistence[key] = Task
						{
							throw AppServerError
								.protocolError("Preference persistence requires storage.")
						}
					}
				}
			case .validateComposerInput(let operation): reserveContext(operation.submission)
			case .prepareSubmission(let submission): reserveContext(submission)
			case .steer(let operation): reserveContext(operation.submission)
			case .persistConversationSelection(
				let context,
				let threadID
			):
				if reservedPersistence[key] == nil
				{
					do
					{
						let project = try conversationDirectory(context)
						guard let storage
						else
						{
							throw AppServerError.protocolError(
								"Selection persistence requires storage."
							)
						}
						storage.saveSelectedThreadID(
							threadID,
							for: project
						)
						reservedPersistence[key] = Task
						{
						}
					}
					catch
					{
						reservedPersistence[key] = Task
						{
							throw error
						}
					}
				}
			case .persistDraft(let write):
				if reservedPersistence[key] ==
					nil
				{
					reservedPersistence[key] = persistence.enqueue(write)
				}
			case .persistPreparedConversation(let write):
				if reservedPersistence[key] ==
					nil
				{
					reservedPersistence[key] = persistence.enqueue(write)
				}
			case .acknowledgeSubmission(let write):
				preparedThreadIDs[write.submission.retainedContextRequestID] = write.threadID
				if reservedPersistence[key] ==
					nil
				{
					reservedPersistence[key] = persistence.enqueue(write)
				}
			case .releaseSubmission(let operation):
				let submission = operation.submission
				let id = submission.retainedContextRequestID
				if ownsReleaseReservation(operation), !durableReferences.contains(id),
					let threadID = preparedThreadIDs[id] ?? submission.context.threadID,
					reservedPersistence[key] == nil
				{
					reservedPersistence[key] = persistence.enqueue(SubmissionAcknowledgementWrite(
						submission: submission,
						threadID: threadID,
						draft: nil
					))
				}
			default: break
			}
		}
	}

	private func reserveContext(_ submission: ComposerSubmission)
	{
		if retainedContexts[submission.retainedContextRequestID] == nil, let storage
		{
			retainedSubmissions[submission.retainedContextRequestID] = submission
			retainedContexts[submission.retainedContextRequestID] =
				storage.retainContextForRequest(submission.draft.context)
		}
	}

	/// An obsolete transport result still owns its captured attachments, never the new draft.
	func finalizeObsoleteSteering(_ operation: SteeringOperation) async throws
	{
		let submission = operation.submission
		let retainedID = submission.retainedContextRequestID
		let transportIsObsolete = hasObservedSubscription
			&& (subscription?.workspace != operation.context.workspace
				|| subscription?.generation != operation.context.generation)
		let ownsCapturedReservation = retainedSubmissions[retainedID]?.context
			.isSameRequest(as: operation.context) == true
		guard retainedContexts[retainedID] != nil, !Task.isCancelled, transportIsObsolete,
				ownsCapturedReservation,
				let threadID = operation.context.threadID
		else
		{
			return
		}
		let persistenceTask = persistence.enqueue(SubmissionAcknowledgementWrite(
			submission: submission,
			threadID: threadID,
			draft: nil
		))
		try await persistenceTask.value
		durableReferences.insert(retainedID)
		_ = releaseReservation(submission)
	}

	func ownsReleaseReservation(_ operation: WorkspaceSubmissionReleaseOperation) -> Bool
	{
		let submission = operation.submission
		guard operation.context.workspace == submission.context.workspace
		else
		{
			return false
		}
		if let captured = retainedSubmissions[submission.retainedContextRequestID]
		{
			return captured.context.isSameRequest(as: submission.context)
				&& captured.conversation == submission.conversation
				&& captured.draft == submission.draft
		}
		return storage == nil || submission.draft.context.isEmpty
	}

	func releaseReservation(_ submission: ComposerSubmission) -> Bool
	{
		let retainedID = submission.retainedContextRequestID
		let boundThreadID = preparedThreadIDs[retainedID] ?? submission.context.threadID
		// Unknown preparation outcomes keep their lease until real backend ownership resolves.
		let hasNoAttachments = submission.draft.context.isEmpty
		let hasResolvedThread = boundThreadID != nil || hasNoAttachments
		let hasDurableReferences = durableReferences.contains(retainedID) || hasNoAttachments
		guard hasResolvedThread, hasDurableReferences
		else
		{
			return false
		}
		if let id = retainedContexts.removeValue(forKey: retainedID)
		{
			storage?.releaseContextForRequest(id)
		}
		retainedSubmissions.removeValue(forKey: retainedID)
		preparedThreadIDs.removeValue(forKey: retainedID)
		durableReferences.remove(retainedID)
		return true
	}

	func persistedReferences(
		for context: OperationContext,
		threadID: String
	) -> [ComposerContextItem]?
	{
		guard let storage, let path = context.workspace.canonicalCheckoutPath
		else
		{
			return nil
		}
		return storage.sentReferences(
			for: URL(fileURLWithPath: path),
			threadID: threadID
		)
	}

	func finalizeReservationOnShutdown(_ submission: ComposerSubmission)
	{
		let retainedID = submission.retainedContextRequestID
		if durableReferences.contains(retainedID) || submission.draft.context.isEmpty
		{
			_ = releaseReservation(submission)
			return
		}
		guard let storage, let id = retainedContexts[retainedID],
				let threadID = preparedThreadIDs[retainedID] ?? submission.context.threadID
		else
		{
			// Forced shutdown cannot invent a conversation or restore an attachment removed by
			// the user. Unknown-thread leases survive only for shared storage's process lifetime.
			return
		}
		let persistenceTask = persistence.enqueue(SubmissionAcknowledgementWrite(
			submission: submission,
			threadID: threadID,
			draft: nil
		))
		Task
		{
			do
			{
				try await persistenceTask.value
				storage.releaseContextForRequest(id)
			}
			catch
			{
				// A failed durable write retains the shared lease rather than pruning its image.
			}
		}
	}
}
