import Foundation

extension TaskWorkspaceCoordinator
{
	func perform(_ effect: WorkspaceCoordinatorEffect)
	{
		switch effect
		{
		case .git(let operation):
			performGitOperation(operation)
		case .attachVerifiedOwner(
			let request,
			let workspace
		):
			attachVerifiedOwner(
				request,
				workspace: workspace
			)
		case .reserveCleanup(let request):
			let accepted = request.owner.flatMap
			{
				store(for: $0)
			}?
			.reserveCleanup(request) ?? (request.owner == nil)
			dispatch(.cleanupReserved(
				request,
				accepted: accepted
			))
		case .drainCleanup(let request):
			drainCleanupPersistence(request)
		case .releaseCleanup(let request):
			request.owner.flatMap
			{
				store(for: $0)
			}?
			.releaseCleanup(request)
		case .managedRecordRecoveryConflicted(
			let reference,
			let expected,
			let cleanup,
			let message
		):
			store(for: reference)?.acceptManagedRecordRecoveryConflict(
				reference,
				expected: expected,
				cleanup: cleanup,
				message: message
			)
		case .managedRecordRecovered(
			let reference,
			let expected,
			let recovered
		):
			store(for: reference)?.acceptRecoveredManagedRecord(
				reference,
				expected: expected,
				recovered: recovered
			)
		case .removeOwner(let reference):
			removeOwner(reference)
		case .cancelRequest(let id):
			for task in jobs[id]?.values ?? Dictionary<UUID, Task<Void, Never>>().values
			{
				task.cancel()
			}
		case .confirmQuit(let request):
			onConfirmQuit?(request)
		case .stopOwners(
			let request,
			let references
		):
			guard freezeOwners(request)
			else
			{
				return
			}
			for reference in references
			{
				store(for: reference)?.inputs.stop()
			}
		case .freezeWritesAndDrainQuit(
			let request,
			let references
		):
			drainQuitPersistence(
				request,
				references: references
			)
		case .completeQuit(
			let request,
			let approved
		):
			completeQuit(
				request,
				approved: approved
			)
		case .notifyQuitCompletion(
			let request,
			let approved
		):
			if !approved
			{
				for store in stores.values
				{
					store.thawInputsAfterQuit(request)
				}
			}
			onQuitCompleted?(
				request,
				approved
			)
			if approved
			{
				onAllTasksFinished?()
			}
			else
			{
				onStopAllFailed?()
			}
		case .ownerTransition(
			let previous,
			let current
		):
			if let store = store(for: current.reference)
			{
				onTaskSnapshot?(TaskNotificationPresentation(
					model: store.model,
					owner: current.reference
				))
			}
			if previous?.requiresRemoteStop == true, !current.requiresRemoteStop,
				!model.hasRemoteOwners, !model.hasUncertainOwners,
				case .idle = model.quit
			{
				onAllTasksFinished?()
			}
		}
	}

	private func performGitOperation(_ operation: WorkspaceLifecycleGitEffect)
	{
		let requestID: UUID
		switch operation
		{
		case .recover(let request):
			requestID = request.requestID
		case .create(let request):
			requestID = request.requestID
		case .verifySelection(let request):
			requestID = request.requestID
		case .remove(let request):
			requestID = request.requestID
		case .cancelCreation(
			let id,
			_
		):
			requestID = id
		}
		launch(requestID)
		{
			let runner = WorkspaceLifecycleGitRunner(manager: self.manager)
			let result = await runner.perform(operation)
			self.dispatch(result)
		}
	}

	private func attachVerifiedOwner(
		_ request: WorkspaceSelectionRequest,
		workspace: TaskWorkspace
	)
	{
		let owner = WorkspaceLifecycleOwner.managed(
			workspaceID: workspace.id,
			sessionID: request.ownerSessionID
		)
		if stores[owner] == nil
		{
			let identity = WorkspaceIdentity(
				sessionID: request.ownerSessionID,
				canonicalCheckoutPath: workspace.checkoutPath
			)
			let store = makeStore(WorkspaceStoreConfiguration(
				reference: WorkspaceLifecycleOwnerReference(
					owner: owner,
					workspace: identity
				),
				managedWorkspace: workspace
			))
			register(
				store,
				owner: owner
			)
			store.inputs.start()
		}
	}

