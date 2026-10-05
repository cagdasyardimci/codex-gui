import AppKit

extension MainWindowController
{
	func renderPinnedSummary(
		_ snapshot: ConversationSnapshot,
		target: WorkspaceIntentTarget
	)
	{
		let owner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: target.presentationIdentity
		)
		let firstPresentation = summaryReconciliation.owner == nil
		let sources = ConversationLocalSources(entries: snapshot.entries)
		let subagents = ConversationSubagents(entries: snapshot.entries)
		if let existing = inspector.conversationSubagents, existing.owner == owner
		{
			existing.update(subagents)
		}
		else
		{
			inspector.conversationSubagents = SubagentsViewController(
				owner: owner,
				subagents: subagents
			)
		}
		let sourcesController: ConversationSourcesViewController
		if let existing = inspector.conversationSources, existing.owner == owner
		{
			sourcesController = existing
			existing.update(sources)
		}
		else
		{
			inspector.conversationSources?.invalidate()
			sourcesController = ConversationSourcesViewController(
				owner: owner,
				sources: sources
			)
			inspector.conversationSources = sourcesController
		}
		sourcesController.onOpen =
		{
			[weak self] record in
			guard let self, target.accepts(.loadEarlierTurns), !target.store.isRetired,
					self.summaryReconciliation.owner == owner,
					sources.records.contains(record), let url = record.url
			else
			{
				return false
			}
			if url.isFileURL, !FileManager.default.isReadableFile(atPath: url.path)
			{
				return false
			}
			guard url.isFileURL || (record.kind == .page && url.scheme == "https")
			else
			{
				return false
			}
			return NSWorkspace.shared.open(url)
		}
		inspector.panels.register(
			sourcesController,
			for: .sources,
			onRequest:
			{
				request in
				guard target.accepts(.loadEarlierTurns), !target.store.isRetired,
						request.owner == owner
				else
				{
					return
				}
				sourcesController.select(request)
			}
		)
		summaryReconciliation.select(owner)
		let visibilityOwner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: String(describing: ObjectIdentifier(target.store))
		)
		let visible = summaryVisibility.isVisible(for: visibilityOwner)
		if visible, snapshot.projectPath != nil, target.accepts(.loadEarlierTurns),
			!currentStore.isRetired, !currentStore.model.lifecycle.isShutdown
		{
			summaryGitLoader.loadIfNeeded(for: owner)
		}
		if target.accepts(.loadEarlierTurns)
		{
			var sections = ContextSummarySections()
			sections.changes = summaryChangesProvider?(owner)
				?? .unavailable("Open Changes to load a repository comparison")
			sections.sources = .available(sources.records.map(\.summary))
			sections.availableDestinations = [.changes, .sources]
			if !subagents.agents.isEmpty
			{
				sections.agents = .available(subagents.summary(
					parentThreadID: snapshot.selectedThreadID ?? ""
				))
				sections.availableDestinations.insert(.subagents)
			}
			summaryReconciliation.accept(ContextSummaryUpdate(
				owner: owner,
				revision: summaryReconciliation.revision + 1,
				sections: sections
			))
		}
		var sections = summaryReconciliation.sections
		sections.changesContext = gitSummary.scopeDescription
		if currentStore.isRetired || currentStore.model.lifecycle.isShutdown
		{
			sections = ContextSummarySections()
			sections.changes = .unavailable("Workspace unavailable")
			sections.sources = .unavailable("Workspace unavailable")
			sections.availableDestinations = []
		}
		inspector.onSummaryDisplayChange =
		{
			[weak self] displayed in
			self?.summaryToggleButton.state = displayed ? .on : .off
			self?.inspector.toolsTabs.setSummaryVisible(displayed)
			self?.summaryToggleButton.setAccessibilityValue(displayed ? "Visible" : "Hidden")
		}
		inspector.renderSummary(
			PinnedSummaryPresentation(
				snapshot,
				ownerIdentity: target.presentationIdentity,
				sections: sections,
				agentPreviews: subagents.agents
			),
			visible: visible
		)
		if inspector.isShowingDetails, inspector.panels.destination == .sources,
			target.accepts(.loadEarlierTurns), !target.store.isRetired
		{
			inspector.open(ContextPanelRequest(
				owner: owner,
				destination: .sources
			))
		}
		if firstPresentation, visible, snapshot.projectPath != nil
		{
			paneController.setReviewCollapsed(false)
		}
		configureSubagentConversationNavigation(
			owner: owner,
			target: target
		)
		conversation.onOpenSubagents =
		{
			[weak self] in
			guard let self, target.accepts(.loadEarlierTurns), !target.store.isRetired,
					self.summaryReconciliation.owner == owner
			else
			{
				return
			}
			self.openSubagentsToolTab(ContextPanelRequest(
				owner: owner,
				destination: .subagents
			))
		}
		inspector.summary.onNavigate =
		{
			[weak self] request in
			guard let self, request.owner == owner, target.accepts(.loadEarlierTurns),
					!target.store.isRetired, self.summaryReconciliation.owner == owner
			else
			{
				return
			}
			switch request.destination
			{
			case .changes:
				self.openGitChanges(
					request,
					inToolTab: true
				)
			case .subagents:
				self.openSubagentsToolTab(request)
			case .sources:
				guard request.recordID == nil || sources.record(
					for: request,
					owner: owner
				) != nil
				else
				{
					return
				}
				self.openSourcesToolTab(request)
			default: break
			}
		}
	}

	private func openSourcesToolTab(_ request: ContextPanelRequest)
	{
		openContextToolTab
		{
			inspector.openSourcesInToolTab(request)
		}
	}

	func openSubagentsToolTab(_ request: ContextPanelRequest)
	{
		openContextToolTab
		{
			inspector.openSubagentsInToolTab(request)
		}
	}

	private func openContextToolTab(_ open: () -> Bool)
	{
		configureToolsPaneClosing()
		if !inspector.isShowingTools || paneController.isReviewCollapsed
		{
			paneController.openToolsPane
			{
				_ = open()
			}
		}
		else
		{
			_ = open()
		}
		updateToolsToolbarControls()
	}

	/// Future Git integration projects its canonical comparison for the captured owner.
	/// It must reject stale owner/revision/scope before returning totals; nil unregisters it.
	func registerSummaryChangesProvider(
		_ provider: ((FeaturePresentationOwner) -> SummarySection<SummaryChangeTotals>)?
	)
	{
		summaryChangesProvider = provider
		guard let snapshot = latestSnapshot
		else
		{
			return
		}
		let target = WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		)
		renderPinnedSummary(
			snapshot,
			target: target
		)
	}

	@objc func togglePinnedSummary()
	{
		guard let snapshot = latestSnapshot
		else
		{
			return
		}
		let owner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: String(describing: ObjectIdentifier(currentStore))
		)
		let visible = summaryVisibility.isVisible(for: owner)
		let expandedConversation = paneController.isShowingExpandedConversation
		let hiddenByContainer = (inspector.isShowingTools && !inspector
			.isSummaryBesideExpandedConversation) || inspector.isShowingDetails
			|| paneController.split.splitViewItems[2].isCollapsed
		if !visible || !hiddenByContainer
		{
			summaryVisibility.toggle(for: owner)
		}
		let target = WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		)
		let revealing = !visible || hiddenByContainer
		if revealing, summaryVisibility.isVisible(for: owner),
			snapshot.projectPath != nil, target.accepts(.loadEarlierTurns)
		{
			summaryGitLoader.refresh(for: FeaturePresentationOwner(
				snapshot,
				storeIdentity: target.presentationIdentity
			))
		}
		inspector.animateSummaryVisibilityChange
		{
			if expandedConversation
			{
				inspector.showSummaryBesideExpandedConversation()
			}
			else
			{
				inspector.showSummary()
			}
			renderPinnedSummary(
				snapshot,
				target: target
			)
			// The inspector opens to make the explicit reveal observable at supported widths.
			if !expandedConversation, summaryVisibility.isVisible(for: owner)
			{
				paneController.setReviewCollapsed(false)
			}
		}
	}

	func openCurrentChanges(toggleIfShowing: Bool = false)
	{
		guard let snapshot = latestSnapshot
		else
		{
			return
		}
		let target = WorkspaceIntentTarget(
			store: currentStore,
			snapshot: snapshot,
			coordinator: coordinator
		)
		guard snapshot.projectPath != nil, target.accepts(.loadEarlierTurns)
		else
		{
			return
		}
		let request = ContextPanelRequest(
			owner: FeaturePresentationOwner(
				snapshot,
				storeIdentity: target.presentationIdentity
			),
			destination: .changes
		)
		if toggleIfShowing, inspector.panels.destination == .changes,
			!inspector.panels.view.isHidden, paneController.isGitReviewFocused
		{
			inspector.showSummary()
		}
		else if toggleIfShowing, inspector.panels.destination == .changes,
				!inspector.panels.view.isHidden, !paneController.isReviewCollapsed
		{
			paneController.toggleReview()
			if paneController.isReviewCollapsed
			{
				inspector.gitChanges.close()
			}
		}
		else
		{
			openGitChanges(request)
		}
	}
}
