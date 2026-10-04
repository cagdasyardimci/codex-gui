import Foundation

/// Synchronous effect routing and local startup/composer restoration.
extension WorkspaceEffectRunner
{
	func accept(
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
			switch effect
			{
			case .restoreSourceStartup(let context):
				guard managedWorkspace == nil, context.workspace == workspace,
						workspace.canonicalCheckoutPath == nil,
						let handle = beginSynchronous(
						effect,
						context: context
						)
				else
				{
					continue
				}
				let action: WorkspaceAction
				let completion: WorkspaceOperationCompletion
				do
				{
					action = try restoredSourceStartup(context)
					completion = .finished
				}
				catch
				{
					let failure = failure(
						for: effect,
						message: error.localizedDescription
					)
					action = failureAction(
						for: effect,
						context: context,
						failure: failure
					)
					completion = .failed(failure)
				}
				completeSynchronous(
					action,
					context: context,
					handle: handle,
					completion: completion
				)
			case .validateComposerInput(let operation):
				let context = operation.context
				guard context.workspace == workspace,
						let handle = beginSynchronous(
						effect,
						context: context
						)
				else
				{
					continue
				}
				let action: WorkspaceAction
				let completion: WorkspaceOperationCompletion
				do
				{
					action = try preparedComposerInput(operation)
					completion = .finished
				}
				catch
				{
					let failure = failure(
						for: effect,
						message: error.localizedDescription
					)
					action = failureAction(
						for: effect,
						context: context,
						failure: failure
					)
					completion = .failed(failure)
				}
				completeSynchronous(
					action,
					context: context,
					handle: handle,
					completion: completion
				)
			case .restoreComposer(let context):
				guard context.workspace == workspace,
						let handle = beginSynchronous(
						effect,
						context: context
						)
				else
				{
					continue
				}
				let action: WorkspaceAction
				let completion: WorkspaceOperationCompletion
				do
				{
					action = try restoredComposer(context)
					completion = .finished
				}
				catch
				{
					let failure = failure(
						for: effect,
						message: error.localizedDescription
					)
					action = failureAction(
						for: effect,
						context: context,
						failure: failure
					)
					completion = .failed(failure)
				}
				completeSynchronous(
					action,
					context: context,
					handle: handle,
					completion: completion
				)
			case .validateReusableReferences(let operation):
				guard operation.context.workspace == workspace,
						let handle = beginSynchronous(
						effect,
						context: operation.context
						)
				else
				{
					continue
				}
				let valid = operation.items.filter
				{
					$0
						.kind != .image ||
						($0.path.map
						{
							FileManager.default.fileExists(atPath: $0)
						} ?? false)
				}
				completeSynchronous(
					.workspaceLifecycle(.reusableReferencesReceived(
						operation,
						valid
					)),
					context: operation.context,
					handle: handle,
					completion: .finished
				)
			case .normalizeProjectPreference(
				let context,
				let url,
				let name
			):
				guard context.workspace == workspace
				else
				{
					continue
				}
				let path = url.standardizedFileURL.resolvingSymlinksInPath().path
				let action: PreferencesAction
				if let name
				{
					action = .projectRenamed(
						context,
						canonicalPath: path,
						name: name
					)
				}
				else
				{
					action = .projectPinToggled(
						context,
						canonicalPath: path
					)
				}
				deliver(
					.preferences(action),
					{
					}
				)
			case .prepareProjectOpening(
				let context,
				let url
			):
				guard context.workspace == workspace
				else
				{
					continue
				}
				let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
				let result: OperationResult<WorkspaceProjectOpening>
				if FileManager.default
					.fileExists(atPath: canonical.appendingPathComponent(".git").path)
				{
					result = .succeeded(WorkspaceProjectOpening(
						identity: WorkspaceIdentity(
							sessionID: context.workspace.sessionID,
							canonicalCheckoutPath: canonical.path
						),
						selectedThreadID: storage?.selectedThreadID(for: canonical)
					))
				}
				else
				{
					result = .failed(OperationFailure(
						message: "Choose a Git repository folder.",
						outcomeIsUncertain: false
					))
				}
				deliver(
					.workspaceLifecycle(.projectOpeningFinished(
						context,
						result
					)),
					{
					}
				)
			case .restoreArchivedSelection(
				let context,
				let archived
			):
				guard context.workspace == workspace,
						let path = context.workspace.canonicalCheckoutPath
				else
				{
					continue
				}
				let selected = archived ? nil : (managedWorkspace?.threadID
					?? storage?.selectedThreadID(for: URL(fileURLWithPath: path)))
				deliver(
					.workspaceLifecycle(.archivedSelectionRestored(
						context,
						archived: archived,
						threadID: selected
					)),
					{
					}
				)
			case .disconnect:
				service.disconnect()
			case .restoreExecution(
				let context,
				let selectedThreadID
			):
				guard context.workspace == workspace
				else
				{
					continue
				}
				let commands = context.workspace.canonicalCheckoutPath.map
				{
					storage?.pendingCommands(for: URL(fileURLWithPath: $0)) ?? []
				} ?? []
				let restoredSelection = selectedThreadID ?? (managedWorkspace == nil
					? context.workspace.canonicalCheckoutPath.flatMap
					{
						storage?.selectedThreadID(for: URL(fileURLWithPath: $0))
					} : nil)
				deliver(
					.connection(.projectRestored(
						context,
						pendingCommands: commands,
						selectedThreadID: restoredSelection
					)),
					{
					}
				)
			case .persistCommands(
				let context,
				let commands
			):
				if let path = context.workspace.canonicalCheckoutPath
				{
					storage?.savePendingCommands(
						Set(commands),
						for: URL(fileURLWithPath: path)
					)
				}
			case .taskFinished: break
			case .subscribe(let context):
				guard context.workspace == workspace
				else
				{
					continue
				}
				attachSubscription(context)
			case .detachSubscription:
				detachSubscription()
			case .scheduleUsageDeadline(let operation):
				guard operation.read.context.workspace.sessionID == workspace.sessionID,
						operation.read.context.generation == subscription?.generation
				else
				{
					continue
				}
				scheduleUsageDeadline(operation)
			case .cancelUsageDeadline(let operation):
				guard usageDeadline == operation
				else
				{
					continue
				}
				usageDeadlineTask?.cancel()
				usageDeadlineTask = nil
				usageDeadline = nil
			case .cancelUsageRefresh(let context):
				guard context.workspace.sessionID == workspace.sessionID
				else
				{
					continue
				}
				cancel(context)
			case .cancelMessageSearch(let operation):
				guard operation.context.workspace.sessionID == workspace.sessionID
				else
				{
					continue
				}
				cancel(
					operation.context,
					purpose: .messageSearch(
						operation.historyRevision,
						operation.query
					)
				)
			case .cancel(let context):
				guard context.workspace == workspace
				else
				{
					continue
				}
				cancel(context)

			default:
				guard let (context, purpose) = identity(of: effect)
				else
				{
					continue
				}
				let request = RequestKey(context)
				// Only an active version request may continue its original transport scope
				// after source checkout selection. Nil checkout paths never match generally.
				let continuesTransport = purpose == .connection
					&& subscription?.workspace.sessionID == context.workspace.sessionID
					&& subscription?.generation == context.generation
					&& handles[request]?.completion == nil
					&& accepted.contains(EffectKey(
						request: request,
						purpose: .version
					))
				let accountSessionEffect: Bool
				let isAccountSessionRequest =
					purpose == .account || purpose == .models || purpose == .signIn
				if isAccountSessionRequest
				{
					accountSessionEffect = context.workspace.sessionID == workspace.sessionID
						&& context.generation == subscription?.generation
				}
				else if case .usage = purpose
				{
					accountSessionEffect = context.workspace.sessionID == workspace.sessionID
						&& context.generation == subscription?.generation
				}
				else
				{
					accountSessionEffect = false
				}
				let canAcceptEffect =
					context.workspace == workspace || continuesTransport || accountSessionEffect
				guard canAcceptEffect
				else
				{
					continue
				}

				start(
					effect,
					context: context,
					purpose: purpose,
					managedWorkspace: managedWorkspace
				)
			}
		}
	}

	func preparedComposerInput(
		_ operation: ComposerInputPreparationOperation
	) throws -> WorkspaceAction
	{
		let project = try conversationDirectory(operation.context)
		let submission = operation.submission
		let text = submission.inputs.compactMap
		{
			if case .text(let text) = $0
			{
				return text
			}
			return nil
		}.joined(separator: "\n")
		let inputs = try ComposerContextBuilder.inputs(
			text: text,
			items: submission.draft.context,
			project: project
		)
		return .workspaceLifecycle(.inputPreparationFinished(
			operation,
			.succeeded(inputs)
		))
	}

	func restoredSourceStartup(_ context: OperationContext) throws -> WorkspaceAction
	{
		guard let storage
		else
		{
			throw AppServerError.protocolError("Source startup requires storage.")
		}
		let preferences = storage.preferenceRestoration
		var project: WorkspaceProjectOpening?
		var commands: [TaskCommandOwnership] = []
		for candidate in preferences.recentProjects
		{
			let canonical = candidate.standardizedFileURL.resolvingSymlinksInPath()
			var isDirectory: ObjCBool = false
			guard FileManager.default.fileExists(
				atPath: canonical.path,
				isDirectory: &isDirectory
			),
				isDirectory.boolValue,
				FileManager.default
				.fileExists(atPath: canonical.appendingPathComponent(".git").path)
			else
			{
				continue
			}
			project = WorkspaceProjectOpening(
				identity: WorkspaceIdentity(
					sessionID: context.workspace.sessionID,
					canonicalCheckoutPath: canonical.path
				),
				selectedThreadID: storage.selectedThreadID(for: canonical)
			)
			commands = storage.pendingCommands(for: canonical)
			break
		}
		return .workspaceLifecycle(.sourceStartupRestored(
			context,
			.succeeded(WorkspaceSourceStartup(
				project: project,
				pendingCommands: commands,
				preferences: preferences
			))
		))
	}

	func restoredComposer(_ context: OperationContext) throws -> WorkspaceAction
	{
		let project = try conversationDirectory(context)
		guard let storage
		else
		{
			throw AppServerError.protocolError("Composer hydration requires storage.")
		}
		return .composer(.conversationRestored(
			context,
			conversation: context.threadID
				.map(ConversationKey.thread) ?? .newChat,
			draft: ComposerDraft(
				text: storage.draft(
					for: project,
					threadID: context.threadID
				),
				context: storage.draftContext(
					for: project,
					threadID: context.threadID
				)
			),
			references: context.threadID
				.map
				{
					storage.sentReferences(
						for: project,
						threadID: $0
					)
				} ?? []
		))
	}
}