	private func removeOwner(_ reference: WorkspaceLifecycleOwnerReference)
	{
		guard let store = store(for: reference)
		else
		{
			return
		}
		if let token = tokens.removeValue(forKey: reference.owner)
		{
			store.removeObserver(token)
		}
		if let token = publicationTokens.removeValue(forKey: reference.owner)
		{
			store.removePublicationObserver(token)
		}
		stores.removeValue(forKey: reference.owner)
		store.shutdown()
	}

	private func completeQuit(
		_ request: WorkspaceQuitRequest,
		approved: Bool
	)
	{
		if !approved || request.purpose == .stopAll
		{
			for store in stores.values
			{
				store.thawInputsAfterQuit(request)
			}
		}
		Task
		{
			let frozen = Set(self.stores.values.compactMap
			{
				store -> WorkspaceLifecycleOwnerReference? in
				guard let reservation = store.model.lifecycle.quitReservation,
						reservation.requestID == request.requestID,
						reservation.reference == store.lifecycleObservation.reference
				else
				{
					return nil
				}
				return reservation.reference
			})
			self.dispatch(.quitCompletionRequested(
				request,
				approved: approved,
				frozenOwners: frozen
			))
		}
	}

	private func drainCleanupPersistence(_ request: WorkspaceCleanupRequest)
	{
		launch(request.requestID)
		{
			do
			{
				if let reference = request.owner,
					let store = self.store(for: reference)
				{
					try await store.awaitAcceptedPersistence()
				}
				try await self.sourceStore.drainPersistence(
					projectPath: request.expected.checkoutPath
				)
				self.dispatch(.cleanupPersistenceDrained(
					request,
					.succeeded(())
				))
			}
			catch
			{
				self.dispatch(.cleanupPersistenceDrained(
					request,
					.failed(OperationFailure(
						message: error.localizedDescription,
						outcomeIsUncertain: false
					))
				))
			}
		}
	}

	private func drainQuitPersistence(
		_ request: WorkspaceQuitRequest,
		references: Set<WorkspaceLifecycleOwnerReference>
	)
	{
		guard freezeOwners(request)
		else
		{
			return
		}
		let captured = references.compactMap
		{
			store(for: $0)
		}
		let pendingLifecycle = jobs.keys.filter
		{
			$0 != request.requestID
		}
		launch(request.requestID)
		{
			do
			{
				for id in pendingLifecycle
				{
					await self.wait(id)
				}
				for store in captured
				{
					try await store.awaitAcceptedPersistence()
				}
				try await self.sourceStore.drainPersistence(projectPath: nil)
				guard references.allSatisfy(
					{
						reference in
						self.store(for: reference)?.model.lifecycle
							.quitReservation == WorkspaceQuitReservation(
								requestID: request.requestID,
								reference: reference
							)
					}
				)
				else
				{
					self.dispatch(.quitPersistenceDrained(
						request,
						.failed(OperationFailure(
							message: "Workspace ownership changed before quitting.",
							outcomeIsUncertain: false
						))
					))
					return
				}
				self.dispatch(.quitPersistenceDrained(
					request,
					.succeeded(())
				))
			}
			catch
			{
				self.dispatch(.quitPersistenceDrained(
					request,
					.failed(OperationFailure(
						message: error.localizedDescription,
						outcomeIsUncertain: false
					))
				))
			}
		}
	}

	private func freezeOwners(_ request: WorkspaceQuitRequest) -> Bool
	{
		let captured = Array(stores.values)
		for store in captured
		{
			guard store.freezeInputsForQuit(request)
			else
			{
				for store in captured
				{
					store.thawInputsAfterQuit(request)
				}
				dispatch(.quitReservationFailed(
					request,
					OperationFailure(
						message: "Workspace inputs could not be reserved for quitting.",
						outcomeIsUncertain: false
					)
				))
				return false
			}
		}
		return true
	}
}
