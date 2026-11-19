import AppKit

extension MainWindowController
{
	func configureVoiceChat(in window: NSWindow)
	{
		conversation.startVoiceChatButton.target = self
		conversation.startVoiceChatButton.action = #selector(startVoiceChat)

		for controls in [conversation.voiceChatControls, floatingVoiceChatControls]
		{
			controls.microphone.target = self
			controls.microphone.action = #selector(toggleVoiceChatMicrophone)
			controls.speakers.target = self
			controls.speakers.action = #selector(toggleVoiceChatSpeakers)
			controls.end.target = self
			controls.end.action = #selector(endVoiceChat)
		}

		if let content = window.contentView
		{
			voiceChat.webRTCHost = content
			let surface = floatingVoiceChatSurface
			surface.translatesAutoresizingMaskIntoConstraints = false
			surface.addSubview(floatingVoiceChatControls)
			floatingVoiceChatControls.translatesAutoresizingMaskIntoConstraints = false
			content.addSubview(surface)
			NSLayoutConstraint.activate([
				surface.trailingAnchor.constraint(
					equalTo: content.trailingAnchor,
					constant: -16
				),
				surface.bottomAnchor.constraint(
					equalTo: content.bottomAnchor,
					constant: -16
				),
				floatingVoiceChatControls.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
				floatingVoiceChatControls.trailingAnchor
					.constraint(equalTo: surface.trailingAnchor),
				floatingVoiceChatControls.topAnchor.constraint(equalTo: surface.topAnchor),
				floatingVoiceChatControls.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
			])
		}
		floatingVoiceChatSurface.isHidden = true
		voiceChat.onChange =
		{
			[weak self] in self?.refreshVoiceChatPresentation()
		}
		voiceChat.onPlaybackLevel =
		{
			[weak self] level in
			self?.conversation.voiceChatOrb.setPlaybackLevel(level)
			self?.floatingVoiceChatControls.orb?.setPlaybackLevel(level)
		}
		voiceChat.onThreadStarted =
		{
			[weak self] store, id in
			guard self?.currentStore === store
			else
			{
				return
			}
			let selection = store.inputs.selectThread(id)
			Task
			{
				_ = await selection?.wait()
				if !store.isRetired
				{
					store.inputs.refreshThreads()
				}
			}
		}
	}

	func refreshVoiceChatControls(_ snapshot: ConversationSnapshot)
	{
		voiceChat.refreshAvailability(store: currentStore)
		let showing = voiceChat.isShowingCall(
			store: currentStore,
			threadID: snapshot.selectedThreadID
		)
		conversation.voiceChatShowing = showing
		conversation.voiceChatAcceptsText = voiceChat.acceptsText
		conversation.voiceChatOrb.isHidden = !showing
		conversation.voiceChatOrb.setActive(showing)
		conversation.voiceChatControls.isHidden = !showing
		conversation.startVoiceChatButton.reconnectsVoiceChat = voiceChat.canReconnect(
			store: currentStore
		)
		conversation.canStartVoiceChat = voiceChat.canStart(store: currentStore)
			&& !snapshot.chatLocked
		let showsFloatingCall = voiceChat.hasCall && !showing
		floatingVoiceChatSurface.isHidden = !showsFloatingCall
		floatingVoiceChatControls.orb?.setActive(showsFloatingCall)
		for controls in [conversation.voiceChatControls, floatingVoiceChatControls]
		{
			controls.render(
				microphoneMuted: voiceChat.microphoneMuted,
				speakersMuted: voiceChat.speakersMuted
			)
		}
	}

	func voiceChatNavigationSnapshot(_ snapshot: ConversationSnapshot) -> ConversationSnapshot
	{
		guard !snapshot.showingArchived, let thread = voiceChat.activeThread(in: currentStore),
				!snapshot.threads.contains(where:
				{
					$0.id == thread.id
				})
		else
		{
			return snapshot
		}
		var snapshot = snapshot
		snapshot.threads.insert(
			thread,
			at: 0
		)
		if snapshot.sidebarThreads?.contains(where:
			{
				$0.id == thread.id
			}) == false
		{
			snapshot.sidebarThreads?.insert(
				thread,
				at: 0
			)
		}
		return snapshot
	}

	private func refreshVoiceChatPresentation()
	{
		guard let snapshot = latestSnapshot
		else
		{
			return
		}
		refreshVoiceChatControls(snapshot)
		let navigationSnapshot = voiceChatNavigationSnapshot(snapshot)
		navigation.render(NavigationPresentation(navigationSnapshot))
		updateConversationTitle(navigationSnapshot)
		let target = WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		)
		conversation.render(ConversationPresentation(
			snapshot,
			ownerIdentity: target.presentationIdentity,
			transcriptEntries: voiceChat.transcript(
				snapshot.entries,
				store: currentStore,
				threadID: snapshot.selectedThreadID
			),
			voiceChatActive: voiceChat.hasCall
		))
		conversation.updateSendState()
	}

	func handleVoiceChatSend(store: WorkspaceStateStore) -> Bool
	{
		let model = store.model
		let key = model.conversations.selectedConversation
		guard voiceChat.isShowingCall(
			store: store,
			threadID: key.threadID
		)
		else
		{
			return false
		}
		let draft = model.composer.drafts[key] ?? ComposerDraft()
		// Realtime appends accept plain text. The thread's normal submission
		// path preserves structured context and queued-message edit semantics.
		guard draft.context.isEmpty, draft.queuedMessageEdit == nil,
				!model.contextNavigation.projectContext.hasSubmissionContext,
				case .text = SlashCommandParser.parse(draft.text)
		else
		{
			return false
		}
		let context = store.operationContext(threadID: key.threadID)
		voiceChat.submit(draft.text)
		{
			[weak store] in
			guard let store, let currentDraft = store.model.composer.drafts[key],
					currentDraft.revision == draft.revision, currentDraft.lifetime == draft.lifetime
			else
			{
				return
			}
			store.dispatch(.composer(.draftEdited(
				context,
				conversation: key,
				text: "",
				revision: draft.revision + 1
			)))
		}
		return true
	}

	@objc private func startVoiceChat()
	{
		voiceChat.start(store: currentStore)
	}

	@objc private func endVoiceChat()
	{
		voiceChat.stop()
	}

	@objc private func toggleVoiceChatMicrophone()
	{
		voiceChat.toggleMicrophone()
	}

	@objc private func toggleVoiceChatSpeakers()
	{
		voiceChat.toggleSpeakers()
	}
}
