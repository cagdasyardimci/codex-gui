import AppKit

// Composer layout, preferences, draft presentation, and input actions.
@MainActor
extension ConversationViewController
{
	private enum ComposerSizing
	{
		static let minimumHeight = LayoutTokens.composer.minimumHeight
		static let contentHeightAllowance: CGFloat = 0
		static let heightUpdateTolerance: CGFloat = 2
	}

	func makeComposerArea() -> NSStackView
	{
		let composerToolbar = makeComposerToolbar()
		installComposerStack(toolbar: composerToolbar)
		let composerArea = AppKitLayout.verticalStack(
			[turnChangeSummaryButton, composerSurface],
			spacing: LayoutTokens.Composer.summarySpacing
		)
		composerArea.alignment = .centerX
		turnChangeSummaryButton.isHidden = true
		turnChangeSummaryButton.target = self
		turnChangeSummaryButton.action = #selector(showTurnChanges)
		turnChangeSummaryLoader.onChange =
		{
			[weak self] in self?.turnChangeSummaryButton.render($0)
		}
		composerSurface.widthAnchor.constraint(equalTo: composerArea.widthAnchor).isActive = true

		return composerArea
	}

	private func makeComposerToolbar() -> ComposerToolbarView
	{
		let attachmentRow = AppKitLayout.horizontalStack(
			[addContextButton, approvalPolicyButton, planModeLabel],
			spacing: LayoutTokens.Composer.leadingControlSpacing
		)
		let actionRow = AppKitLayout.horizontalStack(
			[sendButton, steerButton, stopButton],
			spacing: LayoutTokens.composer.actionSpacing
		)
		let composerToolbar = ComposerToolbarView(
			leadingControls: attachmentRow,
			preferenceControl: modelEffortButton,
			actionControls: actionRow
		)
		attachmentRow.widthAnchor.constraint(
			lessThanOrEqualTo: composerToolbar.widthAnchor
		).isActive = true
		return composerToolbar
	}

	private func installComposerStack(toolbar composerToolbar: ComposerToolbarView)
	{
		ComposerSurfaceLayout.install(
			in: composerSurface,
			attachments: attachmentDetailsScrollView,
			editor: composerScrollView,
			footer: composerToolbar
		)
	}

	func configurePreferenceControls()
	{
		modelEffortButton.target = self
		modelEffortButton.action = #selector(showModelAndEffort)
		modelEffortButton.setAccessibilityLabel("Choose Codex model and reasoning effort")
		modelEffortButton.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		refreshModelEffortButton()
		modelEffortButton.heightAnchor
			.constraint(equalToConstant: LayoutTokens.composer.controlHeight).isActive = true

		configurePreferenceCallbacks()
		modelEffortController.onPreferredContentSizeChange =
		{
			[weak self] in
			self?.modelEffortPopover?.reposition()
		}
		modelEffortController.onModelListPresentationChange =
		{
			[weak self] in self?.refreshModelEffortButton()
		}

		approvalPolicyButton.target = self
		approvalPolicyButton.action = #selector(showApprovalPolicy)
		AppKitControlStyling.styleButton(
			approvalPolicyButton,
			icon: .handRaised
		)
		approvalPolicyButton.font = AppKitFontResolver.font(TypographyTokens.Composer.preference)
		approvalPolicyButton.lineBreakMode = .byTruncatingTail
		approvalPolicyButton.cornerRadius = ShapeTokens.Composer
			.controlRadius(forControlHeight: LayoutTokens.composer.controlHeight)
		approvalPolicyButton.heightAnchor
			.constraint(equalToConstant: LayoutTokens.composer.controlHeight).isActive = true
		AppKitControlStyling.stylePopup(addContextButton)
		AppKitLayout.compressHorizontally(addContextButton)
		preferenceWarningLabel.font = AppKitFontResolver.font(TypographyTokens.Composer.warning)
		preferenceWarningLabel.textColor = .systemOrange
		preferenceWarningLabel.setAccessibilityLabel("Model preference warning")
		preferenceWarningLabel.isHidden = true
	}

