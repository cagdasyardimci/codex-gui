import Foundation

private struct SubmissionStoppedBeforeSend: Error
{
}

struct SubmissionStartFailure: Error
{
	let failure: OperationFailure
	let pendingCapture: PendingGitTurnBaselineCapture?
}

/// Finite backend and persistence effects with checkout ownership validation.
extension WorkspaceEffectRunner
{
	func perform(
		_ effect: WorkspaceEffect,
		context: OperationContext,
		persistenceTask: Task<Void, Error>?,
		contextLoadTask: Task<ProjectContext, Error>?,
		managedWorkspace: TaskWorkspace?
	) async throws -> WorkspaceAction
	{
		switch effect
		{
		case .bindGitTurnBaseline(let operation):
			try Task.checkCancellation()
			guard isGitTurnBaselineBindingCurrent(operation)
			else
			{
				throw CancellationError()
			}
			let result = await gitTurnBaselineService.bind(
				operation.reference,
				turnID: operation.turnID
			)
			return .execution(.gitTurnBaselineBindingFinished(
				context,
				threadID: operation.reference.identity.threadID,
				turnID: operation.turnID,
				result
			))
		case .discardGitTurnBaseline(let operation):
			await gitTurnBaselineService.discard(operation.reference)
			return .execution(.gitTurnBaselineDiscarded(
				operation.context,
				operation.reference.identity.id
			))
		case .forkConversation, .compactConversation, .startConversationReview,
				.updateCommandSettings:
			return await performComposerCommand(
				effect,
				context: context,
				managedWorkspace: managedWorkspace
			)
		case .readReviewMarkers, .writeReviewMarker:
			guard let identity = identity(of: effect),
					let action = reservedReviewResults.removeValue(
					forKey: EffectKey(
						request: RequestKey(context),
						purpose: identity.1
					)
					)
			else
			{
				throw AppServerError.protocolError("Review operation was not reserved.")
			}
			return action
		case .respond(let operation):
			try Task.checkCancellation()
			let ownsCurrentTransport = !hasObservedSubscription
				|| (subscription?.workspace == operation.context.workspace
					&& subscription?.generation == operation.context.generation)
			guard ownsCurrentTransport
			else
			{
				throw AppServerError.disconnected
			}

			let key = EffectKey(
				request: RequestKey(operation.context),
				purpose: .response(operation.interactionID)
			)
			tasks[key]?.hasStartedResponse = true
			try await service.respondAndWait(
				to: operation.interactionID,
				with: operation.response
			)
			return .execution(.interactionResponseFinished(
				operation.context,
				.succeeded(())
			))
		case .validateComposerInput(let operation):
			return try preparedComposerInput(operation)
		case .releaseUnsentSubmission(let submission):
			let id = submission.retainedContextRequestID
			if let captured = retainedSubmissions[id],
				captured.context.isSameRequest(as: submission.context),
				captured.draft == submission.draft,
				let lease = retainedContexts.removeValue(forKey: id)
			{
				storage?.releaseContextForRequest(lease)
				retainedSubmissions.removeValue(forKey: id)
				preparedThreadIDs.removeValue(forKey: id)
				durableReferences.remove(id)
			}
			return .workspaceLifecycle(.unsentSubmissionReleased(context))
		case .restoreSourceStartup: return try restoredSourceStartup(context)
		case .restorePreferences:
			guard let storage
			else
			{
				throw AppServerError.protocolError("Preference restoration requires storage.")
			}
			return .preferences(.restored(storage.preferenceRestoration))
		case .restoreComposer: return try restoredComposer(context)
		case .readBackendDiagnostics:
			return .workspaceLifecycle(.diagnosticsReceived(
				context,
				service.backendDiagnostics
			))
		case .validateReusableReferences(let operation):
			let valid = operation.items.filter
			{
				$0
					.kind != .image ||
					($0.path.map
					{
						FileManager.default.fileExists(atPath: $0)
					} ?? false)
			}
			return .workspaceLifecycle(.reusableReferencesReceived(
				operation,
				valid
			))
		case .connect:
			try await verifyWorkspace(managedWorkspace)
			try await service.connect()
			return .connection(.connectionFinished(
				context,
				.succeeded(())
			))
		case .readExecutableVersion:
			try await verifyWorkspace(managedWorkspace)
			let version = try await service.executableVersion()
			return .connection(.executableVersionReceived(
				context,
				.succeeded(version)
			))
		case .readSelection:
			let detail = try await readConversation(
				context,
				allowsUnselectedCheckout: true,
				managedWorkspace: managedWorkspace
			)
			return .conversations(.selectionReceived(
				context,
				.succeeded(detail)
			))
		case .readConversationHistory(let operation):
			let detail = try await readConversation(
				operation.context,
				managedWorkspace: managedWorkspace
			)
			return .conversations(.historyReceived(
				operation,
				.succeeded(detail)
			))
		case .readConversationPage(let operation):
			guard let path = context.workspace.canonicalCheckoutPath,
					operation.pageScope.generation == context.generation
			else
			{
				throw AppServerError.protocolError("History page scope does not match its request.")
			}
			try CheckoutIdentity.validate(
				cwd: operation.pageScope.projectPath,
				expectedDirectory: URL(fileURLWithPath: path)
			)
			try await verifyWorkspace(managedWorkspace)
			guard let threadID = context.threadID
			else
			{
				throw AppServerError.protocolError("A history page requires a thread.")
			}
			if let boundThreadID = managedWorkspace?.threadID, boundThreadID != threadID
			{
				throw TaskWorkspaceError.ownershipConflict(
					"History page targets another bound thread."
				)
			}
			let page = try await service.loadEarlierTurns(
				threadId: threadID,
				cursor: operation.pageScope.cursor
			)
			return .conversations(.earlierTurnsReceived(
				operation,
				.succeeded(HistoryPage(
					turns: page.turns,
					nextCursor: page.nextCursor
				))
			))
		case .readConversationList(let operation):
			let project = try conversationDirectory(context)
			try await verifyWorkspace(managedWorkspace)
			let threads = try await service.threads(
				for: project,
				archived: operation.archived
			)
			let scoped = threads.filter
			{
				(operation.boundThreadID == nil || operation.boundThreadID == $0.id)
					&& (try? CheckoutIdentity.validate(
						cwd: $0.cwd,
						expectedDirectory: project
					)) !=
					nil
			}
			return .conversations(.threadListReceived(
				operation,
				.succeeded(scoped)
			))
		case .manageConversation(let operation):
			_ = try await readConversation(
				context,
				managedWorkspace: managedWorkspace
			)
			guard let threadID = context.threadID
			else
			{
				throw AppServerError.protocolError("Conversation management requires a thread.")
			}
			switch operation
			{
			case .rename(
				_,
				let name
			): try await service.renameThread(
					id: threadID,
					name: name
				)
			case .archive: try await service.archiveThread(id: threadID)
			case .delete: try await service.deleteThread(id: threadID)
			case .unarchive: try await service.unarchiveThread(id: threadID)
			}
			return .conversations(.managementFinished(
				context,
				.succeeded(())
			))
		case .persistConversationSelection:
			try await persistenceTask?.value
			return .conversations(.selectionPersistenceFinished(
				context,
				.succeeded(())
			))
		case .loadProjectContext(let operation):
			guard let contextLoadTask
			else
			{
				throw AppServerError.protocolError("Project context load was not reserved.")
			}
			return .contextNavigation(.contextReceived(
				operation,
				.succeeded(try await contextLoadTask.value)
			))
		case .saveProjectContext(let operation):
			try await persistenceTask?.value
			return .contextNavigation(.contextPersistenceFinished(
				operation,
				.succeeded(())
			))
		case .searchMessages(
			let operation,
			let threads,
			let totalThreadCount
		):
			let results = try await searchMessagesInBackground(
				operation,
				threads: threads,
				totalThreadCount: totalThreadCount
			)
			return .contextNavigation(.messageSearchFinished(
				operation,
				.succeeded(results)
			))
		case .readSkills(let operation):
			guard (0 ... 1).contains(operation.attempt)
			else
			{
				throw AppServerError.protocolError(
					"Skill refresh attempt is outside its bounded cycle."
				)
			}
			let project = try conversationDirectory(context)
			try await verifyWorkspace(managedWorkspace)
			let catalog = try await service.skills(for: project)
			return .contextNavigation(.skillsReceived(
				operation,
				.succeeded(catalog)
			))
		case .readUsage(let operation):
			let snapshot = try await service.rateLimits()
			let fetchedAt = usageRuntime.now()
			return .usage(.limitsReceived(
				operation,
				.succeeded(UsageObservation(
					snapshot: snapshot,
					fetchedAt: fetchedAt,
					freshnessDeadline: fetchedAt.addingTimeInterval(usageRuntime.freshnessDuration)
				))
			))
		case .readModels:
			return .preferences(.modelsReceived(
				context,
				.succeeded(try await service.models())
			))
		case .beginSignIn:
			return .preferences(.signInURLReceived(
				context,
				.succeeded(try await service
					.startBrowserLogin())
			))
		case .persistPreference(let write):
			_ = write
			guard let persistenceTask
			else
			{
				throw AppServerError.protocolError("Preference write was not reserved.")
			}
			try await persistenceTask.value
			return .preferences(.persistenceFinished(
				context,
				.succeeded(())
			))
		case .readAccount:
			let account = try await service.accountStatus()
			return .preferences(.accountReceived(
				context,
				.succeeded(account)
			))
		case .prepareSubmission(let submission):
			return try await prepareSubmission(
				submission,
				context: context,
				managedWorkspace: managedWorkspace
			)
		case .startSubmission(let prepared):
			return try await startPreparedSubmission(
				prepared,
				context: context,
				managedWorkspace: managedWorkspace
			)
		case .interrupt(let operation):
			try await service.interrupt(
				threadId: operation.context.threadID!,
				turnId: operation.context.turnID!
			)
			return .execution(.interruptionFinished(
				context,
				.succeeded(())
			))
		case .steer(let operation):
			try await verifyWorkspace(managedWorkspace)
			let turnID: String
			do
			{
				turnID = try await service.steerTurn(
					threadId: operation.context.threadID!,
					expectedTurnId: operation.context.turnID!,
					inputs: operation.submission.inputs
				)
			}
			catch
			{
				try await finalizeObsoleteSteering(operation)
				throw error
			}
			try await finalizeObsoleteSteering(operation)
			return .execution(.steeringTransportFinished(
				operation,
				.succeeded(turnID)
			))
		case .readRecovery(let operation), .readCompletedHistory(let operation):
			let detail = try await readConversation(
				operation.context,
				allowsUnselectedCheckout: true,
				managedWorkspace: managedWorkspace
			)
			if case .readRecovery = effect
			{
				return .execution(.reconciliationFinished(
					context,
					.succeeded(detail)
				))
			}
			return .execution(.completedHistoryReceived(
				operation,
				.succeeded(detail)
			))
		case .persistPreparedConversation(let write):
			try await persistenceTask?.value
			return .execution(.preparedPersistenceFinished(
				context,
				.succeeded(write.prepared)
			))
		case .acknowledgeSubmission(let write):
			try await persistenceTask?.value
			durableReferences.insert(write.submission.retainedContextRequestID)
			return .execution(.draftAcknowledgementFinished(
				context,
				.succeeded(SubmissionDraftAcknowledgement(
					submission: write.submission,
					threadID: write.threadID,
					cleared: write.draft != nil,
					references: persistedReferences(
						for: write.submission.context,
						threadID: write.threadID
					)
				))
			))
		case .releaseSubmission(let operation):
			let submission = operation.submission
			guard ownsReleaseReservation(operation)
			else
			{
				throw AppServerError
					.protocolError("Submission release has no captured reservation.")
			}
			try await persistenceTask?.value
			let hasBoundThread = preparedThreadIDs[submission.retainedContextRequestID] != nil
				|| submission.context.threadID != nil
			if hasBoundThread
			{
				durableReferences.insert(submission.retainedContextRequestID)
			}
			let threadID = preparedThreadIDs[submission.retainedContextRequestID] ?? submission
				.context.threadID
			let references = threadID.flatMap
			{
				persistedReferences(
					for: submission.context,
					threadID: $0
				)
			}
			let released = releaseReservation(submission)
			return .composer(.submissionReleaseFinished(
				operation,
				.succeeded(SubmissionReservationRelease(
					submission: submission,
					threadID: threadID,
					references: references,
					released: released
				))
			))
		case .persistDraft:
			try await persistenceTask?.value
			return .composer(.draftPersistenceFinished(
				context,
				.succeeded(())
			))
		default:
			preconditionFailure("Subscription and cancellation effects are synchronous.")
		}
	}

