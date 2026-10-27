import AppKit

// Every callback retains the workspace target captured by the rendered presentation.
extension MainWindowController
{
	func configureNavigationActions(target: WorkspaceIntentTarget)
	{
		navigation
			.onOpenProject =
			{
				[weak self] in
				guard target.accepts(.newChat)
				else
				{
					return
				}
				self?.onOpenProjectRequest()
			}
		navigation.onSelectRecentProject =
		{
			target.dispatch(.openProject($0))
		}
		navigation.onRemoveProject =
		{
			target.dispatch(.removeProject($0))
		}
		navigation.onArchiveProjectChats =
		{
			target.dispatch(.archiveProjectChats($0))
		}
		navigation.onToggleProjectPin =
		{
			target.dispatch(.toggleProjectPin($0))
		}
		navigation.onRenameProject =
		{
			target.dispatch(.renameProject(
				$0,
				$1
			))
		}
		navigation.onNewChatInProject =
		{
			target.dispatch(.newChatInProject($0))
		}
		navigation.onNewChat =
		{
			target.dispatch(.newChat)
		}
		navigation.onRefresh =
		{
			target.dispatch(.refreshThreads)
		}
		navigation.onLoadSidebarThreads =
		{
			target.dispatch(.loadSidebarThreads)
		}
		navigation.onSelectSidebarTask =
		{
			target.dispatch(.selectSidebarTask($0))
		}
		navigation.onSelectThread =
		{
			target.dispatch(.selectThread($0))
		}
		navigation.onSelectPinnedTask =
		{
			target.dispatch(.selectPinnedTask($0))
		}
		navigation.onToggleTaskPin =
		{
			target.dispatch(.toggleTaskPin($0))
		}
		navigation.onRenameTask =
		{
			target.dispatch(.renameTask(
				$0,
				$1
			))
		}
		navigation.onSelectWorkspace =
		{
			target.dispatch(.selectWorkspace($0))
		}
		navigation.onCreateTask =
		{
			target.dispatch(.createTask($0))
		}
		navigation.onRemoveWorkspace =
		{
			target.dispatch(.removeWorkspace($0))
		}
		navigation.onCancelWorkspaceCreation =
		{
			target.dispatch(.cancelCreation($0))
		}
		navigation
			.onReturnToActiveTask =
			{
				if let id = target.store.model.execution
					.activeThreadID
				{
					target.dispatch(.selectThread(id))
				}
			}
		navigation.onSetArchivedFilter =
		{
			target.dispatch(.setArchived($0))
		}
		navigation.onRenameThread =
		{
			target.dispatch(.renameThread($0))
		}
		navigation.onArchiveTask =
		{
			target.dispatch(.archiveTask($0))
		}
		navigation.onDeleteTask =
		{
			target.dispatch(.deleteTask($0))
		}
		navigation.onArchiveThread =
		{
			target.dispatch(.archiveThread)
		}
	}

	func configureSettingsAndStatusActions(target: WorkspaceIntentTarget)
	{
		settings.onSelectApprovalMode =
		{
			[weak self] mode in
			self?.conversation.requestApprovalMode(mode)
			{
				target.dispatch(.selectApprovalMode($0))
			}
		}
		settings.onApplyConfigurationDefaults =
		{
			values, editedKeys in
			guard let update = RunConfigurationDefaultsUpdate(
				effectiveConfig: values,
				editedKeys: editedKeys
			)
			else
			{
				return
			}
			target.dispatch(.applyConfigurationDefaults(update))
		}
		settings.onClose =
		{
			[weak self] in self?.dismissSettings()
		}
		settings.onLogin =
		{
			target.dispatch(.signIn)
		}
		settings.onReconnect =
		{
			target.dispatch(.reconnect)
		}
		settings.onShowBackendDetails =
		{
			[weak self] in self?.showBackendDetails()
		}
		statusView.onReconnect =
		{
			target.dispatch(.reconnect)
		}
		statusView.onShowBackendDetails =
		{
			[weak self] in self?.showBackendDetails()
		}
		statusView.onLogout =
		{
			[weak self] in
			self?.sourceStore.inputs.signOut()
		}
		statusView.onShowSettings =
		{
			[weak self] in
			self?.statusPopover?.close()
			self?.showSettings()
		}
		statusView.onShowUsage =
		{
			[weak self] in
			self?.statusPopover?.close()
			self?.showSettings()
			self?.settings.showUsage()
		}
	}

	func configureInspectorActions(target: WorkspaceIntentTarget)
	{
		inspector.changes.onSelectReviewTurn =
		{
			target.dispatch(.selectReview($0))
		}
		inspector.changes.onSetReviewed =
		{
			target.dispatch(.setReviewed(
				$0,
				$1
			))
		}
		inspector.changes
			.onPrepareChangeRequest =
			{
				target.dispatch(.prepareChangeRequest(
					$0,
					$1
				))
			}
	}

