import Foundation

/// Read-only projections contain no runtime or persistence operations.
@MainActor
struct WorkspaceSelectors
{
	let model: WorkspaceModel
	let now: Date
	var project: URL?
	{
		model.identity.canonicalCheckoutPath.map
		{
			URL(fileURLWithPath: $0)
		}
	}
	var taskWorkspace: TaskWorkspace?
	{
		model.lifecycle.managedWorkspace
	}
	var workspaceCleanupInProgress: Bool
	{
		let hasCleanupReservation = model.lifecycle.cleanupReservation != nil
		let hasQuitReservation = model.lifecycle.quitReservation != nil
		let hasInactiveWorkspace = model.lifecycle.managedWorkspace.map
		{
			$0.phase != .active
		} ?? false

		return hasCleanupReservation || hasQuitReservation || hasInactiveWorkspace
	}
	var isTaskActive: Bool
	{
		model.execution.isTaskActive || !model.composer.uncertainSubmissions.isEmpty
			|| model.lifecycle.pendingInputPreparation != nil
			|| model.lifecycle.managedOwnershipConflict != nil
	}
	var statusMessage: String?
	{
		model.composerCommands.error
			?? model.lifecycle.statusMessage
			?? model.lifecycle.managedOwnershipConflict
			?? model.conversations.error
			?? selectedThreadID.flatMap
			{
				model.conversations.turnReferenceIndices[$0]?.error
			}
			?? model.preferences.statusMessage
			?? model.preferences.persistenceError
			?? model.execution.statusMessage
			?? model.connection.statusMessage
			?? model.composer.persistenceError
	}
	var threads: [ThreadSummary]
	{
		model.conversations.threads
	}
	var selectedThreadID: String?
	{
		if case .thread(let id) = model.conversations.selectedConversation
		{
			return id
		}

		return nil
	}
	var activeThreadID: String?
	{
		model.execution.activeThreadID
	}
	var projectContext: ProjectContext
	{
		model.contextNavigation.projectContext
	}
	var pendingJumpThreadID: String?
	{
		model.contextNavigation.pendingJump?.context.threadID
	}
	var pendingJumpItemID: String?
	{
		model.contextNavigation.pendingJump?.resolvedItemID
	}
	var jumpLoading: Bool
	{
		model.contextNavigation.pendingJump?.pendingRead != nil
	}
	var jumpError: String?
	{
		model.contextNavigation.jumpError
	}
	var searchLoading: Bool
	{
		model.contextNavigation.pendingSearch != nil
			|| model.contextNavigation.pendingMessageSearch != nil
	}
	var searchError: String?
	{
		model.contextNavigation.searchError
	}
	var composerDraft: ComposerDraft
	{
		model.composer
			.drafts[model.conversations.selectedConversation]
			?? ComposerDraft()
	}
	var draft: String
	{
		composerDraft.text
	}
	var draftContext: [ComposerContextItem]
	{
		composerDraft.context
	}
	var accountDescription: String
	{
		model.preferences.accountDescription
	}
	var backendDescription: String
	{
		model.connection.backendDescription
	}
	var executionState: ExecutionState
	{
		model.execution.state
	}
	var models: [ModelOption]
	{
		model.preferences.models
	}
	var modelListError: String?
	{
		model.preferences.modelListError
	}
	var skillCatalog: SkillCatalog?
	{
		model.contextNavigation.skillCatalog
	}
	var skillError: String?
	{
		model.contextNavigation.skillError
	}
	var selectedModelID: String?
	{
		model.preferences.selectedModelID
	}
	var selectedEffort: String?
	{
		model.preferences.selectedEffort
	}
	var runPreferences: RunPreferences
	{
		model.preferences.runPreferences
	}
	var hasStoredModelPreference: Bool
	{
		model.preferences.hasStoredModelPreference
	}
	var showingArchived: Bool
	{
		model.conversations.showingArchived
	}
	var managementRequestActive: Bool
	{
		model.conversations.pendingManagement != nil
	}
	var loadingThreadID: String?
	{
		model.conversations.pendingSelection?.threadID
	}
	var historyPageRequests: [String: HistoryLoadOperation]
	{
		model.conversations.historyLoads
	}
	var pendingInteractions: [PendingInteraction]
	{
		model.execution.pendingInteractions
	}
	var activeTurnID: String?
	{
		model.execution.activeTurnID
	}
	var activePlan: TurnPlanUpdate?
	{
		model.execution.activePlan
	}
	var activeActivity: String?
	{
		model.execution.activeActivity
	}
	var activeTaskOutcomeMessage: String?
	{
		model.execution.outcomeMessage
	}
	var steerRequestActive: Bool
	{
		model.execution.pendingSteering != nil
	}
	var connectionGeneration: Int
	{
		model.connection.generation
	}
	var needsReconciliation: Bool
	{
		model.execution.needsReconciliation
	}
	var hasUncertainRequest: Bool
	{
		model.execution.hasUncertainRequest || model.lifecycle.managedOwnershipConflict != nil
	}
	var isConnected: Bool
	{
		model.connection.isConnected
	}
	var commandLifetime: TaskCommandLifetime
	{
		model.execution.commandLifetime
	}
	var commandEventRevisions: [String: Int]
	{
		model.execution.commandEventRevisions
	}

