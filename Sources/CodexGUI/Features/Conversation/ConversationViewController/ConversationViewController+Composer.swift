import AppKit

// Composer layout, preferences, draft presentation, and input actions.
@MainActor
extension ConversationViewController
{
	func makeComposerArea() -> NSStackView
	{
		let attachmentRow = AppKitLayout.horizontalStack(
			[addContextButton, approvalPolicyButton],
			spacing: 16
		)
		let actionRow = AppKitLayout.horizontalStack(
			[sendButton, steerButton, stopButton],
			spacing: 8
		)
		let composerToolbar = ComposerToolbarView(
			leadingControls: attachmentRow,
			preferenceControl: modelEffortButton,
			actionControls: actionRow
		)
		attachmentRow.widthAnchor.constraint(
			lessThanOrEqualTo: composerToolbar.widthAnchor
		).isActive = true
		let composerSurface = DesktopSurface(
			DesktopTheme.canvas,
			cornerRadius: 16,
			bordered: true
		)
		let composerStack = AppKitLayout.verticalStack(
			[attachmentDetailsScrollView, composerScrollView, composerToolbar],
			spacing: 6
		)
		composerStack.alignment = .leading
		AppKitLayout.pin(
			composerStack,
			to: composerSurface,
			inset: 8
		)
		for row in [attachmentDetailsScrollView, composerScrollView, composerToolbar]
		{
			row.widthAnchor.constraint(equalTo: composerStack.widthAnchor).isActive = true
		}

		let projectIcon = NSImageView()
		projectIcon.image = NSImage(
			systemSymbolName: "folder",
			accessibilityDescription: nil
		)
		projectIcon.contentTintColor = .secondaryLabelColor
		projectIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
		projectIcon.heightAnchor.constraint(equalToConstant: 14).isActive = true
		for label in [projectLocationLabel, projectBranchLabel]
		{
			label.font = .systemFont(ofSize: 12)
			label.textColor = .secondaryLabelColor
			label.lineBreakMode = .byTruncatingMiddle
			label.setContentCompressionResistancePriority(
				.defaultLow,
				for: .horizontal
			)
		}
		projectLocationLabel.setAccessibilityLabel("Project and local checkout")
		projectBranchLabel.setAccessibilityLabel("Selected task checkout branch")
		let contextStrip = AppKitLayout.horizontalStack(
			[projectIcon, projectLocationLabel, flexibleSpace(), projectBranchLabel],
			spacing: 8
		)
		contextStrip.heightAnchor.constraint(equalToConstant: 28).isActive = true
		contextStrip.isHidden = true
		projectContextStrip = contextStrip
		let composerArea = AppKitLayout.verticalStack(
			[contextStrip, composerSurface],
			spacing: 4
		)
		composerArea.alignment = .centerX
		composerSurface.widthAnchor.constraint(equalTo: composerArea.widthAnchor).isActive = true
		contextStrip.widthAnchor.constraint(
			equalTo: composerArea.widthAnchor,
			constant: -24
		).isActive = true

		return composerArea
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
		modelEffortButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

		modelEffortController.onSelectModel =
		{
			[weak self] modelID in
			self?.onSelectModel?(modelID)
		}
		modelEffortController.onSelectEffort =
		{
			[weak self] effort in
			self?.onSelectEffort?(effort)
		}
		modelEffortController.onSetFastMode =
		{
			[weak self] enabled in
			self?.onSetFastMode?(enabled)
		}
		modelEffortController.onPreferredContentSizeChange =
		{
			[weak self] in
			self?.modelEffortPopover?.reposition()
		}

		approvalPolicyButton.target = self
		approvalPolicyButton.action = #selector(showApprovalPolicy)
		DesktopTheme.styleButton(
			approvalPolicyButton,
			symbol: "hand.raised"
		)
		approvalPolicyButton.font = .systemFont(ofSize: 13)
		approvalPolicyButton.lineBreakMode = .byTruncatingTail
		approvalPolicyButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
		approvalPolicyController.onSelect =
		{
			[weak self] mode in
			self?.requestApprovalMode(mode)
		}
		for popup in [jumpButton, addContextButton]
		{
			DesktopTheme.stylePopup(popup)
			AppKitLayout.compressHorizontally(popup)
		}
		preferenceWarningLabel.font = .systemFont(ofSize: 12)
		preferenceWarningLabel.textColor = .systemOrange
		preferenceWarningLabel.setAccessibilityLabel("Model preference warning")
		preferenceWarningLabel.isHidden = true
	}