	func configureMessageSearchActions(target: WorkspaceIntentTarget)
	{
		let store = target.store
		let owner = target.reference
		let storeIdentity = ObjectIdentifier(store)
		if messageSearchStoreIdentity != storeIdentity || messageSearchOwner != owner
		{
			// Retire the previous owner's query before callbacks are rebound to another store.
			messageSearch.dismiss()
		}
		messageSearchStoreIdentity = storeIdentity
		messageSearchOwner = owner
		messageSearch.onSearch =
		{
			target.dispatch(.search($0))
		}
		messageSearch.onOpenHit =
		{
			target.dispatch(.jumpHit($0))
		}
		messageSearch.onLoadMore =
		{
			target.dispatch(.loadMoreSearch)
		}
		messageSearch.onDismiss =
		{
			guard WorkspaceLifecycleReducer.reference(store.model) == owner
			else
			{
				return
			}
			// Dismissal also retires a store that is no longer the selected UI owner.
			store.inputs.dismissMessageSearch()
		}
	}

	func configureConversationActions(target: WorkspaceIntentTarget)
	{
		conversation.onViewChanges =
		{
			[weak self] in
			guard target.accepts(.loadEarlierTurns)
			else
			{
				return
			}
			self?.openChangesToolTab(scope: .lastTurn)
		}
		let skillStore = currentStore
		conversation.onRemoveSkill =
		{
			skill in
			var context = skillStore.currentSnapshot.projectContext
			guard context.selectedSkill == skill
			else
			{
				return
			}
			context.selectedSkill = nil
			target.dispatch(.updateProjectContext(context))
		}
		conversation.onSelectSkill =
		{
			skill in
			guard skillStore.currentSnapshot.skillCatalog?.skills.contains(where:
				{
					$0.path == skill.path && $0.enabled
				}) == true
			else
			{
				return
			}
			var context = skillStore.currentSnapshot.projectContext
			context.selectedSkill = ProjectSkillSelection(
				name: skill.name,
				description: skill.description,
				path: skill.path
			)
			target.dispatch(.updateProjectContext(context))
		}
		conversation.onSlashCommand =
		{
			target.dispatch(.slashCommand($0))
		}
		conversation.onDraftChange =
		{
			target.dispatch(.editDraft($0))
		}
		conversation.onAddContext =
		{
			target.dispatch(.attachContext($0))
		}
		conversation.onImportImageContext =
		{
			target.attachImportedImage($0)
		}
		conversation.onRemoveContext =
		{
			target.dispatch(.removeContext($0))
		}
		conversation.onSend =
		{
			target.dispatch(.send)
		}
		conversation.onRetryLockedChat =
		{
			target.dispatch(.retryLockedChat)
		}
		conversation.onForkLockedChat =
		{
			guard let id = target.store.currentSnapshot.selectedThreadID,
					target.store.model.conversations.lockedThreadIDs.contains(id),
					case .command(let command) = SlashCommandParser.parse("/fork"),
					target.accepts(.slashCommand(command))
			else
			{
				return
			}
			target.dispatch(.slashCommand(command))
		}
		conversation.onSteer =
		{
			target.dispatch(.steer($0))
		}
		conversation.onStop =
		{
			target.dispatch(.stop)
		}
		conversation.onRespond =
		{
			target.dispatch(.respond(
				$0,
				$1
			))
		}
		conversation
			.onReturnToActiveTask =
			{
				if let id = target.store.model.execution
					.activeThreadID
				{
					target.dispatch(.selectThread(id))
				}
			}
		conversation.onSelectModel =
		{
			target.dispatch(.selectModel($0))
		}
		conversation.onSelectEffort =
		{
			target.dispatch(.selectEffort($0))
		}
		conversation.onSelectApprovalMode =
		{
			target.dispatch(.selectApprovalMode($0))
		}
		conversation.onSetFastMode =
		{
			target.dispatch(.setFastMode($0))
		}
		conversation
			.onInsertPath =
			{
				[weak self] in
				guard target.accepts(.editDraft(""))
				else
				{
					return
				}
				self?.onInsertPathRequest()
			}
		conversation.onLoadEarlierTurns =
		{
			target.dispatch(.loadEarlierTurns)
		}
		conversation.onLoadEarlierTurnReferences =
		{
			target.dispatch(.loadEarlierTurnReferences)
		}
		conversation
			.onConversationViewportChanged =
			{
				target.dispatch(.updateConversationViewport($0))
			}
		conversation.onLoadTurnPreview =
		{
			target.dispatch(.loadTurnPreview($0))
		}
		conversation.onJumpToTurnReference =
		{
			turnID in
			guard let threadID = target.conversation.threadID
			else
			{
				return
			}
			target.dispatch(.jumpTarget(ConversationJumpTarget(
				threadID: threadID,
				turnID: turnID,
				itemID: nil,
				filePath: nil,
				kind: .userRequest,
				title: "Turn"
			)))
		}
		conversation.onToggleBookmark =
		{
			target.dispatch(.toggleBookmark($0))
		}
		conversation.onJumpDisplayed =
		{
			target.dispatch(.acknowledgeJump)
		}
	}

}