	var canManageSelectedThread: Bool
	{
		WorkspaceEligibility(model: model).canManageThreads
	}
	var viewedContent: ConversationProjection
	{
		content(for: selectedThreadID)
	}

	func content(for threadID: String?) -> ConversationProjection
	{
		ConversationContentReducer.projection(
			model,
			key: threadID.map(ConversationKey.thread) ?? .newChat
		)
	}

	var selectedReview: ReviewTurn?
	{
		viewedContent.reviewTurns.first
		{
			$0.turnID == viewedContent.selectedReviewTurnID
		}
	}

	var reviewedReferences: Set<ReviewReference>
	{
		ReviewReducer.reviewedReferences(
			model,
			model.conversations.selectedConversation
		)
	}

	var reusableReferences: [ComposerContextItem]
	{
		reusableReferenceCandidates.filter
		{
			candidate in
			guard candidate.kind == .image
			else
			{
				return true
			}
			return candidate.path.map
			{
				model.lifecycle.validatedImagePaths.contains($0)
			} ?? false
		}
	}
	var reusableReferenceCandidates: [ComposerContextItem]
	{
		guard let project, let selectedThreadID
		else
		{
			return []
		}
		var references = model.composer
			.sentReferences[.thread(selectedThreadID)] ?? []
		let projectPath = project.path
		let knownPaths = Set(references.compactMap
		{
			$0.path
		})
		let content = viewedContent.content
		let historyReferences = content.loadedUserReferences
			?? ConversationHistoryReferences.collect(from: content.loadedTurns)
		for reference in historyReferences where !knownPaths.contains(reference.path)
		{
			switch reference.kind
			{
			case .audio:
				continue
			case .fileReference:
				guard reference.path.hasPrefix(projectPath + "/")
				else
				{
					continue
				}
				references.append(
					ComposerContextItem(
						id: reference.id,
						kind: .fileReference,
						title: reference.name,
						path: String(reference.path.dropFirst(projectPath.count + 1))
					)
				)
			case .image:
				references.append(
					ComposerContextItem(
						id: reference.id,
						kind: .image,
						title: reference.name,
						path: reference.path
					)
				)
			}
		}
		return references
	}

	var preferenceWarning: String?
	{
		WorkspaceEligibility(model: model).preferenceWarning
	}
	func visibleStatusMessage(viewingActiveThread: Bool) -> String?
	{
		if let commandError = model.composerCommands.error
		{
			return commandError
		}
		guard viewingActiveThread
		else
		{
			return executionState.isBusy ? nil : statusMessage
		}
		if needsReconciliation
		{
			return statusMessage
		}
		return activeTaskOutcomeMessage ?? statusMessage
	}

