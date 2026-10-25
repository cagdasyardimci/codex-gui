import Foundation
import Testing

@testable import CodexGUI

struct TaskWorkspacePresentationCacheTests
{
	private func model() -> WorkspaceCoordinatorModel
	{
		WorkspaceCoordinatorModel(source: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/source"
		))
	}

	private func workspace(
		name: String = "Task|owner",
		path: String = "/tmp/source",
		createdAt: TimeInterval = 10
	) -> TaskWorkspace
	{
		let id = UUID()
		return TaskWorkspace(
			id: id,
			taskID: name,
			threadID: nil,
			sourceProjectPath: path,
			repositoryGitDirectory: path + "/.git",
			branch: "codex/task/\(id)",
			checkoutPath: "/tmp/task/\(id)",
			baseCommit: "base",
			sourceWasDirty: false,
			createdAt: Date(timeIntervalSince1970: createdAt),
			phase: .active
		)
	}

	private func observation(for workspace: TaskWorkspace) -> WorkspaceLifecycleObservation
	{
		let session = UUID()
		return WorkspaceLifecycleObservation(reference: WorkspaceLifecycleOwnerReference(
			owner: .managed(
				workspaceID: workspace.id,
				sessionID: session
			),
			workspace: WorkspaceIdentity(
				sessionID: session,
				canonicalCheckoutPath: workspace.checkoutPath
			)
		))
	}

	@Test func recordsRecoveryIssuesAndSourcePathInvalidateWithoutARevisionChange()
	{
		var model = model()
		let record = workspace()
		model.workspaces[record.id] = record
		var cache = TaskWorkspacePresentationCache()
		let unbound = cache.presentation(for: model)
		#expect(unbound.choices[0].canRemoveCheckout)

		model.workspaces[record.id]?.threadID = "bound"
		let bound = cache.presentation(for: model)
		#expect(bound !== unbound)
		#expect(!bound.choices[0].canRemoveCheckout)
		model.recoveryIssues[record.id] = .ownershipConflict
		let conflict = cache.presentation(for: model)
		#expect(conflict !== bound)
		#expect(conflict.choices[0].issue == "ownershipConflict")
		model.workspaces[record.id]?.phase = .checkoutRemoved
		let removed = cache.presentation(for: model)
		#expect(removed !== conflict)
		#expect(removed.choices[0].phase == .checkoutRemoved)
		#expect(!removed.choices[0].canRemoveCheckout)

		model.source = WorkspaceIdentity(
			sessionID: model.source.sessionID,
			canonicalCheckoutPath: "/tmp/another-source"
		)
		let otherSource = cache.presentation(for: model)
		#expect(otherSource !== removed)
		#expect(otherSource.choices.isEmpty)
		#expect(model.recordsRevision == 0)
	}

}