	private func searchMessagesInBackground(
		_ operation: MessageSearchOperation,
		threads: [SearchableThread],
		totalThreadCount: Int
	) async throws -> MessageSearchResults
	{
		let searchTask = Task.detached(priority: .userInitiated)
		{
			try Task.checkCancellation()
			let results = MessageSearch.search(
				query: operation.query,
				threads: threads,
				totalThreadCount: totalThreadCount,
				isCancelled:
				{
					Task.isCancelled
				}
			)
			try Task.checkCancellation()
			return results
		}

		return try await withTaskCancellationHandler
		{
			try await searchTask.value
		}
		onCancel:
		{
			searchTask.cancel()
		}
	}

	private func prepareSubmission(
		_ submission: ComposerSubmission,
		context: OperationContext,
		managedWorkspace: TaskWorkspace?
	) async throws -> WorkspaceAction
	{
		guard let path = context.workspace.canonicalCheckoutPath
		else
		{
			throw AppServerError.protocolError("Submission requires a checkout.")
		}
		let directory = URL(fileURLWithPath: path)
		try await verifyWorkspace(managedWorkspace)
		let detail: ThreadDetail
		if let threadID = context.threadID
		{
			detail = try await service.resumeThread(
				id: threadID,
				expectedDirectory: managedWorkspace == nil ? nil : directory
			)
		}
		else
		{
			detail = try await service.startThread(
				in: directory,
				model: submission.modelID
			)
		}

		try Task.checkCancellation()
		try validateThread(
			detail.summary,
			workspace: managedWorkspace
		)
		preparedThreadIDs[submission.retainedContextRequestID] = detail.summary.id
		var boundWorkspace = managedWorkspace
		if context.threadID == nil, let current = managedWorkspace,
			let manager = taskWorkspaceManager
		{
			boundWorkspace = try await manager.bindThread(
				id: current.id,
				threadID: detail.summary.id
			)
		}

		return .execution(.submissionPrepared(
			context,
			.succeeded(PreparedSubmission(
				submission: submission,
				thread: detail,
				workspace: boundWorkspace
			))
		))
	}

