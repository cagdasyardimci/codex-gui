import AppKit

@MainActor
final class SubagentsViewController: NSViewController
{
	typealias TimeRefreshTimerFactory = (
		TimeInterval,
		@escaping @Sendable (Timer) -> Void
	) -> Timer

	let owner: FeaturePresentationOwner
	private(set) var subagents: ConversationSubagents
	var onSelectThread: ((String) -> Void)?
	{
		didSet
		{
			updateAgentActions()
		}
	}
	var onBack: (() -> Void)?
	var onLoadEarlierTurns: (() -> Void)?
	var onRetry: (() -> Void)?
	private(set) var selectedAgent: CodexSubagentActivity?
	private(set) var detailController: SubagentDetailViewController?
	private let listScroll = NSScrollView()
	private var agentActions: [NSButton: CodexSubagentActivity] = [:]
	private var showsAllDoneAgents = false
	private let now: () -> Date
	private let makeTimeRefreshTimer: TimeRefreshTimerFactory
	private var completionLabels: [NSTextField: Date] = [:]
	private var elapsedLabels: [NSTextField: Date] = [:]
	private var refreshInterval: TimeInterval?
	private var timeRefreshTimer: Timer?
	private var isPresented = false
	var isRefreshingTimeLabels: Bool
	{
		timeRefreshTimer != nil
	}
	private let content = AppKitLayout.verticalStack(
		[],
		spacing: 14
	)
	private static let donePreviewLimit = 10
	private static let avatarDimension: CGFloat = 24
	private static let rowSpacing: CGFloat = 12
	private static let minimumRowHeight: CGFloat = 30
	private static let secondaryTextColor = NSColor(name: "SubagentsSecondaryText")
	{
		appearance in
		let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		return isDark ? .secondaryLabelColor : NSColor(
			calibratedWhite: 0.58,
			alpha: 1
		)
	}
	private final class SubagentShowMoreButton: DesktopStyledButton
	{
		init(
			title: String,
			target: AnyObject?,
			action: Selector?
		)
		{
			super.init(
				title: title,
				presentation: .nativeBorderless,
				size: .regular
			)
			self.target = target
			self.action = action
			alignment = .left
			contentTintColor = SubagentsViewController.secondaryTextColor
		}

		required init?(coder: NSCoder)
		{
			nil
		}
	}

	private static let textPointSize: CGFloat = 13
	private static let timePointSize: CGFloat = 12

	init(
		owner: FeaturePresentationOwner,
		subagents: ConversationSubagents,
		now: @escaping () -> Date = Date.init,
		makeTimeRefreshTimer: @escaping TimeRefreshTimerFactory =
		{
			interval, callback in
			Timer(
				timeInterval: interval,
				repeats: true,
				block: callback
			)
		}
	)
	{
		self.owner = owner
		self.subagents = subagents
		self.now = now
		self.makeTimeRefreshTimer = makeTimeRefreshTimer
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
		let scroll = listScroll
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.drawsBackground = false
		let document = DesktopFlippedView()
		document.translatesAutoresizingMaskIntoConstraints = false
		scroll.documentView = document
		document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
		AppKitLayout.pin(
			content,
			to: document,
			inset: 24
		)
		view = NSView()
		AppKitLayout.pin(
			scroll,
			to: view,
			inset: 0
		)
		render()
	}

	override func viewDidAppear()
	{
		super.viewDidAppear()
		isPresented = true
		refreshTimeLabels()
		updateTimeRefreshTimer()
	}

	override func viewDidDisappear()
	{
		super.viewDidDisappear()
		isPresented = false
		stopTimeRefreshTimer()
	}

	func setPresentationVisible(_ visible: Bool)
	{
		isPresented = visible
		if visible
		{
			refreshTimeLabels()
		}
		updateTimeRefreshTimer()
	}

	func refreshTimeLabels()
	{
		let currentTime = now()
		for (label, startedAt) in elapsedLabels
		{
			label.stringValue = SubagentTimeFormatter.elapsed(
				startedAt: startedAt,
				now: currentTime
			)
		}
		for (label, completedAt) in completionLabels
		{
			label.stringValue = SubagentTimeFormatter.relativeCompletion(
				completedAt: completedAt,
				now: currentTime
			)
		}
	}

