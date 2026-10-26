import AppKit

/// Complete status presentation; feature owners supply messages and recovery actions.
@MainActor
class DesktopStatusView: DesktopSurface
{
	enum Presentation
	{
		case centered, inline, inlineCompact, conversation, imageOverlay
	}
	struct Action
	{
		let title: String
		let accessibilityLabel: String?
		let identifier: String?
		let isEnabled: Bool
		let onActivate: () -> Void

		init(
			title: String,
			accessibilityLabel: String? = nil,
			identifier: String? = nil,
			isEnabled: Bool = true,
			onActivate: @escaping () -> Void
		)
		{
			self.title = title
			self.accessibilityLabel = accessibilityLabel
			self.identifier = identifier
			self.isEnabled = isEnabled
			self.onActivate = onActivate
		}
	}
	let messageLabel = NSTextField(wrappingLabelWithString: "")
	private let titleLabel = NSTextField(wrappingLabelWithString: "")
	private let actionsStack = NSStackView()
	private let presentation: Presentation
	private var hasTitle = false
	private let loadingIndicator = NSProgressIndicator()
	private var actionsEnabled = true
	private var actionEnabledStates: [Bool] = []
	private var actionIdentities: [String] = []
	private(set) var isLoading = false
	private var usesInlineLayout: Bool
	{
		presentation == .inline || presentation == .inlineCompact || presentation == .conversation
	}

	var stringValue: String
	{
		get
		{
			messageLabel.stringValue
		}
		set
		{
			setMessage(newValue)
		}
	}

	init(
		icon: NSImage? = nil,
		title: String? = nil,
		message: String,
		actions: [Action] = [],
		presentation: Presentation = .centered
	)
	{
		self.presentation = presentation
		super.init(presentation == .centered ? AppKitColorTokens.canvas : .clear)
		var views: [NSView] = []
		loadingIndicator.style = .spinning
		loadingIndicator.controlSize = .small
		loadingIndicator.isDisplayedWhenStopped = false
		loadingIndicator.isHidden = true
		loadingIndicator.setAccessibilityLabel("Loading")
		if presentation == .imageOverlay
		{
			loadingIndicator.appearance = NSAppearance(named: .darkAqua)
		}
		views.append(loadingIndicator)
		if let icon
		{
			let image = NSImageView(image: icon)
			image.contentTintColor = AppKitColorTokens.secondaryText
			image.setAccessibilityElement(false)
			let side: CGFloat = presentation == .centered ? 32 : 16
			image.widthAnchor.constraint(equalToConstant: side).isActive = true
			image.heightAnchor.constraint(equalToConstant: side).isActive = true
			views.append(image)
		}
		hasTitle = title?.isEmpty == false
		titleLabel.stringValue = title ?? ""
		titleLabel.font = .systemFont(
			ofSize: presentation == .inlineCompact ? 11 : (presentation == .inline ? 12 : 16),
			weight: .medium
		)
		titleLabel.textColor = presentation == .imageOverlay ? .white : AppKitColorTokens
			.primaryText
		titleLabel.isHidden = !hasTitle
		titleLabel.setAccessibilityRoleDescription("heading")
		messageLabel
			.font =
			.systemFont(ofSize: presentation == .inlineCompact ? 11 :
				(presentation == .inline ? 12 : 13))
		messageLabel.textColor = presentation == .imageOverlay ? .white : AppKitColorTokens
			.secondaryText
		messageLabel.isSelectable = true
		for label in [titleLabel, messageLabel]
		{
			label.alignment = usesInlineLayout ? .left : .center
			label.setContentCompressionResistancePriority(
				.defaultLow,
				for: .horizontal
			)
		}
		let text = AppKitLayout.verticalStack(
			[titleLabel, messageLabel],
			spacing: 4
		)
		text.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		views.append(text)
		actionsStack.orientation = .horizontal
		actionsStack.alignment = .centerY
		actionsStack.spacing = 8
		views.append(actionsStack)
		let stack = !usesInlineLayout
			? AppKitLayout.verticalStack(
				views,
				spacing: 12,
				alignment: .centerX
			)
			: AppKitLayout.horizontalStack(
				views,
				spacing: 8
			)
		if !usesInlineLayout
		{
			stack.translatesAutoresizingMaskIntoConstraints = false
			addSubview(stack)
			let leading = stack.leadingAnchor.constraint(
				greaterThanOrEqualTo: leadingAnchor,
				constant: 16
			)
			let trailing = stack.trailingAnchor.constraint(
				lessThanOrEqualTo: trailingAnchor,
				constant: -16
			)
			leading.priority = NSLayoutConstraint.Priority(999)
			trailing.priority = NSLayoutConstraint.Priority(999)
			NSLayoutConstraint.activate([
				stack.centerXAnchor.constraint(equalTo: centerXAnchor),
				stack.centerYAnchor.constraint(equalTo: centerYAnchor),
				leading,
				trailing,
				text.widthAnchor.constraint(equalTo: stack.widthAnchor),
				messageLabel.widthAnchor.constraint(equalTo: text.widthAnchor),
				titleLabel.widthAnchor.constraint(equalTo: text.widthAnchor),
			])
		}
		else
		{
			AppKitLayout.pin(
				stack,
				to: self,
				inset: 0
			)
			text.setContentHuggingPriority(
				.defaultLow,
				for: .horizontal
			)
			messageLabel.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
			titleLabel.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
		}
		setActions(actions)
		setMessage(message)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func setMessage(_ message: String)
	{
		messageLabel.stringValue = message
		messageLabel.isHidden = message.isEmpty
		updateVisibility()
	}

	func setActions(_ actions: [Action])
	{
		let identities = actions.map
		{
			$0.identifier ?? $0.accessibilityLabel ?? $0.title
		}
		if identities != actionIdentities
		{
			for child in actionsStack.arrangedSubviews
			{
				actionsStack.removeArrangedSubview(child)
				child.removeFromSuperview()
			}
			for action in actions
			{
				actionsStack.addArrangedSubview(DesktopActionButton(
					title: action.title,
					presentation: .secondary,
					size: usesInlineLayout && presentation != .conversation ? .compact : .regular
				))
			}
			actionIdentities = identities
		}
		actionEnabledStates = actions.map(\.isEnabled)
		for (index, action) in actions.enumerated()
		{
			guard let button = actionsStack.arrangedSubviews[index] as? DesktopActionButton
			else
			{
				continue
			}
			button.title = action.title
			button.setAccessibilityLabel(action.accessibilityLabel ?? action.title)
			button.onAction = action.onActivate
			button.isEnabled = actionsEnabled && action.isEnabled
		}
		actionsStack.isHidden = actions.isEmpty
		updateVisibility()
	}

	func setActionsEnabled(_ enabled: Bool)
	{
		actionsEnabled = enabled
		for (index, child) in actionsStack.arrangedSubviews.enumerated()
		{
			(child as? NSButton)?.isEnabled = enabled && actionEnabledStates[index]
		}
	}

	func setLoading(_ loading: Bool)
	{
		isLoading = loading
		loadingIndicator.isHidden = !loading
		if loading
		{
			loadingIndicator.startAnimation(nil)
		}
		else
		{
			loadingIndicator.stopAnimation(nil)
		}
		updateVisibility()
	}

	private func updateVisibility()
	{
		if usesInlineLayout
		{
			isHidden = messageLabel.stringValue.isEmpty && !hasTitle
				&& actionsStack.arrangedSubviews.isEmpty && !isLoading
		}
	}
}