	private func startPreparedSubmission(
		_ prepared: PreparedSubmission,
		context: OperationContext,
		managedWorkspace: TaskWorkspace?
	) async throws -> WorkspaceAction
	{
		let submission = prepared.submission
		let detail = prepared.thread
		guard let path = context.workspace.canonicalCheckoutPath
		else
		{
			throw AppServerError.protocolError("Submission requires a checkout.")
		}
		let directory = URL(fileURLWithPath: path)
		try await verifyWorkspace(managedWorkspace)
		try Task.checkCancellation()
		guard isSubmissionCurrent(context)
		else
		{
			throw CancellationError()
		}
		if isSubmissionStopped(context)
		{
			return .execution(.submissionCancelledBeforeSend(context))
		}

		let baselineResult = await gitTurnBaselineService.capture(GitTurnBaselineCaptureRequest(
			context: context,
			threadID: detail.summary.id,
			repositoryRoot: path
		))
		let baseline: GitTurnBaselineReference?
		if case .captured(let reference) = baselineResult
		{
			baseline = reference
		}
		else
		{
			baseline = nil
		}

		// Capture may suspend. Revalidate execution ownership before sending backend work.
		do
		{
			try await validateSubmissionAfterCapture(
				context,
				managedWorkspace: managedWorkspace
			)
		}
		catch
		{
			if let baseline
			{
				await gitTurnBaselineService.discard(baseline)
			}
			if error is SubmissionStoppedBeforeSend
			{
				return .execution(.submissionCancelledBeforeSend(context))
			}
			throw error
		}

		let turn = try await startTurnPreservingBaseline(
			submission,
			context: context,
			detail: detail,
			directory: directory,
			managedWorkspace: managedWorkspace,
			baseline: baseline
		)

		return .execution(.submissionAcknowledged(
			context,
			SubmissionAcknowledgement(
				thread: detail.summary,
				turn: turn,
				gitTurnBaseline: baseline,
				gitTurnBaselineResult: baselineResult
			)
		))
	}

