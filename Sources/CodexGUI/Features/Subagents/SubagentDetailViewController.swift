import AppKit

@MainActor
final class SubagentDetailViewController: NSViewController
{
	let owner: FeaturePresentationOwner
	let transcript = TranscriptViewController()
	var onBack: (() -> Void)?
	var onLoadEarlierTurns: (() -> Void)?
	var onRetry: (() -> Void)?
	private(set) var agent: CodexSubagentActivity?
	private(set) var state: SubagentConversationState?
	private let nameLabel = NSTextField(labelWithString: "")
	private let metadataLabel = NSTextField(labelWithString: "")
	private let avatarContainer = NSView()
	private let status = DesktopStatusView(
		message: "",
		presentation: .conversation
	)
	private static let contentInset: CGFloat = 16
	private static let contentSpacing: CGFloat = 12
	private static let headerSpacing: CGFloat = 10
	private static let avatarDimension: CGFloat = 24

	init(owner: FeaturePresentationOwner)
	{
		self.owner = owner
		super.init(
			nibName: nil,
			bundle: nil
		)
	}

	required init?(coder: NSCoder)
	{
		return nil
	}

	override func loadView()
	{
		view = NSView()
		let content = AppKitLayout.verticalStack(
			[],
			spacing: Self.contentSpacing
		)
		AppKitLayout.pin(
			content,
			to: view,
			inset: Self.contentInset
		)
		content.addArrangedSubview(makeHeader())
		let divider = NSBox()
		divider.boxType = .separator
		content.addArrangedSubview(divider)
		content.addArrangedSubview(makeStatusRow())
		addChild(transcript)
		content.addArrangedSubview(makeTranscriptContent())
		for child in content.arrangedSubviews
		{
			child.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
		}
		transcript.onLoadEarlierTurns =
		{
			[weak self] in
			self?.onLoadEarlierTurns?()
		}
	}

	func render(
		agent: CodexSubagentActivity,
		state: SubagentConversationState
	)
	{
		_ = view
		self.agent = agent
		self.state = state
		nameLabel.stringValue = agent.displayName
		let settingsDescription = state.settings.map
		{
			settings in
			[settings.model, settings.reasoningEffort].compactMap
			{
				$0
			}.joined(separator: " · ")
		}
		metadataLabel.stringValue = settingsDescription ?? ""
		metadataLabel.isHidden = metadataLabel.stringValue.isEmpty
		renderAvatar(agent)
		status.setMessage("")
		status.setLoading(false)
		status.setActions(state.error == nil ? [] : [DesktopStatusView.Action(
			title: "Retry",
			isEnabled: !state.isLoading,
			onActivate:
			{
				[weak self] in
				guard let self, self.state?.error != nil, self.state?.isLoading == false
				else
				{
					return
				}
				self.onRetry?()
			}
		)])
		transcript.render(TranscriptPresentation(
			owner: owner,
			entries: state.entries,
			turnTimings: state.turnTimings,
			canLoadEarlierTurns: state.nextCursor != nil,
			navigation: nil,
			executionState: .ready,
			activeThreadID: nil,
			activeTurnID: nil
		))
		transcript.setLoadEarlierEnabled(!state.isLoading)
	}

	private func makeTranscriptContent() -> NSView
	{
		let stack = AppKitLayout.verticalStack(
			[makeTranscriptUtilityRow(), transcript.view],
			spacing: 6
		)
		stack.alignment = .leading
		for row in stack.arrangedSubviews
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		let container = DesktopSurface(AppKitColorTokens.canvas)
		AppKitLayout.pin(
			stack,
			to: container
		)
		return container
	}

	private func makeTranscriptUtilityRow() -> NSView
	{
		let utilityRow = transcript.utilityRow
		let centeredRow = NSView()
		centeredRow.addSubview(utilityRow)
		utilityRow.translatesAutoresizingMaskIntoConstraints = false
		let preferredWidth = utilityRow.widthAnchor.constraint(equalTo: centeredRow.widthAnchor)
		preferredWidth.priority = .defaultLow
		NSLayoutConstraint.activate([
			utilityRow.centerXAnchor.constraint(equalTo: centeredRow.centerXAnchor),
			utilityRow.widthAnchor.constraint(
				lessThanOrEqualToConstant: ConversationFlowLayout.maximumContentWidth
			),
			utilityRow.widthAnchor.constraint(lessThanOrEqualTo: centeredRow.widthAnchor),
			preferredWidth,
			utilityRow.topAnchor.constraint(equalTo: centeredRow.topAnchor),
			utilityRow.bottomAnchor.constraint(equalTo: centeredRow.bottomAnchor),
		])
		centeredRow.isHidden = utilityRow.isHidden
		transcript.onUtilityRowVisibilityChanged =
		{
			[weak centeredRow, weak utilityRow] in
			centeredRow?.isHidden = utilityRow?.isHidden ?? true
		}
		return centeredRow
	}

	private func makeHeader() -> NSView
	{
		let backButton = DesktopBackButton(
			target: self,
			action: #selector(goBack)
		)
		backButton.setAccessibilityLabel("Back to Subagents")
		backButton.toolTip = "Back to Subagents"
		avatarContainer.widthAnchor.constraint(equalToConstant: Self.avatarDimension)
			.isActive = true
		avatarContainer.heightAnchor.constraint(equalToConstant: Self.avatarDimension)
			.isActive = true
		nameLabel.font = .systemFont(
			ofSize: 15,
			weight: .semibold
		)
		nameLabel.lineBreakMode = .byTruncatingTail
		nameLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		metadataLabel.font = .systemFont(ofSize: 12)
		metadataLabel.textColor = .secondaryLabelColor
		metadataLabel.lineBreakMode = .byTruncatingTail
		metadataLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let spacer = NSView()
		spacer.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		metadataLabel.alignment = .right
		let header = AppKitLayout.horizontalStack(
			[
				backButton,
				avatarContainer,
				nameLabel,
				spacer,
				metadataLabel
			],
			spacing: Self.headerSpacing,
			alignment: .centerY
		)
		return header
	}

	private func makeStatusRow() -> NSView
	{
		status
	}

	private func renderAvatar(_ agent: CodexSubagentActivity)
	{
		for child in avatarContainer.subviews
		{
			child.removeFromSuperview()
		}
		let avatar = ConversationSubagentAvatarView(
			assetName: ConversationSubagentAvatars.assetName(for: agent.identity),
			name: agent.name
		)
		AppKitLayout.pin(
			avatar,
			to: avatarContainer,
			inset: 0
		)
	}

	@objc private func goBack()
	{
		onBack?()
	}

}