	private func updateTimeRefreshTimer()
	{
		let hasTimeLabels = !completionLabels.isEmpty || !elapsedLabels.isEmpty
		guard isPresented, selectedAgent == nil, hasTimeLabels
		else
		{
			stopTimeRefreshTimer()
			return
		}
		let interval: TimeInterval = elapsedLabels.isEmpty ? 60 : 1
		if refreshInterval != interval
		{
			stopTimeRefreshTimer()
		}
		guard timeRefreshTimer == nil
		else
		{
			return
		}
		let timer = makeTimeRefreshTimer(interval)
		{
			[weak self] timer in
			guard let self
			else
			{
				timer.invalidate()
				return
			}
			let timerIdentity = ObjectIdentifier(timer)
			MainActor.assumeIsolated
			{
				guard self.timeRefreshTimer.map(ObjectIdentifier.init) == timerIdentity,
						self.isPresented,
						self.selectedAgent == nil
				else
				{
					return
				}
				if self.view.isHiddenOrHasHiddenAncestor
				{
					self.stopTimeRefreshTimer()
					return
				}
				self.refreshTimeLabels()
			}
		}
		timeRefreshTimer = timer
		refreshInterval = interval
		RunLoop.main.add(
			timer,
			forMode: .common
		)
	}

	private func stopTimeRefreshTimer()
	{
		timeRefreshTimer?.invalidate()
		timeRefreshTimer = nil
		refreshInterval = nil
	}

	func update(_ subagents: ConversationSubagents)
	{
		guard self.subagents != subagents
		else
		{
			return
		}
		self.subagents = subagents
		if isViewLoaded
		{
			render()
		}
	}

	func showConversation(
		agent: CodexSubagentActivity,
		state: SubagentConversationState
	)
	{
		guard let threadID = agent.conversationThreadID
		else
		{
			return
		}
		_ = view
		if selectedAgent?.conversationThreadID != threadID
		{
			if let previous = detailController
			{
				previous.view.removeFromSuperview()
				previous.removeFromParent()
			}
			let detail = SubagentDetailViewController(
				owner: owner.replacingSelectedThreadID(threadID)
			)
			detail.onBack =
			{
				[weak self, weak detail] in
				guard let self, let detail, self.detailController === detail,
						self.selectedAgent?.conversationThreadID == threadID
				else
				{
					return
				}
				self.showList()
				self.onBack?()
			}
			detail.onLoadEarlierTurns =
			{
				[weak self, weak detail] in
				guard let self, let detail, self.detailController === detail,
						self.selectedAgent?.conversationThreadID == threadID
				else
				{
					return
				}
				self.onLoadEarlierTurns?()
			}
			detail.onRetry =
			{
				[weak self, weak detail] in
				guard let self, let detail, self.detailController === detail,
						self.selectedAgent?.conversationThreadID == threadID
				else
				{
					return
				}
				self.onRetry?()
			}
			addChild(detail)
			AppKitLayout.pin(
				detail.view,
				to: view,
				inset: 0
			)
			detailController = detail
		}
		selectedAgent = agent
		stopTimeRefreshTimer()
		listScroll.isHidden = true
		detailController?.view.isHidden = false
		detailController?.render(
			agent: agent,
			state: state
		)
	}

	func showList()
	{
		selectedAgent = nil
		detailController?.view.isHidden = true
		listScroll.isHidden = false
		refreshTimeLabels()
		updateTimeRefreshTimer()
	}

	private func render()
	{
		agentActions.removeAll()
		completionLabels.removeAll()
		elapsedLabels.removeAll()
		for child in content.arrangedSubviews
		{
			content.removeArrangedSubview(child)
			child.removeFromSuperview()
		}
		appendHeading("Active · \(subagents.activeAgents.count)")
		for agent in subagents.activeAgents
		{
			appendRow(agent)
		}
		if let last = content.arrangedSubviews.last
		{
			content.setCustomSpacing(
				28,
				after: last
			)
		}
		appendHeading("Finished · \(subagents.doneAgents.count)")
		let visibleDone = showsAllDoneAgents
			? subagents.doneAgents : Array(subagents.doneAgents.prefix(Self.donePreviewLimit))
		for agent in visibleDone
		{
			appendRow(agent)
		}
		let remainingCount = subagents.doneAgents.count - visibleDone.count
		if remainingCount > 0
		{
			let button = SubagentShowMoreButton(
				title: "Show \(remainingCount) more",
				target: self,
				action: #selector(showMore(_:))
			)
			button.identifier = NSUserInterfaceItemIdentifier("subagents-show-more")
			content.addArrangedSubview(button)
		}
		refreshTimeLabels()
		updateTimeRefreshTimer()
	}