	private func startTurnPreservingBaseline(
		_ submission: ComposerSubmission,
		context: OperationContext,
		detail: ThreadDetail,
		directory: URL,
		managedWorkspace: TaskWorkspace?,
		baseline: GitTurnBaselineReference?
	) async throws -> CodexTurn
	{
		do
		{
			return try await service.startTurn(
				threadId: detail.summary.id,
				inputs: submission.inputs,
				model: submission.modelID,
				effort: submission.effort,
				skills: submission.skills,
				cwd: managedWorkspace == nil ? nil : directory,
				preferences: submission.preferences,
				collaborationMode: submission.collaborationMode,
				serviceTier: submission.serviceTier
			)
		}
		catch
		{
			let definitelyRejected: Bool
			if let serverError = error as? AppServerError,
				case .requestRejected = serverError
			{
				definitelyRejected = true
			}
			else if let writeFailure = error as? ProtocolWriteFailure
			{
				definitelyRejected = !writeFailure.mayHaveBeenSent
			}
			else
			{
				definitelyRejected = false
			}
			if definitelyRejected, let baseline
			{
				await gitTurnBaselineService.discard(baseline)
			}
			let pending = !definitelyRejected ? baseline.map
			{
				PendingGitTurnBaselineCapture(
					context: context,
					reference: $0,
					previousTurnIDs: Set(detail.turns.map(\.id))
				)
			} : nil
			throw SubmissionStartFailure(
				failure: OperationFailure(
					message: error.localizedDescription,
					outcomeIsUncertain: !definitelyRejected
				),
				pendingCapture: pending
			)
		}
	}

