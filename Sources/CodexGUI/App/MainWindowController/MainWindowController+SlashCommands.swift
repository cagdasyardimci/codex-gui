import AppKit

extension MainWindowController
{
	func handlePresentationCommand(_ command: WorkspacePresentationCommand)
	{
		switch command
		{
		case .openSignIn(let url): NSWorkspace.shared.open(url)
		case .slashCommand(let request): presentSlashCommand(request)
		case .taskFinished: break
		}
	}

	/// Equality includes revision, text and attachments so retained picker callbacks cannot
	/// consume a later edit within the same draft lifetime.
	func slashRequestIsCurrent(_ request: SlashCommandPresentationRequest) -> Bool
	{
		Self.slashRequestIsCurrent(
			request,
			model: currentStore.model
		)
	}

	static func slashRequestIsCurrent(
		_ request: SlashCommandPresentationRequest,
		model: WorkspaceModel
	) -> Bool
	{
		request.context.belongsTo(
			workspace: model.identity,
			generation: model.connection.generation
		)
			&& request.context.threadID == request.conversation.threadID
			&& request.conversation == model.conversations.selectedConversation
			&& model.composer.drafts[request.conversation] == request.draft
			&& !model.lifecycle.isShutdown
	}

	func presentSlashCommand(_ request: SlashCommandPresentationRequest)
	{
		guard slashRequestIsCurrent(request)
		else
		{
			return
		}
		let snapshot = coordinator?.currentSnapshot ?? currentStore.currentSnapshot
		let target = WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		)
		let accept: (WorkspaceIntent) -> Void =
		{
			[weak self] intent in
			guard let self, self.slashRequestIsCurrent(request),
					self.currentStore.currentSnapshot
					.slashCommandUnavailableReasons[request.invocation.id] == nil,
					target.accepts(intent)
			else
			{
				return
			}
			if target.dispatch(intent), self.slashRequestIsCurrent(request)
			{
				target.dispatch(.acknowledgeSlashCommand(request))
				self.conversation.modelEffortPopover?.close()
				self.conversation.approvalPolicyPopover?.close()
				self.conversation.configurePreferenceCallbacks()
			}
		}
		let acknowledge: () -> Void =
		{
			[weak self] in
			guard self?.slashRequestIsCurrent(request) == true
			else
			{
				return
			}
			target.dispatch(.acknowledgeSlashCommand(request))
		}
		switch request.invocation.id
		{
		case .model, .reasoning:
			conversation.modelEffortPopover?.close()
			conversation.showModelAndEffort()
			conversation.modelEffortController.onSelectModel =
			{
				accept(.selectModel($0))
			}
			conversation.modelEffortController.onSelectEffort =
			{
				accept(.selectEffort($0))
			}
			conversation.modelEffortController.onSetFastMode =
			{
				accept(.setFastMode($0))
			}
		case .permissions:
			if request.invocation.trimmedArguments == "full"
			{
				conversation.requestApprovalMode(.fullAccess)
				{
					accept(.selectApprovalMode($0))
				}
			}
			else
			{
				conversation.showApprovalPolicy()
				conversation.approvalPolicyController.onSelect =
				{
					[weak self] mode in
					guard let self, self.slashRequestIsCurrent(request)
					else
					{
						return
					}
					self.conversation.requestApprovalMode(mode)
					{
						accept(.selectApprovalMode($0))
					}
				}
			}
		case .rename:
			navigation.presentRenameThread
			{
				accept(.renameThread($0))
			}
		case .delete:
			guard let thread = snapshot.threads
				.first(where:
					{
						$0.id == snapshot.selectedThreadID
					})
			else
			{
				return
			}
			navigation.confirmDeleteTask(thread)
			{
				accept(.deleteTask($0))
			}
		case .fork:
			presentForkRecovery(
				snapshot: snapshot,
				request: request,
				target: target
			)
		case .resume:
			presentResumePicker(
				snapshot: snapshot,
				request: request,
				target: target
			)
		case .plan:
			presentPlanSettingsRetry(
				request: request,
				target: target
			)
		case .review:
			presentReviewTarget(
				request: request,
				target: target
			)
		case .skills:
			presentSkillsPicker(
				snapshot: snapshot,
				request: request,
				accept: accept
			)
		case .mention:
			conversation.openFileSearch()
			conversation.fileSelectionReceiver =
			{
				[weak self] item in
				guard let self, self.slashRequestIsCurrent(request),
						target.accepts(.attachContext(item))
				else
				{
					return
				}
				acknowledge()
				target.dispatch(.attachContext(item))
			}
		case .status:
			showStatus()
			acknowledge()
		case .diff:
			openCurrentChanges()
			acknowledge()
		case .copy:
			guard let response = Self.latestAgentResponse(in: snapshot)
			else
			{
				return
			}
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(
				response,
				forType: .string
			)
			acknowledge()
		default: break
		}
	}

	static func latestAgentResponse(in snapshot: ConversationSnapshot) -> String?
	{
		snapshot.entries.last(where:
			{
				$0.kind == .agent && !$0.body.isEmpty
			})?.body
	}

	static func forkRecoveryCommands(
		in snapshot: ConversationSnapshot,
		originalThreadID: String
	) -> [PaletteCommand]
	{
		let originalIsAvailable = snapshot.threads.contains
		{
			$0.cwd == snapshot.projectPath && $0.id == originalThreadID
		}
		let candidates = snapshot.threads
			.filter
			{
				$0.cwd == snapshot.projectPath && $0.id != originalThreadID
			}
		return candidates.map
		{
			thread in
			PaletteCommand(
				title: thread.displayTitle,
				detail: "Saved conversation · \(thread.id) · \(thread.preview ?? "")",
				destination: .conversation(thread.id)
			)
		} + [PaletteCommand(
			title: "Continue Original Chat",
			detail: originalIsAvailable
				? "A fork may remain saved. Resume work in the original chat."
				: "Unavailable: the original chat is absent from the refreshed checkout list.",
			destination: .action("continue-original"),
			isEnabled: originalIsAvailable
		)]
	}

	private func presentForkRecovery(
		snapshot: ConversationSnapshot,
		request: SlashCommandPresentationRequest,
		target: WorkspaceIntentTarget
	)
	{
		guard let window, window.attachedSheet == nil,
				let uncertain = currentStore.model.composerCommands.uncertainFork,
				let originalThreadID = uncertain.threadID
		else
		{
			return
		}
		commandPalette.onChoose =
		{
			[weak self] destination in
			guard let self, self.slashRequestIsCurrent(request),
					self.currentStore.model.composerCommands.uncertainFork == uncertain
			else
			{
				return
			}
			switch destination
			{
			case .conversation(let id): target.dispatch(.recoverFork(
					request,
					.resume(threadID: id)
				))
			case .action("continue-original"):
				target.dispatch(.recoverFork(
					request,
					.continueOriginal
				))
			default: break
			}
		}
		commandPalette.present(
			in: window,
			commands: Self.forkRecoveryCommands(
				in: snapshot,
				originalThreadID: originalThreadID
			),
			title: "Resolve fork outcome",
			searchPlaceholder: "Inspect refreshed saved conversations",
			informativeText: "The fork may have been saved "
				+ "even though its result was not confirmed. "
				+ "Choose a saved conversation to continue, or Continue Original Chat. "
				+ "Any saved fork remains in the conversation list."
		)
	}

	private func presentResumePicker(
		snapshot: ConversationSnapshot,
		request: SlashCommandPresentationRequest,
		target: WorkspaceIntentTarget
	)
	{
		guard let window, window.attachedSheet == nil
		else
		{
			return
		}
		let commands = snapshot.threads.map
		{
			PaletteCommand(
				title: $0.displayTitle,
				detail: "Conversation · \($0.id)",
				destination: .conversation($0.id)
			)
		}
		commandPalette.onChoose =
		{
			[weak self] destination in
			guard let self, self.slashRequestIsCurrent(request),
					case .conversation(let id) = destination
			else
			{
				return
			}
			let invocation = SlashCommandInvocation(
				descriptor: request.invocation.descriptor,
				arguments: id
			)
			target.dispatch(.completeSlashCommand(
				request,
				invocation
			))
		}
		commandPalette.present(
			in: window,
			commands: commands,
			title: "Resume conversation",
			searchPlaceholder: "Search saved conversations"
		)
	}

	private func presentSkillsPicker(
		snapshot: ConversationSnapshot,
		request: SlashCommandPresentationRequest,
		accept: @escaping (WorkspaceIntent) -> Void
	)
	{
		guard let window, window.attachedSheet == nil
		else
		{
			return
		}
		let skills = snapshot.skillCatalog?.skills.filter(\.enabled) ?? []
		let commands = [PaletteCommand(
			title: "No skill",
			detail: "Use the next message without a selected skill",
			destination: .action("none")
		)]
			+ skills.enumerated().map
			{
				index, skill in
				PaletteCommand(
					title: skill.displayName ?? skill.name,
					detail: skill.shortDescription ?? skill.description,
					destination: .action(String(index)),
					searchText: skill.searchText
				)
			}
		commandPalette.onChoose =
		{
			[weak self] destination in
			guard let self, self.slashRequestIsCurrent(request),
					case .action(let value) = destination
			else
			{
				return
			}
			var context = self.currentStore.currentSnapshot.projectContext
			if value == "none"
			{
				context.selectedSkill = nil
			}
			else
			{
				guard let index = Int(value), skills.indices.contains(index)
				else
				{
					return
				}
				context.selectedSkill = ProjectSkillSelection(
					name: skills[index].name,
					description: skills[index].description,
					path: skills[index].path
				)
			}
			accept(.updateProjectContext(context))
		}
		commandPalette.present(
			in: window,
			commands: commands,
			title: "Choose a skill",
			searchPlaceholder: "Search available skills"
		)
	}

	private func presentPlanSettingsRetry(
		request: SlashCommandPresentationRequest,
		target: WorkspaceIntentTarget
	)
	{
		guard let window, window.attachedSheet == nil
		else
		{
			return
		}
		let alert = NSAlert()
		alert.messageText = "Reapply conversation mode"
		alert.informativeText = "The previous settings change was not confirmed. "
			+ "Choose the mode to apply explicitly."
		alert.addButton(withTitle: "Reapply Plan")
		alert.addButton(withTitle: "Reset Default")
		alert.addButton(withTitle: "Cancel")
		alert.beginSheetModal(for: window)
		{
			[weak self] response in
			guard let self, self.slashRequestIsCurrent(request)
			else
			{
				return
			}
			switch response
			{
			case .alertFirstButtonReturn: target.dispatch(.retryPlanSettings(
					request,
					.plan
				))
			case .alertSecondButtonReturn: target.dispatch(.retryPlanSettings(
					request,
					.default
				))
			default: break
			}
		}
	}

	private func presentReviewTarget(
		request: SlashCommandPresentationRequest,
		target: WorkspaceIntentTarget
	)
	{
		guard let window, window.attachedSheet == nil
		else
		{
			return
		}
		let picker = NSPopUpButton()
		picker.addItems(withTitles: [
			"Uncommitted changes",
			"Base branch",
			"Commit",
			"Custom instructions"
		])
		picker.setAccessibilityLabel("Review target")
		let field = NSTextField(string: "")
		field.placeholderString = "Branch, commit SHA, or instructions (when needed)"
		field.setAccessibilityLabel("Review target value")
		let accessory = AppKitLayout.verticalStack([picker, field])
		accessory.frame = NSRect(
			x: 0,
			y: 0,
			width: 420,
			height: 64
		)
		let alert = NSAlert()
		alert.messageText = "Review changes"
		alert.informativeText = "Choose the changes or instructions Codex should review."
		alert.accessoryView = accessory
		alert.addButton(withTitle: "Start Review")
		alert.addButton(withTitle: "Cancel")
		alert.beginSheetModal(for: window)
		{
			[weak self] response in
			guard response == .alertFirstButtonReturn, let self,
					self.slashRequestIsCurrent(request)
			else
			{
				return
			}
			let kinds = ["uncommitted", "base", "commit", "custom"]
			let kind = kinds[picker.indexOfSelectedItem]
			let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			let arguments = kind == "uncommitted" ? kind : "\(kind) \(value)"
			let invocation = SlashCommandInvocation(
				descriptor: request.invocation.descriptor,
				arguments: arguments
			)
			target.dispatch(.completeSlashCommand(
				request,
				invocation
			))
		}
	}
}
