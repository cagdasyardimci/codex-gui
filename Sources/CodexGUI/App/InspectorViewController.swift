import AppKit

@MainActor
final class InspectorViewController: NSViewController
{
	let changes = ChangesViewController()
	let summary = PinnedSummaryViewController()
	let toolsTabs = ToolsTabViewController()
	private(set) var isShowingTools = false
	private var isShowingExpandedConversation = false
	private var expandedConversationSummaryRevealed = false
	var onToolsClose: ((Bool) -> Void)?
	var onPaneContentChange: (() -> Void)?
	private var summaryVisible = true
	private(set) var isShowingDetails = false
	private var renderedOwner: FeaturePresentationOwner?
	private weak var inspectorBox: NSView?
	private let headerDivider = DesktopSurface(DesktopTheme.border)
	var onSummaryDisplayChange: ((Bool) -> Void)?
	private let content = NSView()
	private let projectLabel = NSTextField(labelWithString: "Project")
	private var preferredBoxHeight: NSLayoutConstraint?
	private var hasReviewContent = false
	private var summaryTransition: PinnedSummaryTransition?
	private var summaryTransitionRevision = 0

	override func loadView()
	{
		let container = DesktopSurface(DesktopTheme.canvas)
		let box = makeInspectorBox(in: container)

		configureHeaderControls()
		installInspectorContent(in: box)

		view = container
		addChild(toolsTabs)
		AppKitLayout.pin(
			toolsTabs.view,
			to: container,
			inset: 0
		)
		toolsTabs.view.isHidden = true
		toolsTabs.onCloseLastTab =
		{
			[weak self] in self?.closeToolsPane()
		}
		toolsTabs.onClosePane =
		{
			[weak self] in self?.closeToolsPane()
		}
		addChild(summary)
		AppKitLayout.pin(
			summary.view,
			to: content,
			inset: 0
		)
		addChild(changes)
		AppKitLayout.pin(
			changes.view,
			to: content,
			inset: 0
		)
	}

	func renderSummary(
		_ presentation: PinnedSummaryPresentation,
		visible: Bool
	)
	{
		_ = view
		if renderedOwner != presentation.owner || summaryVisible != visible
		{
			cancelSummaryTransition()
		}
		if renderedOwner != presentation.owner
		{
			isShowingDetails = false
			expandedConversationSummaryRevealed = false
		}
		renderedOwner = presentation.owner
		summaryVisible = visible
		summary.render(presentation)
		updateContentVisibility()
	}

	func showSummary()
	{
		isShowingTools = false
		isShowingDetails = false
		updateContentVisibility()
	}

	var isSummaryBesideExpandedConversation: Bool
	{
		isShowingTools && isShowingExpandedConversation && expandedConversationSummaryRevealed
			&& summaryVisible
	}

	func setExpandedConversation(
		_ active: Bool,
		resetSummary: Bool
	)
	{
		if isShowingExpandedConversation != active
		{
			cancelSummaryTransition()
		}
		isShowingExpandedConversation = active
		if resetSummary
		{
			expandedConversationSummaryRevealed = false
		}
		updateContentVisibility()
	}

	func showSummaryBesideExpandedConversation()
	{
		expandedConversationSummaryRevealed = true
		isShowingDetails = false
		updateContentVisibility()
	}

	func showReportedChanges()
	{
		cancelSummaryTransition()
		_ = view
		isShowingTools = false
		isShowingDetails = true
		updateContentVisibility()
	}

	func showToolsTab()
	{
		cancelSummaryTransition()
		_ = view
		toolsTabs.openNewTab()
		isShowingTools = true
		updateContentVisibility()
	}

	/// Clears the previous surface before caching the opening transition, preserving pane geometry.
	func hideContentForToolsOpening()
	{
		cancelSummaryTransition()
		_ = view
		inspectorBox?.isHidden = true
		toolsTabs.view.isHidden = true
	}

	func showToolsPane()
	{
		cancelSummaryTransition()
		_ = view
		if toolsTabs.tabCount == 0
		{
			toolsTabs.openNewTab()
		}
		isShowingTools = true
		updateContentVisibility()
	}

	func closeToolsPane()
	{
		isShowingTools = false
		updateContentVisibility()
		onToolsClose?(isShowingDetails || summaryVisible)
	}

