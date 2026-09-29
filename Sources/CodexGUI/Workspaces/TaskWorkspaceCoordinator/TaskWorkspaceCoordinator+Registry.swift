import Foundation

extension TaskWorkspaceCoordinator
{
	func register(
		_ store: WorkspaceStateStore,
		owner: WorkspaceLifecycleOwner
	)
	{
		guard !retired, stores[owner] == nil
		else
		{
			return
		}
		stores[owner] = store
		let token = observeLifecycleChanges(
			of: store,
			owner: owner
		)
		tokens[owner] = token
		publicationTokens[owner] = observePublications(
			of: store,
			owner: owner
		)
	}

	private func observeLifecycleChanges(
		of store: WorkspaceStateStore,
		owner: WorkspaceLifecycleOwner
	) -> UUID
	{
		return store.observe
		{
			[weak self, weak store] value in
			guard let self, let store, !self.retired, self.stores[owner] === store
			else
			{
				return
			}
			if case .source = owner, value.identity != self.model.source
			{
				self.dispatch(
					.sourceOpened(value.identity),
					publish: false
				)
				if self.model.source == value.identity
				{
					Task
					{
						await self.reloadWorkspaces()
					}
				}
			}
			self.dispatch(
				.ownerObserved(store.lifecycleObservation),
				publish: false
			)
			if let workspace = store.managedWorkspace
			{
				self.dispatch(
					.bindingObserved(
						WorkspaceLifecycleOwnerReference(
							owner: owner,
							workspace: value.identity
						),
						workspace
					),
					publish: false
				)
			}
		}
	}

	private func observePublications(
		of store: WorkspaceStateStore,
		owner: WorkspaceLifecycleOwner
	) -> UUID
	{
		return store.observePublications
		{
			[weak self, weak store] publication in
			guard let self, let store, !self.retired, self.stores[owner] === store
			else
			{
				return
			}
			for command in publication.commands
			{
				self.onPresentationCommand?(command)
			}
			guard self.model.selectedOwner == owner, self.dispatchDepth == 0
			else
			{
				return
			}
			if !publication.coalescible
			{
				self.pendingPublication?.cancel()
				self.pendingPublication = nil
				self.onChange?(self.currentSnapshot)
				return
			}
			guard self.pendingPublication == nil
			else
			{
				return
			}
			let epoch = self.model.selectionEpoch
			self.pendingPublication = Task
			{
				await store.factoryDependencies.publicationWait()
				guard !Task.isCancelled, !self.retired, self.stores[owner] === store,
						self.model.selectedOwner == owner,
						self.model.selectionEpoch == epoch
				else
				{
					return
				}
				self.pendingPublication = nil
				self.onChange?(self.currentSnapshot)
			}
		}
	}

	func decorated(
		_ original: ConversationSnapshot,
		owner: WorkspaceLifecycleOwner
	) -> ConversationSnapshot
	{
		var snapshot = original
		snapshot.workspaceOwner = stores[owner].map
		{
			WorkspaceLifecycleOwnerReference(
				owner: owner,
				workspace: $0.model.identity
			)
		}
		snapshot.workspaceSelectionEpoch = model.selectionEpoch
		if case .managed(
			let id,
			_
		) = model.selectedOwner
		{
			snapshot.selectedTaskWorkspaceID = id
		}
		snapshot.taskWorkspaceMessage = model.message
		snapshot.taskWorkspaces = taskWorkspaceChoices()
		let running = model.owners.values.filter(\.requiresRemoteStop).count
		let waiting = model.owners.values.filter
		{
			$0.executionState == .awaitingApproval || $0.executionState == .awaitingAnswer
		}.count
		snapshot.taskStatusSummary = running == 0 ? nil :
			"\(running) running task\(running == 1 ? "" : "s")" +
			(waiting == 0 ? "" : " · \(waiting) need a response")
		return snapshot
	}

	private func taskWorkspaceChoices() -> [TaskWorkspaceChoice]
	{
		let visibleWorkspaces = model.workspaces.values.filter
		{
			workspace in
			workspace.sourceProjectPath == model.source.canonicalCheckoutPath || model.owners
				.contains
				{
					owner, observation in
					guard case .managed(
						let workspaceID,
						_
					) = owner
					else
					{
						return false
					}
					return workspaceID == workspace.id && observation.requiresRemoteStop
				}
		}
		let orderedWorkspaces = visibleWorkspaces.sorted
		{
			$0.createdAt < $1.createdAt
		}
		return orderedWorkspaces.map
		{
			taskWorkspaceChoice(for: $0)
		}
	}

	private func taskWorkspaceChoice(for workspace: TaskWorkspace) -> TaskWorkspaceChoice
	{
		let observation = model.owners.first
		{
			owner, _ in
			guard case .managed(
				let workspaceID,
				_
			) = owner
			else
			{
				return false
			}
			return workspaceID == workspace.id
		}?.value
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
			issue: model.recoveryIssues[workspace.id]?.rawValue,
			canRemoveCheckout: canRemoveCheckout
		)
	}

}