	func configureComposerControls()
	{
		interactionStack.orientation = .vertical
		interactionStack.alignment = .leading
		interactionStack.spacing = 8

		composer.isEditable = true
		composer.isSelectable = true
		composer.isRichText = false
		composer.allowsUndo = true
		composer.isAutomaticQuoteSubstitutionEnabled = false
		composer.isAutomaticDashSubstitutionEnabled = false
		composer.isAutomaticTextReplacementEnabled = false
		composer.font = .systemFont(ofSize: 15)
		composer.textColor = .labelColor
		composer.drawsBackground = false
		composer.textContainerInset = NSSize(
			width: 4,
			height: 8
		)
		composer.isHorizontallyResizable = false
		composer.isVerticallyResizable = true
		composer.autoresizingMask = [.width]
		composer.textContainer?.widthTracksTextView = true
		composer.delegate = self
		composer.setAccessibilityLabel("Message to Codex")
		composer.registerForDraggedTypes([.fileURL, .tiff, .png])
		composerScrollView.documentView = composer
		composerScrollView.hasVerticalScroller = true
		composerScrollView.autohidesScrollers = true
		composerScrollView.drawsBackground = false
		composerScrollView.borderType = .noBorder
		composerHeightConstraint = composerScrollView.heightAnchor.constraint(equalToConstant: 46)
		composerHeightConstraint?.priority = .defaultHigh
		composerHeightConstraint?.isActive = true
		composerScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
		composer.onImage =
		{
			[weak self] image, title in self?.attachImage(
				image,
				title: title
			)
		}
		contextView.onRemove =
		{
			[weak self] id in self?.onRemoveContext?(id)
		}
		contextView.onReuse =
		{
			[weak self] id in self?.onReuseContext?(id)
		}
		attachmentDetailsScrollView.drawsBackground = false
		attachmentDetailsScrollView.borderType = .noBorder
		requestDetailsScrollView.drawsBackground = false
		requestDetailsScrollView.borderType = .noBorder

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
		addContextButton.target = self
		addContextButton.action = #selector(chooseContextAction)
		addContextButton.setAccessibilityLabel("Add attachments or inspect request context")
		addContextButton.item(at: 0)?.image = NSImage(
			systemSymbolName: "plus",
			accessibilityDescription: nil
		)?
			.withSymbolConfiguration(NSImage.SymbolConfiguration(
				pointSize: 15,
				weight: .regular
			))
		(addContextButton.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
		addContextButton.contentTintColor = .labelColor
		addContextButton.imagePosition = .imageOnly
		addContextButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
		addContextButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
		addContextButton.toolTip = "Add Context…"
		sendButton.target = self
		sendButton.action = #selector(send)
		sendButton.keyEquivalent = "\r"
		sendButton.keyEquivalentModifierMask = [.command]
		sendButton.setAccessibilityLabel("Send message")
		steerButton.target = self
		steerButton.action = #selector(steer)
		steerButton.keyEquivalent = "\r"
		steerButton.keyEquivalentModifierMask = [.command, .shift]
		steerButton.setAccessibilityLabel("Steer the active turn with this message")
		stopButton.target = self
		stopButton.action = #selector(stop)
		stopButton.setAccessibilityLabel("Stop current task")
		for button in [sendButton, steerButton, stopButton]
		{
			let symbol = button === stopButton ? "stop.circle.fill" : "arrow.up.circle.fill"
			DesktopTheme.styleButton(
				button,
				symbol: symbol,
				prominent: true
			)
			button.image = button.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(
				pointSize: 28,
				weight: .regular
			))
			button.imagePosition = .imageOnly
			button.widthAnchor.constraint(equalToConstant: 28).isActive = true
			button.heightAnchor.constraint(equalToConstant: 28).isActive = true
		}
		sendButton.toolTip = "Send message (⌘Return)"
		steerButton.toolTip = "Steer the active turn (⇧⌘Return)"
	}