	/// History is ordered oldest to newest. An in-flight turn can precede history publication,
	/// but a completed or older active identity must never replace newer loaded source history.
	var lastGitTurnID: String?
	{
		let content = viewedContent.content
		let turns = content.loadedTurns
		let latest = content.latestObservedGitTurnID ?? turns.last?.id
		guard selectedThreadID != nil, selectedThreadID == activeThreadID,
				executionState.isBusy, let activeTurnID
		else
		{
			return latest
		}
		if let observed = content.latestObservedGitTurnID, observed != activeTurnID,
			ConversationTurnStatus.isRunning(content.turnTimings[observed]?.status)
		{
			return observed
		}
		if let activeIndex = turns.firstIndex(where:
			{
				$0.id == activeTurnID
			}),
			activeIndex < turns.count - 1
		{
			return latest
		}
		return activeTurnID
	}

	var gitTurnBaselineFailure: GitComparisonFailure?
	{
		let reportedTurnID = viewedContent.content.latestReportedGitTurn?.id ?? lastGitTurnID
		guard let threadID = selectedThreadID,
				let binding = model.execution.gitTurnBaselineBindings[threadID],
				binding.context.workspace == model.identity,
				binding.turnID == reportedTurnID,
				let result = binding.result,
				case .unavailable(let failure) = result
		else
		{
			return nil
		}
		return failure
	}