	private func appendHeading(_ text: String)
	{
		let label = NSTextField(labelWithString: text)
		label.font = .systemFont(ofSize: Self.textPointSize)
		label.textColor = Self.secondaryTextColor
		content.addArrangedSubview(label)
		label.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
	}

	private func appendRow(_ agent: CodexSubagentActivity)
	{
		let avatar = ConversationSubagentAvatarView(
			assetName: ConversationSubagentAvatars.assetName(for: agent.identity),
			name: agent.name
		)
		avatar.widthAnchor.constraint(equalToConstant: Self.avatarDimension).isActive = true
		avatar.heightAnchor.constraint(equalToConstant: Self.avatarDimension).isActive = true

		let name = SubagentNameButton(title: agent.displayName)
		name.target = self
		name.action = #selector(selectThread(_:))
		name.identifier = NSUserInterfaceItemIdentifier("subagent-open:\(agent.identity)")
		name.setAccessibilityLabel("Open subagent chat: \(agent.name)")
		name.isEnabled = onSelectThread != nil && agent.conversationThreadID != nil
		agentActions[name] = agent
		let status = subagents.status(for: agent)
		let spacer = NSView()
		spacer.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		var rowViews: [NSView] = [avatar, name, spacer]
		if let completedAt = subagents.completedAt(for: agent)
		{
			let completion = makeTimeLabel(
				agent,
				identifierPrefix: "subagent-completed"
			)
			completionLabels[completion] = completedAt
			rowViews.append(completion)
		}
		if status == .active
		{
			if let startedAt = subagents.startedAt(for: agent)
			{
				let elapsed = makeTimeLabel(
					agent,
					identifierPrefix: "subagent-elapsed"
				)
				elapsedLabels[elapsed] = startedAt
				rowViews.append(elapsed)
			}
		}
		let row = AppKitLayout.horizontalStack(
			rowViews,
			spacing: Self.rowSpacing,
			alignment: .centerY
		)
		row.identifier = NSUserInterfaceItemIdentifier("subagent:\(agent.identity)")
		content.addArrangedSubview(row)
		row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
		row.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumRowHeight)
			.isActive = true
	}

	private func makeTimeLabel(
		_ agent: CodexSubagentActivity,
		identifierPrefix: String
	) -> NSTextField
	{
		let label = NSTextField(labelWithString: "")
		label.font = .systemFont(ofSize: Self.timePointSize)
		label.textColor = Self.secondaryTextColor
		label.alignment = .right
		label.identifier = NSUserInterfaceItemIdentifier("\(identifierPrefix):\(agent.identity)")
		return label
	}

	private func updateAgentActions()
	{
		for (button, agent) in agentActions
		{
			button.isEnabled = onSelectThread != nil && agent.conversationThreadID != nil
		}
	}

	@objc private func selectThread(_ sender: NSButton)
	{
		guard let agent = agentActions[sender], subagents.agents.contains(agent),
				let threadID = agent.conversationThreadID, let onSelectThread
		else
		{
			return
		}
		onSelectThread(threadID)
	}

	@objc private func showMore(_ sender: NSButton)
	{
		showsAllDoneAgents = true
		render()
	}
}

/// A name link keeps its recorded title readable when navigation is unavailable.
@MainActor
private final class SubagentNameButton: DesktopAttributedTitleButton
{
	init(title: String)
	{
		super.init(frame: .zero)
		cell = SubagentNameButtonCell(textCell: title)
		isBordered = false
		alignment = .left
		font = .systemFont(ofSize: 13)
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		attributedTitle = NSAttributedString(
			string: title,
			attributes: [
				.font: NSFont.systemFont(ofSize: 13),
				.foregroundColor: NSColor.labelColor,
				.paragraphStyle: paragraph,
			]
		)
		cell?.lineBreakMode = .byTruncatingTail
		setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}

private final class SubagentNameButtonCell: NSButtonCell
{
	override func drawTitle(
		_ title: NSAttributedString,
		withFrame frame: NSRect,
		in controlView: NSView
	) -> NSRect
	{
		attributedTitle.draw(in: frame)
		return frame
	}
}
