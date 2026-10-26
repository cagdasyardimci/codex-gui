import AppKit

@MainActor
final class SubagentAvatarNavigationButton: NSButton
{
	private let agents: [CodexSubagentActivity]
	private let onSelectThread: (String) -> Void

	init(
		agents: [CodexSubagentActivity],
		isOverflow: Bool = false,
		onSelectThread: @escaping (String) -> Void
	)
	{
		self.agents = agents
		self.onSelectThread = onSelectThread
		super.init(frame: .zero)
		title = ""
		isBordered = false
		refusesFirstResponder = false
		target = self
		action = #selector(openConversation)
		setButtonType(.momentaryPushIn)
		let label = !isOverflow && agents.count == 1
			? "Open conversation: \(agents[0].name), \(agents[0].action)"
			: "More subagent conversations"
		toolTip = label
		setAccessibilityLabel(label)
		isEnabled = isOverflow || agents.first?.conversationThreadID != nil
		if isOverflow
		{
			menu = makeOverflowMenu()
		}
	}

	@available(
		*,
		unavailable
	)
	required init?(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}

	@objc private func openConversation()
	{
		if menu == nil, let agent = agents.first
		{
			if let threadID = agent.conversationThreadID
			{
				onSelectThread(threadID)
			}
			return
		}
		menu?.popUp(
			positioning: nil,
			at: NSPoint(
				x: 0,
				y: bounds.maxY
			),
			in: self
		)
	}

	private func makeOverflowMenu() -> NSMenu
	{
		let menu = NSMenu()
		for (index, agent) in agents.enumerated()
		{
			let item = NSMenuItem(
				title: "\(agent.name), \(agent.action)",
				action: #selector(selectOverflowAgent(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.tag = index
			item.isEnabled = agent.conversationThreadID != nil
			menu.addItem(item)
		}
		menu.autoenablesItems = false
		return menu
	}

	@objc private func selectOverflowAgent(_ item: NSMenuItem)
	{
		guard agents.indices.contains(item.tag),
				let threadID = agents[item.tag].conversationThreadID
		else
		{
			return
		}
		onSelectThread(threadID)
	}
}
