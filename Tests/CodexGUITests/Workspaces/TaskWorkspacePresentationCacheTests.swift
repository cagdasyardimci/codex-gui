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

	@Test func unchangedPresentationInputsReuseChoicesAndKeepCreationOrder()
	{
		var model = model()
		let earlier = workspace(
			name: "Earlier|owner",
			createdAt: 1
		)
		let later = workspace(
			name: "Later|owner",
			createdAt: 2
		)
		model.workspaces = [later.id: later, earlier.id: earlier]
		var cache = TaskWorkspacePresentationCache()
		let original = cache.presentation(for: model)
		#expect(original.choices.map(\.id) == [earlier.id, later.id])
		#expect(original.choices.map(\.title) == ["Earlier", "Later"])
		#expect(original.statusSummary == nil)

		model.selectionEpoch += 1
		model.recordsRevision += 1
		model.message = "An unrelated publication"
		#expect(cache.presentation(for: model) === original)
		#expect(cache.presentation(for: model) === original)
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

	@Test func ownerTransitionsAndReservationsUpdateCleanupAndAggregateStatus()
	{
		var model = model()
		var record = workspace()
		record.threadID = "bound"
		model.workspaces[record.id] = record
		var owner = observation(for: record)
		owner.executionState = .ready
		model.owners[owner.reference.owner] = owner
		var cache = TaskWorkspacePresentationCache()
		let idle = cache.presentation(for: model)
		#expect(idle.choices[0].canRemoveCheckout)

		owner.executionState = .running
		model.owners[owner.reference.owner] = owner
		let running = cache.presentation(for: model)
		#expect(running !== idle)
		#expect(!running.choices[0].canRemoveCheckout)
		#expect(running.statusSummary == "1 running task")
		owner.executionState = .awaitingAnswer
		model.owners[owner.reference.owner] = owner
		let waiting = cache.presentation(for: model)
		#expect(waiting.statusSummary == "1 running task · 1 need a response")

		owner.executionState = .ready
		owner.cleanupReservation = UUID()
		model.owners[owner.reference.owner] = owner
		let reserved = cache.presentation(for: model)
		#expect(!reserved.choices[0].canRemoveCheckout)
		#expect(reserved.statusSummary == nil)
		owner.cleanupReservation = nil
		owner.composerOutcomeUncertain = true
		model.owners[owner.reference.owner] = owner
		#expect(!cache.presentation(for: model).choices[0].canRemoveCheckout)
		owner.composerOutcomeUncertain = false
		owner.unresolvedCommands = true
		model.owners[owner.reference.owner] = owner
		#expect(!cache.presentation(for: model).choices[0].canRemoveCheckout)
		#expect(cache.presentation(for: model).statusSummary == "1 running task")

		model.owners.removeValue(forKey: owner.reference.owner)
		let retired = cache.presentation(for: model)
		#expect(retired.choices[0].executionState == nil)
		#expect(!retired.choices[0].canRemoveCheckout)
		#expect(retired.statusSummary == nil)
		#expect(model.recordsRevision == 0)
	}

	@Test func anyRunningOwnerKeepsForeignWorkspaceVisibleAndFirstOwnerSuppliesItsChoice() throws
	{
		var model = model()
		let record = workspace(path: "/tmp/foreign-source")
		model.workspaces[record.id] = record
		let alpha = observation(for: record)
		let beta = observation(for: record)
		model.owners = [alpha.reference.owner: alpha, beta.reference.owner: beta]
		let firstOwner = try #require(model.owners.first?.key)
		let laterOwner = firstOwner == alpha.reference.owner
			? beta.reference.owner : alpha.reference.owner
		model.owners[firstOwner]?.executionState = .ready
		model.owners[laterOwner]?.executionState = .running
		var cache = TaskWorkspacePresentationCache()
		let visible = cache.presentation(for: model)
		#expect(visible.choices.map(\.id) == [record.id])
		#expect(visible.choices[0].executionState == .ready)
		#expect(visible.choices[0].canRemoveCheckout)
		#expect(visible.statusSummary == "1 running task")

		model.owners.removeValue(forKey: firstOwner)
		let survivor = cache.presentation(for: model)
		#expect(survivor !== visible)
		#expect(survivor.choices[0].executionState == .running)
		#expect(!survivor.choices[0].canRemoveCheckout)
		model.owners.removeValue(forKey: laterOwner)
		#expect(cache.presentation(for: model).choices.isEmpty)
		#expect(cache.presentation(for: model).statusSummary == nil)
	}

	@Test func equalCreationDatesRetainExistingWorkspaceEnumerationOrder()
	{
		var model = model()
		let records = (0 ..< 8).map
		{
			workspace(name: "Task \($0)")
		}
		for record in records
		{
			model.workspaces[record.id] = record
		}
		var cache = TaskWorkspacePresentationCache()
		#expect(cache.presentation(for: model).choices.map(\.id)
			== Array(model.workspaces.values).map(\.id))
	}

	@Test func canonicallyEquivalentRecordUpdatesRefreshExactDisplayedAndCopyableText()
	{
		var model = model()
		let original = workspace(name: "Café|owner")
		model.workspaces[original.id] = original
		var cache = TaskWorkspacePresentationCache()
		let first = cache.presentation(for: model)
		let updated = TaskWorkspace(
			id: original.id,
			taskID: "Cafe\u{301}|owner",
			threadID: original.threadID,
			sourceProjectPath: original.sourceProjectPath,
			repositoryGitDirectory: original.repositoryGitDirectory,
			branch: "codex/cafe\u{301}",
			checkoutPath: "/tmp/cafe\u{301}",
			baseCommit: original.baseCommit,
			sourceWasDirty: original.sourceWasDirty,
			createdAt: original.createdAt,
			phase: original.phase
		)
		let composed = TaskWorkspace(
			id: original.id,
			taskID: original.taskID,
			threadID: original.threadID,
			sourceProjectPath: original.sourceProjectPath,
			repositoryGitDirectory: original.repositoryGitDirectory,
			branch: "codex/café",
			checkoutPath: "/tmp/café",
			baseCommit: original.baseCommit,
			sourceWasDirty: original.sourceWasDirty,
			createdAt: original.createdAt,
			phase: original.phase
		)
		model.workspaces[original.id] = composed
		let composedPresentation = cache.presentation(for: model)
		#expect(composed == updated)
		model.workspaces[original.id] = updated
		let decomposedPresentation = cache.presentation(for: model)
		#expect(decomposedPresentation !== composedPresentation)
		#expect(Array(decomposedPresentation.choices[0].title.utf8)
			== Array("Cafe\u{301}".utf8))
		#expect(Array(decomposedPresentation.choices[0].branch.utf8)
			== Array(updated.branch.utf8))
		#expect(Array(decomposedPresentation.choices[0].checkoutPath.utf8)
			== Array(updated.checkoutPath.utf8))
		#expect(Array(first.choices[0].title.utf8) == Array("Café".utf8))
		#expect(model.recordsRevision == 0)
	}
}
