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
		let taskPresentation = taskPresentationCache.presentation(for: model)
		snapshot.taskWorkspaces = taskPresentation.choices
		snapshot.taskStatusSummary = taskPresentation.statusSummary
		return snapshot
	}
}
