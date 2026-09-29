import Foundation

/// Dispatches lifecycle transitions without changing synchronous feature composition order.
@MainActor
enum WorkspaceLifecycleReducer
{
	static let reducer = WorkspaceReducer(reduce: reduce)

	static func reduce(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		guard case .workspaceLifecycle(let lifecycle) = action
		else
		{
			return WorkspaceLifecycleComposition.reduceFeatureCompletion(
				&model,
				action
			)
		}
		switch lifecycle
		{
		case .managedRecordRecoveryConflicted, .managedRecordRecovered,
				.cleanupReserved, .cleanupReleased, .quitFrozen, .quitThawed:
			return reduceReservations(
				&model,
				lifecycle
			)
		case .inputPreparationRequested, .inputPreparationFinished, .unsentSubmissionReleased:
			return reduceInputPreparation(
				&model,
				lifecycle
			)
		case .sourceStartupRequested, .sourceStartupRestored, .projectPinRequested,
				.projectRenameRequested, .projectOpeningRequested, .projectOpeningFinished,
				.archivedSelectionRequested, .archivedSelectionRestored, .initialHydrationRequested,
				.bootstrapRequested, .refreshRequested, .composerHydrationRequested,
				.capabilityRejected, .diagnosticsReceived, .reusableReferencesReceived,
				.shutdownRequested:
			return reduceStartup(
				&model,
				lifecycle
			)
		}
	}

	static func valid(
		_ context: OperationContext,
		_ model: WorkspaceModel
	) -> Bool
	{
		context.belongsTo(
			workspace: model.identity,
			generation: model.connection.generation
		)
	}

}