	func renderModelAndApprovalPreferences(_ snapshot: ConversationPresentation.Preferences)
	{
		let selectedModel =
			snapshot.models.first(where:
				{
					$0.id == snapshot.selectedModelID
				})
			??
			(snapshot.selectedModelID == nil ? snapshot.models
				.first(where: \.isDefault) : nil)
		let effortTitle = ModelEffortPopoverView.effortTitle(
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
			? ApprovalPopoverStyle.fullAccess : .secondaryLabelColor
		approvalPolicyButton.contentTintColor = approvalTint
		approvalPolicyButton.attributedTitle = NSAttributedString(
			string: approvalMode.title,
			attributes: [
				.font: NSFont.systemFont(ofSize: 13),
				.foregroundColor: approvalTint,
			]
		)
		let approvalSymbol: String
		switch approvalMode
		{
		case .askForApproval: approvalSymbol = "hand.raised"
		case .approveForMe: approvalSymbol = "checkmark.shield"
		case .fullAccess: approvalSymbol = "exclamationmark.shield"
		}
		approvalPolicyButton.image = NSImage(
			systemSymbolName: approvalSymbol,
			accessibilityDescription: nil
		)?
			.withSymbolConfiguration(NSImage.SymbolConfiguration(
				pointSize: 13,
				weight: .regular
			))
	}

	func renderComposer(_ snapshot: ConversationPresentation.Composer)
	{
		let viewingActiveTask =
			snapshot.activeThreadID != nil && snapshot.activeThreadID == snapshot.selectedThreadID

		if composer.string != snapshot.draft
		{
			composer.string = snapshot.draft
			updateComposerHeight()
		}
		contextView.render(
			items: snapshot.draftContext,
			reusable: snapshot.reusableReferences
		)
		attachmentDetailsScrollView.updateContentHeight()

		composer.acceptsImageAttachments = snapshot.projectPath != nil
		for index in 1 ... 4
		{
			addContextButton.item(at: index)?.isEnabled = snapshot.projectPath != nil
		}

		sendButton.isEnabled =
			snapshot.canSend
				&& (!snapshot.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
					|| !snapshot.draftContext.isEmpty)
		steerButton.isHidden = !viewingActiveTask || snapshot.activeExecutionState != .running
		sendButton.isHidden = !steerButton.isHidden
		steerButton.isEnabled =
			snapshot.canSteer
				&& (!snapshot.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
					|| !snapshot.draftContext.isEmpty)
		sendButton.contentTintColor = sendButton.isEnabled ? .systemBlue : .tertiaryLabelColor
		steerButton.contentTintColor = steerButton.isEnabled ? .systemBlue : .tertiaryLabelColor
		stopButton.isEnabled =
			viewingActiveTask
				&& (snapshot.activeExecutionState == .running
					|| snapshot.activeExecutionState == .awaitingApproval
					|| snapshot.activeExecutionState == .awaitingAnswer)
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
		showAtFileCompletionIfNeeded()
	}

	func renderProjectLocation(_ snapshot: ConversationPresentation.Location)
	{
		guard let path = snapshot.projectPath
		else
		{
			projectContextStrip?.isHidden = true
			return
		}
		let projectName = URL(fileURLWithPath: path).lastPathComponent
		projectLocationLabel.stringValue = "\(projectName) · Local"
		projectLocationLabel.toolTip = path
		projectBranchLabel.stringValue = snapshot.selectedBranch ?? ""
		projectBranchLabel.toolTip = snapshot.selectedCheckoutPath
		projectBranchLabel.isHidden = projectBranchLabel.stringValue.isEmpty
		projectContextStrip?.isHidden = false
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
				+ composer.textContainerInset.height * 2 + 12
		let availableHeight = max(
			46,
			view.bounds.height * 0.25
		)
		let height = min(
			160,
			min(
				availableHeight,
				max(
					46,
					contentHeight
				)
			)
		)
		if abs((composerHeightConstraint?.constant ?? 0) - height) > 2
		{
			composerHeightConstraint?.constant = height
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
		onSend?()
	}
	@objc private func steer()
	{
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
			isPickerPresented: modelEffortPopover?.isShown == true
		)
	}

	@objc private func showModelAndEffort()
	{
		approvalPolicyPopover?.close()
		if modelEffortPopover?.isShown == true
		{
			modelEffortPopover?.close()
			return
		}
		if modelEffortPopover == nil
		{
			let popover = ComposerPopoverPanel(contentViewController: modelEffortController)
			popover.onPresentationChange =
			{
				[weak self] presented in
				self?.modelEffortController.setPresented(presented)
				self?.refreshModelEffortButton()
			}
			modelEffortPopover = popover
		}
		modelEffortPopover?.show(
			relativeTo: modelEffortButton.bounds,
			of: modelEffortButton
		)
	}

	@objc private func showApprovalPolicy()
	{
		modelEffortPopover?.close()
		if approvalPolicyPopover == nil
		{
			let popover = NSPopover()
			popover.contentViewController = approvalPolicyController
			popover.contentSize = approvalPolicyController.preferredContentSize
			popover.behavior = .transient
			approvalPolicyPopover = popover
		}
		approvalPolicyPopover?.show(
			relativeTo: approvalPolicyButton.bounds,
			of: approvalPolicyButton,
			preferredEdge: .maxY
		)
	}

	func requestApprovalMode(_ mode: ApprovalMode)
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
			onSelectApprovalMode?(mode)
			return
		}
		guard let window = view.window, window.attachedSheet == nil
		else
		{
			return
		}

		// Capture the requesting workspace's callback before a later render can replace it.
		let applyMode = onSelectApprovalMode
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
			[weak self] response in
			self?.fullAccessConfirmationPanel = nil
			if response == .OK
			{
				applyMode?(.fullAccess)
			}
		}
	}

}