	private func validateSubmissionAfterCapture(
		_ context: OperationContext,
		managedWorkspace: TaskWorkspace?
	) async throws
	{
		try Task.checkCancellation()
		guard isSubmissionCurrent(context)
		else
		{
			throw CancellationError()
		}
		if isSubmissionStopped(context)
		{
			throw SubmissionStoppedBeforeSend()
		}
		try await verifyWorkspace(managedWorkspace)
		try Task.checkCancellation()
		guard isSubmissionCurrent(context)
		else
		{
			throw CancellationError()
		}
		if isSubmissionStopped(context)
		{
			throw SubmissionStoppedBeforeSend()
		}
	}

	func conversationDirectory(_ context: OperationContext) throws -> URL
	{
		guard let path = context.workspace.canonicalCheckoutPath
		else
		{
			throw AppServerError.protocolError("Conversation operations require a checkout.")
		}
		return URL(fileURLWithPath: path)
	}

	func readConversation(
		_ context: OperationContext,
		allowsUnselectedCheckout: Bool = false,
		managedWorkspace: TaskWorkspace? = nil
	) async throws -> ThreadDetail
	{
		guard let threadID = context.threadID
		else
		{
			throw AppServerError.protocolError("A history read requires a thread.")
		}
		let project: URL?
		if allowsUnselectedCheckout, context.workspace.canonicalCheckoutPath == nil
		{
			project = nil
		}
		else
		{
			project = try conversationDirectory(context)
		}
		try await verifyWorkspace(managedWorkspace)
		let detail = try await service.readThread(id: threadID)
		guard detail.summary.id == threadID
		else
		{
			throw AppServerError.protocolError("History returned another conversation.")
		}
		try CheckoutIdentity.validate(
			cwd: detail.summary.cwd,
			expectedDirectory: project
		)
		try validateThread(
			detail.summary,
			workspace: managedWorkspace
		)
		return detail
	}

	private func verifyWorkspace(_ workspace: TaskWorkspace?) async throws
	{
		guard let workspace
		else
		{
			return
		}
		guard let manager = taskWorkspaceManager
		else
		{
			throw TaskWorkspaceError.ownershipConflict("task manager is unavailable")
		}
		let verified = try await manager.activeCheckout(id: workspace.id)
		guard verified.hasSameOwnership(as: workspace), verified.threadID == workspace.threadID
		else
		{
			throw TaskWorkspaceError.ownershipConflict("task binding changed on disk")
		}
	}

	private func validateThread(
		_ summary: ThreadSummary,
		workspace: TaskWorkspace?
	) throws
	{
		guard let workspace
		else
		{
			return
		}
		let path = URL(fileURLWithPath: summary.cwd).standardizedFileURL.resolvingSymlinksInPath()
			.path
		guard path == workspace.checkoutPath,
				workspace.threadID == nil || workspace.threadID == summary.id
		else
		{
			throw TaskWorkspaceError
				.ownershipConflict(
					"conversation \(summary.id) reports another checkout: \(summary.cwd)"
				)
		}
	}
}