	func animateSummaryVisibilityChange(_ updates: () -> Void)
	{
		cancelSummaryTransition()
		_ = view
		guard !isShowingTools || (isShowingExpandedConversation && !isSummaryDisplayed),
				!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		else
		{
			updates()
			return
		}
		let wasDisplayed = isSummaryDisplayed
		let closingTransition = wasDisplayed
			? inspectorBox.flatMap
			{
				PinnedSummaryTransition(view: $0)
			} : nil
		updates()
		view.window?.layoutIfNeeded()
		view.layoutSubtreeIfNeeded()
		let isDisplayed = isSummaryDisplayed
		guard wasDisplayed != isDisplayed
		else
		{
			return
		}
		let transition = isDisplayed
			? inspectorBox.flatMap
			{
				PinnedSummaryTransition(view: $0)
			} : closingTransition
		guard let transition
		else
		{
			return
		}
		summaryTransitionRevision += 1
		let revision = summaryTransitionRevision
		summaryTransition = transition
		transition.animate(appearing: isDisplayed)
		{
			[weak self] in
			guard let self, self.summaryTransitionRevision == revision
			else
			{
				return
			}
			self.summaryTransition = nil
		}
	}

	private var isSummaryDisplayed: Bool
	{
		guard summaryVisible, !isShowingDetails,
				!isShowingTools || isSummaryBesideExpandedConversation, let inspectorBox
		else
		{
			return false
		}
		return !inspectorBox.isHiddenOrHasHiddenAncestor
	}

	private func cancelSummaryTransition()
	{
		summaryTransitionRevision += 1
		summaryTransition?.cancel()
		summaryTransition = nil
	}

	private func updateContentVisibility()
	{
		let showDetails = isShowingDetails && !isShowingTools
		summary.view.isHidden = showDetails || !summaryVisible
		changes.view.isHidden = !showDetails
		let showSummary = !isShowingTools ? summaryVisible : isSummaryBesideExpandedConversation
		inspectorBox?.isHidden = !showDetails && !showSummary
		toolsTabs.view.isHidden = !isShowingTools || isShowingExpandedConversation
		projectLabel.isHidden = !showDetails
		headerDivider.isHidden = !showDetails
		onSummaryDisplayChange?(showSummary && !showDetails)
		updateBoxHeight()
		onPaneContentChange?()
	}

	private func makeInspectorBox(in container: NSView) -> NSView
	{
		let box = DesktopSurface(
			DesktopTheme.inspector,
			cornerRadius: 16
		)
		box.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(box)
		inspectorBox = box
		let preferredHeight = box.heightAnchor.constraint(equalToConstant: 300)
		// The box may yield space without raising the window's minimum content height.
		preferredHeight.priority = NSLayoutConstraint.Priority(1)
		preferredBoxHeight = preferredHeight
		NSLayoutConstraint.activate([
			box.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: 12
			),
			box.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -12
			),
			box.topAnchor.constraint(
				equalTo: container.topAnchor,
				constant: 12
			),
			box.bottomAnchor.constraint(
				lessThanOrEqualTo: container.bottomAnchor,
				constant: -12
			),
			box.heightAnchor.constraint(lessThanOrEqualToConstant: 440),
			preferredHeight,
		])
		return box
	}

	private func configureHeaderControls()
	{
		projectLabel.font = .systemFont(
			ofSize: 13,
			weight: .regular
		)
		projectLabel.textColor = .secondaryLabelColor
		projectLabel.lineBreakMode = .byTruncatingMiddle
		projectLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		projectLabel.setAccessibilityLabel("Inspector project")
	}

	private func installInspectorContent(in box: NSView)
	{
		let divider = headerDivider
		let stack = AppKitLayout.verticalStack(
			[projectLabel, divider, content],
			spacing: 12
		)
		AppKitLayout.pin(
			stack,
			to: box,
			inset: 16
		)
		projectLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
		content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		content.bottomAnchor.constraint(equalTo: stack.bottomAnchor).isActive = true
		content.setContentHuggingPriority(
			.defaultLow,
			for: .vertical
		)
	}

	/// Updates the floating inspector's heading and height; child controllers render their own
	/// state.
	func render(_ snapshot: ConversationSnapshot)
	{
		render(ReviewPresentation(snapshot))
	}
	func render(_ snapshot: ReviewPresentation)
	{
		projectLabel.stringValue =
			snapshot.projectPath.map
				{
					URL(fileURLWithPath: $0).lastPathComponent
				} ?? "Project"
		projectLabel.toolTip = snapshot.projectPath
		if let review = snapshot.selectedReview
		{
			hasReviewContent = !review.files.isEmpty
		}
		else
		{
			hasReviewContent =
				snapshot.reviewTurns
					.isEmpty && (!snapshot.changedFiles.isEmpty || !snapshot.diff.isEmpty)
		}
		updateBoxHeight()
	}

	private func updateBoxHeight()
	{
		preferredBoxHeight?.constant = isShowingDetails ? (hasReviewContent ? 440 : 300) : 320
	}
}