	func configurePreferenceCallbacks()
	{
		modelEffortController.onSelectModel =
		{
			[weak self] in self?.onSelectModel?($0)
		}
		modelEffortController.onSelectEffort =
		{
			[weak self] in self?.onSelectEffort?($0)
		}
		modelEffortController.onSetFastMode =
		{
			[weak self] in self?.onSetFastMode?($0)
		}
		approvalPolicyController.onSelect =
		{
			[weak self] in self?.requestApprovalMode($0)
		}
	}

	func configureComposerControls()
	{
		planModeLabel.font = AppKitFontResolver.font(TypographyTokens.Composer.plan)
		planModeLabel.textColor = .systemBlue
		planModeLabel.setAccessibilityLabel("Plan mode enabled")
		planModeLabel.isHidden = true
		interactionStack.orientation = .vertical
		interactionStack.alignment = .leading
		interactionStack.spacing = LayoutTokens.Composer.interactionSpacing
		interactionStack.isHidden = true

		configureDraftEditor()
		configureContextPreviews()
		configureContextActionButton()
		configureSubmissionButtons()
	}

	private func configureDraftEditor()
	{
		composer.isEditable = true
		composer.isSelectable = true
		composer.isRichText = false
		composer.allowsUndo = true
		composer.isAutomaticQuoteSubstitutionEnabled = false
		composer.isAutomaticDashSubstitutionEnabled = false
		composer.isAutomaticTextReplacementEnabled = false
		composer.font = AppKitFontResolver.font(TypographyTokens.Composer.editor)
		composer.textColor = AppKitColorTokens.primaryText
		composer.insertionPointColor = AppKitColorTokens.primaryText
		// Match the surface so AppKit can repaint the old insertion point after editing.
		composer.backgroundColor = AppKitColorTokens.composer
		composer.drawsBackground = true
		composer.textContainerInset = .zero
		composer.isHorizontallyResizable = false
		composer.isVerticallyResizable = true
		composer.autoresizingMask = [.width]
		composer.textContainer?.widthTracksTextView = true
		composer.textContainer?.lineFragmentPadding = 0
		composer.layoutManager?.delegate = composer
		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = TypographyTokens.Composer.editor.lineHeight ?? 0
		paragraph.maximumLineHeight = TypographyTokens.Composer.editor.lineHeight ?? 0
		composer.defaultParagraphStyle = paragraph
		composer.typingAttributes = AppKitFontResolver
			.textAttributes(TypographyTokens.Composer.editor)
			.merging(
				[
					.font: AppKitFontResolver.font(TypographyTokens.Composer.editor),
					.foregroundColor: AppKitColorTokens.primaryText,
					.paragraphStyle: paragraph,
				],
				uniquingKeysWith:
				{
					_, replacement in replacement
				}
			)
		composer.delegate = self
		composer.setAccessibilityLabel("Message to Codex")
		composer.setAccessibilityIdentifier("conversation-composer")
		composer.registerForDraggedTypes([.fileURL, .tiff, .png])
		composerScrollView.documentView = composer
		composerScrollView.hasVerticalScroller = true
		composerScrollView.autohidesScrollers = true
		composerScrollView.drawsBackground = false
		composerScrollView.borderType = .noBorder
		composerHeightConstraint = composerScrollView.heightAnchor
			.constraint(equalToConstant: ComposerSizing.minimumHeight)
		composerHeightConstraint?.priority = .defaultHigh
		composerHeightConstraint?.isActive = true
		composerScrollView.heightAnchor
			.constraint(greaterThanOrEqualToConstant: ComposerSizing.minimumHeight).isActive = true
		composer.onImage =
		{
			[weak self] image, title in self?.attachImage(
				image,
				title: title
			)
		}
		composer.onImageSource =
		{
			[weak self] source, title in self?.attachImage(
				source,
				title: title
			)
		}
	}

