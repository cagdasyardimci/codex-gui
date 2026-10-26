import AppKit

@MainActor
enum ConversationSubagentAvatars
{
	static let assetNames = [
		"01-gaze-geometric",
		"02-gaze-geometric",
		"03-gaze-geometric",
		"04-gaze-geometric",
		"05-gaze-geometric",
		"06-gaze-geometric",
		"07-gaze-geometric",
		"08-gaze-geometric",
		"09-gaze-geometric",
		"10-gaze-geometric",
		"11-gaze-geometric",
		"12-gaze-geometric",
		"13-gaze-geometric",
		"14-gaze-geometric",
		"15-gaze-geometric",
		"16-gaze-geometric",
		"17-gaze-geometric",
		"18-gaze-geometric",
		"19-gaze-geometric",
		"20-gaze-geometric",
		"21-gaze-geometric",
		"22-gaze-geometric",
		"23-gaze-geometric",
		"24-gaze-geometric",
		"25-gaze-geometric",
		"26-gaze-geometric",
		"27-gaze-geometric",
		"28-gaze-geometric",
	]
	private static let maximumVisibleAvatars = 4
	private static let avatarSize: CGFloat = 18
	private static var assignedAssets: [String: String] = [:]
	private static let imageCache = NSCache<NSString, NSImage>()

	static func make(
		_ agents: [CodexSubagentActivity],
		onSelectThread: ((String) -> Void)? = nil
	) -> NSView
	{
		let stack = NSStackView()
		stack.orientation = .horizontal
		stack.alignment = .centerY
		stack.spacing = 5
		let count = min(
			agents.count,
			maximumVisibleAvatars
		)
		let width = CGFloat(count) * avatarSize + CGFloat(max(
			0,
			count - 1
		)) * stack.spacing
		let hasOverflow = onSelectThread != nil && agents.count > maximumVisibleAvatars
		let interactiveWidth = width + (hasOverflow ? avatarSize + stack.spacing : 0)
		stack.widthAnchor.constraint(equalToConstant: interactiveWidth).isActive = true
		for agent in agents.prefix(maximumVisibleAvatars)
		{
			stack.addArrangedSubview(makeAvatar(
				agent,
				onSelectThread: onSelectThread
			))
		}
		if hasOverflow, let onSelectThread
		{
			let button = SubagentAvatarNavigationButton(
				agents: Array(agents.dropFirst(maximumVisibleAvatars)),
				isOverflow: true,
				onSelectThread: onSelectThread
			)
			button.title = "…"
			button.widthAnchor.constraint(equalToConstant: avatarSize).isActive = true
			button.heightAnchor.constraint(equalToConstant: avatarSize).isActive = true
			stack.addArrangedSubview(button)
		}
		stack.setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
		return stack
	}

	private static func makeAvatar(
		_ agent: CodexSubagentActivity,
		onSelectThread: ((String) -> Void)?
	) -> NSView
	{
		let avatar = ConversationSubagentAvatarView(
			assetName: assetName(for: agent.identity),
			name: agent.name
		)
		avatar.translatesAutoresizingMaskIntoConstraints = false
		avatar.widthAnchor.constraint(equalToConstant: avatarSize).isActive = true
		avatar.heightAnchor.constraint(equalToConstant: avatarSize).isActive = true
		if let onSelectThread
		{
			let button = SubagentAvatarNavigationButton(
				agents: [agent],
				onSelectThread: onSelectThread
			)
			button.addSubview(avatar)
			avatar.setAccessibilityElement(false)
			avatar.centerXAnchor.constraint(equalTo: button.centerXAnchor).isActive = true
			avatar.centerYAnchor.constraint(equalTo: button.centerYAnchor).isActive = true
			button.widthAnchor.constraint(equalToConstant: avatarSize).isActive = true
			button.heightAnchor.constraint(equalToConstant: avatarSize).isActive = true
			return button
		}
		else
		{
			return avatar
		}
	}

	static func assetName(for identity: String) -> String
	{
		if let assigned = assignedAssets[identity]
		{
			return assigned
		}
		// Assign once per app session so lifecycle updates and scrolling retain the same avatar.
		let chosen = assetNames[Int.random(in: assetNames.indices)]
		assignedAssets[identity] = chosen
		return chosen
	}

	static func resourceDirectory(in appResourcesURL: URL?) -> URL?
	{
		let bundle: Bundle
		if let appResourcesURL
		{
			guard let packaged = Bundle(url: appResourcesURL.appendingPathComponent(
				"CodexGUI_CodexGUI.bundle"
			))
			else
			{
				return nil
			}
			bundle = packaged
		}
		else
		{
			bundle = .module
		}
		return bundle.resourceURL?.appendingPathComponent("SubagentAvatars")
	}

	static func image(
		named name: String,
		dark: Bool
	) -> NSImage?
	{
		let mode = dark ? "dark" : "light"
		let key = "\(mode):\(name)" as NSString
		if let image = imageCache.object(forKey: key)
		{
			return image
		}
		let appResourcesURL = Bundle.main.bundleURL.pathExtension == "app"
			? Bundle.main.resourceURL : nil
		guard let url = resourceDirectory(in: appResourcesURL)?
			.appendingPathComponent(mode).appendingPathComponent(name)
			.appendingPathExtension("svg"),
			let image = NSImage(contentsOf: url)
		else
		{
			return nil
		}
		image.isTemplate = false
		imageCache.setObject(
			image,
			forKey: key
		)
		return image
	}
}
