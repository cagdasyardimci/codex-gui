import Foundation

/// Reuses derived choices until their coordinator inputs change.
struct TaskWorkspacePresentationCache
{
	private struct WorkspaceInput: Equatable
	{
		let workspace: TaskWorkspace

		static func == (lhs: Self, rhs: Self) -> Bool
		{
			let left = lhs.workspace
			let right = rhs.workspace
			// Canonical Unicode equality must not retain stale displayed or copied text.
			return left == right
				&& TaskWorkspacePresentationCache.sameUTF8(
					left.taskID,
					right.taskID
				)
				&& TaskWorkspacePresentationCache.sameUTF8(
					left.threadID,
					right.threadID
				)
				&& TaskWorkspacePresentationCache.sameUTF8(
					left.sourceProjectPath,
					right.sourceProjectPath
				)
				&& TaskWorkspacePresentationCache.sameUTF8(
					left.repositoryGitDirectory,
					right.repositoryGitDirectory
				)
				&& TaskWorkspacePresentationCache.sameUTF8(
					left.branch,
					right.branch
				)
				&& TaskWorkspacePresentationCache.sameUTF8(
					left.checkoutPath,
					right.checkoutPath
				)
				&& TaskWorkspacePresentationCache.sameUTF8(
					left.baseCommit,
					right.baseCommit
				)
		}
	}

	private struct OwnerInput: Equatable
	{
		let owner: WorkspaceLifecycleOwner
		let observation: WorkspaceLifecycleObservation

		static func == (lhs: Self, rhs: Self) -> Bool
		{
			lhs.owner == rhs.owner && lhs.observation == rhs.observation
				&& TaskWorkspacePresentationCache.sameUTF8(
					lhs.observation.activeThreadID,
					rhs.observation.activeThreadID
				)
				&& TaskWorkspacePresentationCache.sameUTF8(
					lhs.observation.reference.workspace.canonicalCheckoutPath,
					rhs.observation.reference.workspace.canonicalCheckoutPath
				)
		}
	}

	private struct Inputs: Equatable
	{
		let sourceProjectPath: String?
		let workspaces: [WorkspaceInput]
		let recoveryIssues: [UUID: TaskWorkspaceRecoveryKind]
		let owners: [OwnerInput]

		init(model: WorkspaceCoordinatorModel)
		{
			sourceProjectPath = model.source.canonicalCheckoutPath
			// Preserve dictionary enumeration for equal creation dates and first matching owners.
			workspaces = model.workspaces.values.map
			{
				WorkspaceInput(workspace: $0)
			}
			recoveryIssues = model.recoveryIssues
			owners = model.owners.map
			{
				OwnerInput(
					owner: $0.key,
					observation: $0.value
				)
			}
		}

		static func == (lhs: Self, rhs: Self) -> Bool
		{
			TaskWorkspacePresentationCache.sameUTF8(
				lhs.sourceProjectPath,
				rhs.sourceProjectPath
			)
				&& lhs.workspaces == rhs.workspaces
				&& lhs.recoveryIssues == rhs.recoveryIssues
				&& lhs.owners == rhs.owners
		}
	}

	private struct OwnerSummary
	{
		var firstObservationByWorkspace: [UUID: WorkspaceLifecycleObservation] = [:]
		var runningWorkspaceIDs: Set<UUID> = []
		var runningOwnerCount = 0
		var responseWaitingOwnerCount = 0
	}

	private var cachedInputs: Inputs?
	private var cachedPresentation: TaskWorkspacePresentation?

	private static func sameUTF8(
		_ lhs: String,
		_ rhs: String
	) -> Bool
	{
		lhs.utf8.elementsEqual(rhs.utf8)
	}

	private static func sameUTF8(
		_ lhs: String?,
		_ rhs: String?
	) -> Bool
	{
		switch (lhs, rhs)
		{
		case (nil, nil): true
		case (.some(let left), .some(let right)): sameUTF8(
				left,
				right
			)
		default: false
		}
	}

	mutating func presentation(for model: WorkspaceCoordinatorModel) -> TaskWorkspacePresentation
	{
		let updatedInputs = Inputs(model: model)
		if cachedInputs == updatedInputs, let cachedPresentation
		{
			return cachedPresentation
		}

		let prepared = Self.preparePresentation(updatedInputs)
		cachedInputs = updatedInputs
		cachedPresentation = prepared
		return prepared
	}

	private static func preparePresentation(_ inputs: Inputs) -> TaskWorkspacePresentation
	{
		let owners = summarizeOwners(inputs.owners)
		let choices = prepareChoices(
			inputs,
			owners: owners
		)

		return TaskWorkspacePresentation(
			choices: choices,
			statusSummary: statusSummary(for: owners)
		)
	}

	private static func summarizeOwners(_ owners: [OwnerInput]) -> OwnerSummary
	{
		var summary = OwnerSummary()
		for input in owners
		{
			let observation = input.observation
			if observation.requiresRemoteStop
			{
				summary.runningOwnerCount += 1
			}
			let needsResponse = observation.executionState == .awaitingApproval
				|| observation.executionState == .awaitingAnswer
			if needsResponse
			{
				summary.responseWaitingOwnerCount += 1
			}

			guard case .managed(
				let workspaceID,
				_
			) = input.owner
			else
			{
				continue
			}
			if summary.firstObservationByWorkspace[workspaceID] == nil
			{
				summary.firstObservationByWorkspace[workspaceID] = observation
			}
			if observation.requiresRemoteStop
			{
				summary.runningWorkspaceIDs.insert(workspaceID)
			}
		}
		return summary
	}

	private static func prepareChoices(
		_ inputs: Inputs,
		owners: OwnerSummary
	) -> [TaskWorkspaceChoice]
	{
		let workspaceRecords = inputs.workspaces.map(\.workspace)
		let visibleWorkspaces = workspaceRecords.filter
		{
			$0.sourceProjectPath == inputs.sourceProjectPath
				|| owners.runningWorkspaceIDs.contains($0.id)
		}
		let orderedWorkspaces = visibleWorkspaces.sorted
		{
			$0.createdAt < $1.createdAt
		}

		return orderedWorkspaces.map
		{
			workspace in
			makeChoice(
				for: workspace,
				observation: owners.firstObservationByWorkspace[workspace.id],
				issue: inputs.recoveryIssues[workspace.id]?.rawValue
			)
		}
	}

	private static func makeChoice(
		for workspace: TaskWorkspace,
		observation: WorkspaceLifecycleObservation?,
		issue: String?
	) -> TaskWorkspaceChoice
	{
		let canRemoveCheckout =
			(workspace.phase == .active || workspace.phase == .removing)
				&& (workspace.threadID == nil || observation != nil)
				&& observation?.blocksCleanup != true
				&& observation?.cleanupReservation == nil

		return TaskWorkspaceChoice(
			id: workspace.id,
			title: workspace.taskID.components(separatedBy: "|").first ?? workspace.taskID,
			checkoutPath: workspace.checkoutPath,
			branch: workspace.branch,
			sourceWasDirty: workspace.sourceWasDirty,
			phase: workspace.phase,
			executionState: observation?.executionState,
			issue: issue,
			canRemoveCheckout: canRemoveCheckout
		)
	}

	private static func statusSummary(for owners: OwnerSummary) -> String?
	{
		let runningCount = owners.runningOwnerCount
		guard runningCount != 0
		else
		{
			return nil
		}
		let waitingCount = owners.responseWaitingOwnerCount
		return "\(runningCount) running task\(runningCount == 1 ? "" : "s")"
			+ (waitingCount == 0 ? "" : " · \(waitingCount) need a response")
	}
}