	private func configureContextPreviews()
	{
		contextView.onRemove =
		{
			[weak self] id in self?.onRemoveContext?(id)
		}
		attachmentDetailsScrollView.drawsBackground = false
		attachmentDetailsScrollView.borderType = .noBorder
		requestDetailsScrollView.drawsBackground = false
		requestDetailsScrollView.borderType = .noBorder
	}

	private func configureContextActionButton()
	{
		addContextButton.pullsDown = true
		addContextButton.addItems(withTitles: [
			"Add Context…",
			"Search Project Files…",
			"Attach Image…",
			"Select Code…",
			"Insert File Path…",
			"Inspect Request Context…",
		])
		addContextButton.menu?.autoenablesItems = false
		addContextButton.menu?.font = AppKitFontResolver.font(TypographyTokens.Composer.contextMenu)
		addContextButton.target = self
		addContextButton.action = #selector(chooseContextAction)
		addContextButton.setAccessibilityLabel("Add attachments or inspect request context")
		addContextButton.item(at: 0)?.image = ComposerFooterIcons.add
		(addContextButton.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
		addContextButton.contentTintColor = AppKitColorTokens.primaryText
		addContextButton.imagePosition = .imageOnly
		addContextButton.widthAnchor
			.constraint(equalToConstant: LayoutTokens.composer.controlHeight).isActive = true
		addContextButton.heightAnchor
			.constraint(equalToConstant: LayoutTokens.composer.controlHeight).isActive = true
		addContextButton.toolTip = "Add Context…"
	}

	private func configureSubmissionButtons()
	{
		sendButton.target = self
		sendButton.action = #selector(send)
		sendButton.keyEquivalent = "\r"
		sendButton.keyEquivalentModifierMask = [.command]
		sendButton.setAccessibilityLabel("Send message")
		sendButton.setAccessibilityIdentifier("conversation-send")
		steerButton.target = self
		steerButton.action = #selector(steer)
		steerButton.keyEquivalent = "\r"
		steerButton.keyEquivalentModifierMask = [.command, .shift]
		steerButton.setAccessibilityLabel("Steer the active turn with this message")
		stopButton.target = self
		stopButton.action = #selector(stop)
		stopButton.setAccessibilityLabel("Stop current task")
		stopButton.setAccessibilityIdentifier("conversation-stop")
		for button in [sendButton, steerButton, stopButton]
		{
			let symbol: DesktopIcon = button === stopButton
				? .stopCircleFilled : (button === sendButton ? .arrowUpLg : .arrowUp)
			AppKitControlStyling.styleButton(
				button,
				icon: symbol,
				prominent: true
			)
			button.image = DesktopIcons.image(
				symbol,
				size: button === sendButton ? LayoutTokens.Composer.sendIconSize : LayoutTokens
					.composer.controlHeight
			)
			button.imagePosition = .imageOnly
			button.widthAnchor.constraint(equalToConstant: LayoutTokens.composer.controlHeight)
				.isActive = true
			button.heightAnchor.constraint(equalToConstant: LayoutTokens.composer.controlHeight)
				.isActive = true
		}
		sendButton.wantsLayer = true
		sendButton.layer?.cornerRadius = ShapeTokens.Composer
			.controlRadius(forControlHeight: LayoutTokens.composer.controlHeight)
		sendButton.contentTintColor = .white
		sendButton.toolTip = "Send message (⌘Return)"
		steerButton.toolTip = "Steer the active turn (⇧⌘Return)"
	}

	func renderModelAndApprovalPreferences(_ snapshot: ConversationPresentation.Preferences)
	{
		let requestedModel = snapshot.models.first
		{
			$0.id == snapshot.selectedModelID
		}
		let defaultModel = snapshot.selectedModelID == nil
			? snapshot.models.first(where: \.isDefault) : nil
		let selectedModel = requestedModel ?? defaultModel
		let effortTitle = ModelPreferencePresentation.effortTitle(
			snapshot.selectedEffort ?? selectedModel?.defaultReasoningEffort
		)
		latestModelEffortSummary = selectedModel.map
		{
			"\($0.displayName) \(effortTitle)"
		}
		latestModelEffortTitle = effortTitle
		latestFastMode = snapshot.fastMode
		refreshModelEffortButton()
		modelEffortController.render(
			models: snapshot.models,
			selectedModelID: snapshot.selectedModelID,
			selectedEffort: snapshot.selectedEffort,
			fastMode: snapshot.fastMode
		)

		approvalMode = snapshot.approvalMode
		approvalPolicyController.render(mode: approvalMode)
		approvalPolicyButton.title = approvalMode.title
		approvalPolicyButton.toolTip = "\(approvalMode.title): \(approvalMode.description)"
		approvalPolicyButton.setAccessibilityLabel("Approval policy: \(approvalMode.title)")
		let approvalTint: NSColor = approvalMode == .fullAccess
			? ApprovalPopoverStyle.fullAccess : AppKitColorTokens.secondaryText
		approvalPolicyButton.contentTintColor = approvalTint
		approvalPolicyButton.attributedTitle = NSAttributedString(
			string: approvalMode.title,
			attributes: [
				.font: AppKitFontResolver.font(TypographyTokens.Composer.preference),
				.foregroundColor: approvalTint,
			]
		)
		let approvalSymbol: DesktopIcon
		switch approvalMode
		{
		case .askForApproval: approvalSymbol = .handRaised
		case .approveForMe: approvalSymbol = .shieldCheck
		case .fullAccess: approvalSymbol = .warning
		}
		if approvalMode == .fullAccess
		{
			approvalPolicyButton.image = ComposerFooterIcons.fullAccess
		}
		else
		{
			approvalPolicyButton.image = DesktopIcons.image(
				approvalSymbol,
				size: LayoutTokens.permission.iconSize
			)
		}
	}

	func renderComposer(_ snapshot: ConversationPresentation.Composer)
	{
		composerSubmissionPresentation = snapshot
		turnChangeSummaryLoader.render(
			request: snapshot.turnChangeRequest,
			activeTurnID: snapshot.activeTurnID
		)
		planModeLabel.stringValue = snapshot.planModeStatus ?? "Plan mode"
		planModeLabel.isHidden = !snapshot.planMode && snapshot.planModeStatus == nil
		planModeLabel.textColor = snapshot.planModeStatus == nil ? .systemBlue : .systemOrange
		planModeLabel.setAccessibilityLabel(planModeLabel.stringValue)
		planModeLabel.toolTip = snapshot.planModeStatus == nil ? "Plan mode enabled"
			: "Run /plan to choose Reapply Plan or Reset Default after reconnecting."
		slashCommandController.availableSkills = snapshot.availableSkills
		slashCommandController.unavailableReason =
		{
			snapshot.slashCommandUnavailableReasons[$0]
		}
		if slashCompletionRange != nil,
			let query = SlashCommandParser.completionQuery(
			in: composer.string,
			selectedRange: composer.selectedRange()
			)
		{
			slashCommandController.render(prefix: query.prefix)
		}
		if composer.string != snapshot.draft
		{
			dismissSlashCommands()
			if fileSelectionReceiver != nil || fileSearchWasCompletion
			{
				fileSearchPopover?.close()
				fileSelectionReceiver = nil
				completionRange = nil
			}
			modelEffortPopover?.close()
			approvalPolicyPopover?.close()
			configurePreferenceCallbacks()
			composer.string = snapshot.draft
			updateComposerHeight()
		}
		contextView.render(items: snapshot.draftContext)
		attachmentDetailsScrollView.updateContentHeight()

		composer.acceptsImageAttachments = snapshot.projectPath != nil
		for index in 1 ... 4
		{
			addContextButton.item(at: index)?.isEnabled = snapshot.projectPath != nil
		}
		updateSendState()
	}

	@objc private func showTurnChanges()
	{
		onViewChanges?()
	}

	func updateSendState()
	{
		guard let snapshot = composerSubmissionPresentation
		else
		{
			sendButton.isEnabled = false
			sendButton.layerBackgroundColor = .tertiaryLabelColor
			steerButton.isEnabled = false
			return
		}
		let isSlashInput: Bool
		switch SlashCommandParser.parse(snapshot.draft)
		{
		case .text: isSlashInput = false
		case .command, .error: isSlashInput = true
		}
		let isViewingActiveTask =
			snapshot.activeThreadID != nil && snapshot.activeThreadID == snapshot.selectedThreadID

		let hasMessageContent =
			!snapshot.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
				|| !snapshot.draftContext.isEmpty
		let canSubmitMessage = snapshot.canSend || isSlashInput
		let canSteerMessage = snapshot.canSteer || isSlashInput

		let preparationComplete = attachmentsAreReady
		sendButton.isEnabled = canSubmitMessage && hasMessageContent && preparationComplete
		steerButton.isHidden = !isViewingActiveTask || snapshot.activeExecutionState != .running
		sendButton.isHidden = !steerButton.isHidden
		steerButton.isEnabled = canSteerMessage && hasMessageContent && preparationComplete
		let preparationMessage = codeSelectionTask == nil
			? "Preparing image attachment…" : "Loading code selection…"
		sendButton.toolTip = preparationComplete
			? "Send message (⌘Return)" : preparationMessage
		steerButton.toolTip = preparationComplete
			? "Steer the active turn (⇧⌘Return)" : preparationMessage
		sendButton.contentTintColor = .white
		sendButton.layerBackgroundColor = sendButton.isEnabled
			? AppKitColorTokens.composerSend : NSColor.tertiaryLabelColor
		steerButton.contentTintColor = steerButton.isEnabled ? .systemBlue : .tertiaryLabelColor
		let hasStoppableExecution =
			snapshot.activeExecutionState == .running
				|| snapshot.activeExecutionState == .awaitingApproval
				|| snapshot.activeExecutionState == .awaitingAnswer
		stopButton.isEnabled = isViewingActiveTask && hasStoppableExecution
		stopButton.isHidden = !stopButton.isEnabled
	}

	func textDidChange(_ notification: Notification)
	{
		guard notification.object as? NSTextView === composer
		else
		{
			return
		}
		onDraftChange?(composer.string)
		updateComposerHeight()
		updateComposerCompletion()
	}

	func updateComposerHeight()
	{
		guard let textContainer = composer.textContainer,
				let layoutManager = composer.layoutManager
		else
		{
			return
		}
		textContainer.widthTracksTextView = true
		layoutManager.ensureLayout(for: textContainer)
		let contentHeight =
			layoutManager.usedRect(for: textContainer).height
				+ composer.textContainerInset.height * 2 + ComposerSizing.contentHeightAllowance
		let desiredHeight = ComposerLayout().desiredEditorHeight(
			contentHeight: contentHeight,
			viewportHeight: view.window?.contentView?.bounds.height ?? view.bounds.height
		)

		if abs((composerHeightConstraint?.constant ?? 0) - desiredHeight)
			> ComposerSizing.heightUpdateTolerance
		{
			composerHeightConstraint?.constant = desiredHeight
		}
	}

	func insertPath(_ path: String)
	{
		let insertion = path.contains(" ") ? "\"\(path)\"" : path
		composer.insertText(
			insertion,
			replacementRange: composer.selectedRange()
		)
		onDraftChange?(composer.string)
		view.window?.makeFirstResponder(composer)
	}

	@objc private func send()
	{
		guard attachmentsAreReady
		else
		{
			return
		}
		onSend?()
	}
	@objc private func steer()
	{
		guard attachmentsAreReady
		else
		{
			return
		}
		onSteer?(composer.string)
	}
	@objc private func stop()
	{
		onStop?()
	}

	@objc func choosePath()
	{
		onInsertPath?()
	}

	private func refreshModelEffortButton()
	{
		modelEffortButton.update(
			summary: latestModelEffortSummary,
			effortTitle: latestModelEffortTitle,
			fastMode: latestFastMode,
			isPickerPresented: modelEffortPopover?.isShown == true,
			isModelListPresented: modelEffortController.isShowingModelList
		)
	}

	@objc func showModelAndEffort()
	{
		configurePreferenceCallbacks()
		approvalPolicyPopover?.close()
		if modelEffortPopover?.isShown == true
		{
			modelEffortPopover?.close()
			return
		}
		if modelEffortPopover == nil
		{
			let popover = ComposerPopoverPanel(
				contentViewController: modelEffortController,
				shadowOutset: LayoutTokens.ModelPopover.shadowOutset
			)
			popover.anchorSpacing = LayoutTokens.ModelPopover.anchorSpacing
			popover.limitsHeightToSpaceAboveAnchor = true
			popover.focusAfterDismissal = composer
			popover.onPresentationChange =
			{
				[weak self] presented in
				self?.modelEffortController.setPresented(presented)
				if !presented
				{
					self?.configurePreferenceCallbacks()
				}
				self?.refreshModelEffortButton()
			}
			modelEffortPopover = popover
		}
		modelEffortPopover?.show(
			relativeTo: modelEffortButton.bounds,
			of: modelEffortButton
		)
	}

	@objc func showApprovalPolicy()
	{
		configurePreferenceCallbacks()
		modelEffortPopover?.close()
		if approvalPolicyPopover?.isShown == true
		{
			approvalPolicyPopover?.close()
			return
		}
		if approvalPolicyPopover == nil
		{
			let popover = ComposerPopoverPanel(
				contentViewController: approvalPolicyController,
				hasShadow: true
			)
			popover.alignsToAnchorLeadingEdge = true
			popover.horizontalOffset = LayoutTokens.ApprovalPopover.anchorHorizontalOffset
			popover.anchorSpacing = LayoutTokens.ApprovalPopover.anchorSpacing
			popover.onPresentationChange =
			{
				[weak self] shown in
				if shown
				{
					self?.approvalPolicyController.focusSelectedRow()
				}
			}
			approvalPolicyPopover = popover
		}
		approvalPolicyController.clearHover()
		approvalPolicyPopover?.show(
			relativeTo: approvalPolicyButton.bounds,
			of: approvalPolicyButton
		)
	}

	func requestApprovalMode(
		_ mode: ApprovalMode,
		completion: ((ApprovalMode) -> Void)? = nil
	)
	{
		approvalPolicyPopover?.close()
		guard fullAccessConfirmationPanel == nil
		else
		{
			return
		}
		guard mode == .fullAccess, approvalMode != .fullAccess
		else
		{
			(completion ?? onSelectApprovalMode)?(mode)
			return
		}
		guard let window = view.window, window.attachedSheet == nil
		else
		{
			return
		}

		// Capture the requesting workspace's callback before a later render can replace it.
		let applyMode = completion ?? onSelectApprovalMode
		let confirmation = FullAccessConfirmationView()
		let panel = FullAccessConfirmationPanel(
			contentRect: .zero,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		panel.isReleasedWhenClosed = false
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		panel.contentViewController = confirmation
		confirmation.view.layoutSubtreeIfNeeded()
		panel.setContentSize(confirmation.view.fittingSize)
		confirmation.onDecision =
		{
			[weak window, weak panel] confirmed in
			guard let window, let panel
			else
			{
				return
			}
			window.endSheet(
				panel,
				returnCode: confirmed ? .OK : .cancel
			)
		}
		fullAccessConfirmationPanel = panel
		window.beginSheet(panel)
		{
			[weak self, weak panel] response in
			self?.fullAccessConfirmationPanel = nil
			if response == .OK
			{
				applyMode?(.fullAccess)
			}
			panel?.finishDismissal()
		}
	}

}
