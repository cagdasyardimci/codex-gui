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
				}; self?.onOpenProjectRequest()
			}
		navigation.onSelectRecentProject =
		{
			target.dispatch(.openProject($0))
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
		navigation.onSelectThread =
		{
			target.dispatch(.selectThread($0))
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
		statusView.onShowSettings =
		{
			[weak self] in self?.showSettings()
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
	}

	func configureConversationActions(target: WorkspaceIntentTarget)
	{
		conversation.onDraftChange =
		{
			target.dispatch(.editDraft($0))
		}
		conversation.onAddContext =
		{
			target.dispatch(.attachContext($0))
		}
		conversation.onRemoveContext =
		{
			target.dispatch(.removeContext($0))
		}
		conversation.onReuseContext =
		{
			target.dispatch(.reuseReference($0))
		}
		conversation.onSend =
		{
			target.dispatch(.send)
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
				}; self?.onInsertPathRequest()
			}
		conversation.onLoadEarlierTurns =
		{
			target.dispatch(.loadEarlierTurns)
		}
		conversation.onToggleBookmark =
		{
			target.dispatch(.toggleBookmark($0))
		}
		conversation.onJumpTarget =
		{
			target.dispatch(.jumpTarget($0))
		}
		conversation.onJumpDisplayed =
		{
			target.dispatch(.acknowledgeJump)
		}
	}

}