	func makeSnapshot() -> ConversationSnapshot
	{
		let viewingActiveThread = selectedThreadID != nil && selectedThreadID == activeThreadID
		let visibleExecutionState: ExecutionState =
			viewingActiveThread || activeThreadID == nil
				? executionState : (isConnected ? .ready : .disconnected)
		let canLoadEarlierTurns = viewedContent.nextTurnsCursor != nil
			&& selectedThreadID.flatMap
			{
				historyPageRequests[$0]
			} == nil
		let pendingJumpIsVisible = selectedThreadID == pendingJumpThreadID
			&& viewedContent.entries.contains(where:
				{
					$0.id == pendingJumpItemID
				})
		let reportedTurn = ConversationReportedGitTurnProjection(content: viewedContent.content)

		var snapshot = ConversationSnapshot(
			turnTimings: ConversationContentReducer.timings(for: viewedContent.content),
			projectPath: project?.path,
			threads: threads,
			selectedThreadID: selectedThreadID,
			entries: viewedContent.entries,
			canLoadEarlierTurns: canLoadEarlierTurns,
			changedFiles: viewedContent.changedFiles,
			diff: viewedContent.diff,
			draft: draft,
			draftContext: draftContext,
			reusableReferences: reusableReferences,
			canSend: WorkspaceEligibility(model: model).canSend || composerCommandAvailable,
			accountDescription: accountDescription,
			backendDescription: backendDescription,
			executionState: visibleExecutionState,
			statusMessage: visibleStatusMessage(viewingActiveThread: viewingActiveThread),
			models: models,
			selectedModelID: selectedModelID,
			selectedEffort: selectedEffort,
			pendingInteractions: viewingActiveThread ? pendingInteractions : [],
			recentProjects: model.preferences.recentProjects,
			approvalMode: runPreferences.approvalMode,
			fastMode: runPreferences.fastMode,
			pinnedProjectPaths: model.preferences.pinnedProjectPaths,
			projectDisplayNames: model.preferences.projectDisplayNames,
			preferenceWarning: preferenceWarning,
			showingArchived: showingArchived,
			canManageThreads: WorkspaceEligibility(model: model).canManageThreads,
			activeThreadID: activeThreadID,
			activeTurnID: activeTurnID,
			lastGitTurnID: lastGitTurnID,
			reportedGitTurnID: reportedTurn.turnID,
			reportedGitChanges: reportedTurn.changes,
			gitTurnBaselineRevision: selectedThreadID
				.map
				{
					model.execution.gitTurnBaselineRevisions[
						$0,
						default: 0
					]
				} ?? 0,
			gitTurnBaselineFailure: gitTurnBaselineFailure,
			activeExecutionState: activeThreadID == nil && !executionState.isBusy
				? nil : executionState,
			taskOutcomeUncertain: needsReconciliation || hasUncertainRequest,
			canSteer: WorkspaceEligibility(model: model).canSteer || composerCommandAvailable,
			activePlan: activePlan,
			activeActivity: activeActivity,
			skillCatalog: skillCatalog,
			skillError: skillError,
			usage: model.usage.snapshot,
			usageFetchedAt: model.usage.fetchedAt,
			usageIsStale: model.usage.isStale(
				isConnected: isConnected,
				now: now
			),
			usageError: model.usage.error,
			reviewTurns: viewedContent.reviewTurns,
			selectedReviewTurnID: viewedContent.selectedReviewTurnID,
			selectedReview: selectedReview,
			reviewedReferences: reviewedReferences,
			projectContext: projectContext,
			projectContextError: model.contextNavigation.contextError,
			messageSearch: model.contextNavigation.messageSearch,
			navigationTargets: model.contextNavigation.navigationTargets,
			pendingJumpItemID: pendingJumpIsVisible ? pendingJumpItemID : nil,
			jumpLoading: jumpLoading,
			jumpError: jumpError,
			searchLoading: searchLoading,
			searchError: searchError
		)
		if selectedThreadID == activeThreadID,
			viewedContent.content.liveChangeTurnID == activeTurnID,
			viewedContent.content.hasAggregateDiff
		{
			snapshot.activeTurnDiff = viewedContent.diff
		}
		if let threadID = selectedThreadID
		{
			let index = model.conversations.turnReferenceIndices[threadID]
			snapshot.turnReferences = index?.references ?? []
			snapshot.turnPreviews = index?.references.compactMap
			{
				index?.previews[$0.id]
			} ?? []
			snapshot.turnPreviewErrors = index?.previewErrors ?? [:]
			snapshot.canLoadEarlierTurnReferences = isConnected && index?.pendingRead == nil
				&& (index?.hasLoadedPage != true || index?.nextCursor != nil)
		}
		snapshot.slashCommandUnavailableReasons = Dictionary(uniqueKeysWithValues:
			SlashCommandRegistry.commands.compactMap
			{
				descriptor in
				ComposerCommandReducer.unavailableReason(
					descriptor.id,
					model: model
				)
				.map
				{
					(descriptor.id, $0)
				}
			})
		if let id = model.conversations.selectedConversation.threadID
		{
			snapshot.threadTokenUsage = model.composerCommands.tokenUsage[id]
			snapshot.threadStatus = model.composerCommands.threadStatuses[id]
			snapshot.threadSettings = model.composerCommands.threadSettings[id]
		}
		snapshot.planMode = model.composerCommands.planModes[
			model.conversations.selectedConversation
		] == .plan
		if let pending = model.composerCommands.pendingSettings
		{
			snapshot.planModeStatus = pending.outcomeUncertain
				? "Plan mode unknown — run /plan to reapply or reset." : "Plan mode pending…"
		}
		snapshot.workspaceOwner = WorkspaceLifecycleReducer.reference(model)
		snapshot.composerDraftLifetime = composerDraft.lifetime
		return snapshot
	}
	var backendDiagnosticsReport: String
	{
		let diagnostics = model.lifecycle.backendDiagnostics ?? BackendDiagnosticsSnapshot(
			cliVersion: nil,
			exitCode: nil,
			stderrTail: ""
		)
		let version = diagnostics.cliVersion ?? "Unknown"
		let compatibility =
			version == "codex-cli 0.153.2"
				? "Tested baseline" : "Compatibility unverified"
		let exit = diagnostics.exitCode.map(String.init) ?? "Unavailable"
		let stderr = diagnostics.stderrTail.isEmpty ? "No stderr captured." : diagnostics.stderrTail
		return """
		Codex CLI: \(version) — \(compatibility)
		Process exit code: \(exit)

		Recent app-server stderr (up to 8 KiB):
		\(stderr)
		"""
	}

	static func snapshot(
		model: WorkspaceModel,
		now: Date
	) -> ConversationSnapshot
	{
		WorkspaceSelectors(
			model: model,
			now: now
		).makeSnapshot()
	}
}
