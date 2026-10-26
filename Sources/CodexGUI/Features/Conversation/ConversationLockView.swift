import AppKit

@MainActor
final class ConversationLockView: DesktopSurface
{
	var onRetry: (() -> Void)?
	var onFork: (() -> Void)?
	var canFork = false
	{
		didSet
		{
			forkButton.isEnabled = canFork
		}
	}
	var isRetrying = false
	{
		didSet
		{
			retryButton.isEnabled = !isRetrying
			retryButton.toolTip = isRetrying
				? "Checking whether this chat is available"
				: "Try opening this chat again"
		}
	}

	private let retryButton = DesktopStyledButton(
		title: "Retry",
		presentation: .quiet
	)
	private let forkButton = DesktopStyledButton(
		title: "Fork chat",
		presentation: .quiet
	)

	init()
	{
		super.init(
			AppKitColorTokens.canvas,
			cornerRadius: ShapeTokens.ChatLock.cornerRadius,
			bordered: true,
			borderWidth: ShapeTokens.ChatLock.edgeWidth,
			borderColor: AppKitColorTokens.chatLockEdge
		)
		let lockIcon = ConversationLockIconView()

		let title = NSTextField(labelWithString: "This is open in another app")
		title.font = AppKitFontResolver.font(TypographyTokens.ChatLock.title)
		title.textColor = AppKitColorTokens.primaryText
		title.lineBreakMode = .byTruncatingTail
		if let lineHeight = TypographyTokens.ChatLock.title.lineHeight
		{
			title.heightAnchor.constraint(equalToConstant: lineHeight).isActive = true
		}
		let detail = NSTextField(labelWithString: "Close it there to continue here.")
		detail.font = AppKitFontResolver.font(TypographyTokens.ChatLock.detail)
		detail.textColor = AppKitColorTokens.captionText
		detail.lineBreakMode = .byTruncatingTail
		if let lineHeight = TypographyTokens.ChatLock.detail.lineHeight
		{
			detail.heightAnchor.constraint(equalToConstant: lineHeight).isActive = true
		}
		let message = AppKitLayout.verticalStack(
			[title, detail],
			spacing: LayoutTokens.ChatLock.messageSpacing
		)
		message.alignment = .leading
		message.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		message.setContentHuggingPriority(
			.defaultHigh,
			for: .horizontal
		)

		let divider = DesktopSurface(AppKitColorTokens.chatLockDivider)
		divider.translatesAutoresizingMaskIntoConstraints = false
		for button in [retryButton, forkButton]
		{
			button.isBordered = false
			button.hoverTrackingOptions = [
				.mouseEnteredAndExited,
				.activeInActiveApp,
				.inVisibleRect
			]
			button.setButtonType(.momentaryPushIn)
			button.setContentCompressionResistancePriority(
				.required,
				for: .horizontal
			)
		}
		retryButton.target = self
		retryButton.action = #selector(retry)
		retryButton.setAccessibilityLabel("Retry opening chat")
		retryButton.toolTip = "Try opening this chat again"
		forkButton.target = self
		forkButton.action = #selector(fork)
		forkButton.setAccessibilityLabel("Fork locked chat")
		forkButton.isEnabled = false

		let items: [NSView] = [lockIcon, message, divider, retryButton, forkButton]
		for item in items
		{
			item.translatesAutoresizingMaskIntoConstraints = false
			addSubview(item)
		}
		NSLayoutConstraint.activate([
			heightAnchor.constraint(greaterThanOrEqualToConstant: LayoutTokens.ChatLock.height),
			lockIcon.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: LayoutTokens.ChatLock.leadingInset
			),
			lockIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
			lockIcon.widthAnchor.constraint(equalToConstant: LayoutTokens.ChatLock.iconWidth),
			lockIcon.heightAnchor.constraint(equalToConstant: LayoutTokens.ChatLock.iconHeight),
			message.leadingAnchor.constraint(
				equalTo: lockIcon.trailingAnchor,
				constant: LayoutTokens.ChatLock.iconTextSpacing
			),
			message.centerYAnchor.constraint(equalTo: centerYAnchor),
			message.topAnchor.constraint(
				greaterThanOrEqualTo: topAnchor,
				constant: LayoutTokens.ChatLock.verticalInset
			),
			message.bottomAnchor.constraint(
				lessThanOrEqualTo: bottomAnchor,
				constant: -LayoutTokens.ChatLock.verticalInset
			),
			message.trailingAnchor.constraint(
				lessThanOrEqualTo: divider.leadingAnchor,
				constant: -LayoutTokens.ChatLock.textActionSpacing
			),
			divider.trailingAnchor.constraint(
				equalTo: retryButton.leadingAnchor,
				constant: -LayoutTokens.ChatLock
					.dividerActionSpacing
			),
			divider.centerYAnchor.constraint(equalTo: centerYAnchor),
			divider.widthAnchor.constraint(equalToConstant: LayoutTokens.ChatLock.dividerWidth),
			divider.heightAnchor.constraint(equalToConstant: LayoutTokens.ChatLock.actionHeight),
			retryButton.centerYAnchor.constraint(equalTo: centerYAnchor),
			retryButton.heightAnchor
				.constraint(equalToConstant: LayoutTokens.ChatLock.actionHeight),
			retryButton.widthAnchor.constraint(greaterThanOrEqualToConstant:
				LayoutTokens.ChatLock.retryMinimumWidth),
			retryButton.trailingAnchor.constraint(
				equalTo: forkButton.leadingAnchor,
				constant: -LayoutTokens.ChatLock.actionSpacing
			),
			forkButton.centerYAnchor.constraint(equalTo: centerYAnchor),
			forkButton.heightAnchor.constraint(equalToConstant: LayoutTokens.ChatLock.actionHeight),
			forkButton.widthAnchor.constraint(greaterThanOrEqualToConstant:
				LayoutTokens.ChatLock.forkMinimumWidth),
			forkButton.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -LayoutTokens.ChatLock.trailingInset
			),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	@objc private func retry()
	{
		onRetry?()
	}

	@objc private func fork()
	{
		onFork?()
	}
}

/// Draws the reference 18-point lock artwork with native appearance colors.
@MainActor
private final class ConversationLockIconView: NSView
{
	override var isOpaque: Bool
	{
		false
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		AppKitColorTokens.primaryText.setStroke()
		let body = NSBezierPath(
			roundedRect: NSRect(
				x: 3.2,
				y: 3,
				width: 11.6,
				height: 8.8
			),
			xRadius: 2.25,
			yRadius: 2.25
		)
		body.lineWidth = 1.33
		body.stroke()

		let shackle = NSBezierPath()
		shackle.move(to: NSPoint(
			x: 5.3,
			y: 11.7
		))
		shackle.line(to: NSPoint(
			x: 5.3,
			y: 12
		))
		shackle.curve(
			to: NSPoint(
				x: 9,
				y: 15.7
			),
			controlPoint1: NSPoint(
				x: 5.3,
				y: 14.0435
			),
			controlPoint2: NSPoint(
				x: 6.9566,
				y: 15.7
			)
		)
		shackle.curve(
			to: NSPoint(
				x: 12.7,
				y: 12
			),
			controlPoint1: NSPoint(
				x: 11.0435,
				y: 15.7
			),
			controlPoint2: NSPoint(
				x: 12.7,
				y: 14.0435
			)
		)
		shackle.line(to: NSPoint(
			x: 12.7,
			y: 11.7
		))
		shackle.lineWidth = 1.33
		shackle.lineJoinStyle = .round
		shackle.stroke()

		let keyhole = NSBezierPath()
		keyhole.move(to: NSPoint(
			x: 8.5,
			y: 7.5
		))
		keyhole.line(to: NSPoint(
			x: 9.5,
			y: 7.5
		))
		keyhole.lineWidth = 1.33
		keyhole.lineCapStyle = .round
		keyhole.stroke()
	}
}
