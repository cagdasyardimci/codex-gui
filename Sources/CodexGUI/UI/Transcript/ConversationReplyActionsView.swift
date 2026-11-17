import AppKit

/// Shared message actions retain exact copy text and retire playback and menus with their cell.
@MainActor
final class ConversationReplyActionsView: NSStackView
{
	static let height = LayoutTokens.Transcript.replyControlSize
	private var isUserMessage = false
	private let copyButton = DesktopStyledButton(
		title: "",
		presentation: .transcriptAction
	)
	private let editButton = DesktopStyledButton(
		title: "",
		presentation: .transcriptAction
	)
	private let feedbackButton = DesktopStyledButton(
		title: "",
		presentation: .transcriptAction
	)
	private var bookmarked = false
	private let readButton = DesktopStyledButton(
		title: "",
		presentation: .transcriptAction
	)
	private let moreButton = DesktopStyledButton(
		title: "",
		presentation: .transcriptAction
	)
	private let timestampLabel = DesktopTextField(labelWithString: "")
	private var actionGeneration = UUID()
	private(set) var actionMenu: DesktopActionMenu?
	private var onBranch: (() -> Void)?
	private var canBranch: (() -> Bool)?
	private var source: String?
	private var onToggleBookmark: (() -> Void)?

	init()
	{
		super.init(frame: .zero)
		orientation = .horizontal
		alignment = .centerY
		spacing = LayoutTokens.Transcript.replyControlSpacing
		translatesAutoresizingMaskIntoConstraints = false
		heightAnchor.constraint(equalToConstant: Self.height).isActive = true
		for button in [copyButton, editButton, feedbackButton, readButton, moreButton]
		{
			addArrangedSubview(button)
		}
		copyButton.image = DesktopIcons.image(
			.copy,
			size: LayoutTokens.Transcript.replyIconSize,
			accessibilityDescription: "Copy response"
		)
		copyButton.toolTip = "Copy response"
		copyButton.setAccessibilityLabel("Copy response")
		timestampLabel.setTypographyRole(TypographyTokens.Transcript.timestamp)
		timestampLabel.textColor = AppKitColorTokens.secondaryText
		configureIcon(
			readButton,
			icon: .soundOnReadOutLoudSpeaker,
			label: "Read aloud"
		)
		configureIcon(
			moreButton,
			icon: .dotsHorizontalMoreMenu,
			label: "More response actions"
		)
		configureIcon(
			editButton,
			icon: .editPencil,
			label: "Edit message"
		)
		configureIcon(
			feedbackButton,
			icon: .thumbs,
			label: "Give feedback"
		)
		reset()
	}

	@available(
		*,
		unavailable
	)
	required init?(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}

	func configure(
		source: String,
		bookmarked: Bool,
		onToggleBookmark: (() -> Void)?,
		isUserMessage: Bool = false,
		onBranch: (() -> Void)? = nil,
		canBranch: (() -> Bool)? = nil,
		timestamp: Date? = nil
	)
	{
		actionGeneration = UUID()
		actionMenu?.close()
		actionMenu = nil
		timestampLabel.removeFromSuperview()
		for view in arrangedSubviews
		{
			setCustomSpacing(
				spacing,
				after: view
			)
		}
		if let timestamp
		{
			let formatter = DateFormatter()
			formatter.locale = Locale(identifier: "en_US_POSIX")
			formatter.dateFormat = "h:mm a"
			timestampLabel.stringValue = formatter.string(from: timestamp)
			if isUserMessage
			{
				insertArrangedSubview(
					timestampLabel,
					at: 0
				)
				setCustomSpacing(
					LayoutTokens.Transcript.timestampSpacing,
					after: timestampLabel
				)
			}
			else
			{
				addArrangedSubview(timestampLabel)
				setCustomSpacing(
					LayoutTokens.Transcript.timestampSpacing,
					after: moreButton
				)
			}
		}
		self.onBranch = onBranch
		self.canBranch = canBranch
		self.source = source
		self.onToggleBookmark = onToggleBookmark
		isHidden = false
		self.isUserMessage = isUserMessage
		let copyLabel = isUserMessage ? "Copy message" : "Copy response"
		copyButton.toolTip = copyLabel
		copyButton.setAccessibilityLabel(copyLabel)
		editButton.isHidden = !isUserMessage
		editButton.isEnabled = false
		feedbackButton.isHidden = isUserMessage
		feedbackButton.target = self
		feedbackButton.isEnabled = false
		readButton.isHidden = isUserMessage
		readButton.target = self
		readButton.isEnabled = false
		moreButton.isHidden = isUserMessage || (onBranch == nil && onToggleBookmark == nil)
		moreButton.isEnabled = !moreButton.isHidden
		if !isUserMessage, timestamp != nil
		{
			setCustomSpacing(
				LayoutTokens.Transcript.timestampSpacing,
				after: moreButton.isHidden ? readButton : moreButton
			)
		}
		moreButton.target = self
		moreButton.action = #selector(showMore)
		copyButton.isEnabled = true
		copyButton.target = self
		copyButton.action = #selector(copyResponse)

		setBookmarked(bookmarked)
	}

	func setBookmarked(_ bookmarked: Bool)
	{
		self.bookmarked = bookmarked
	}

	func reset()
	{
		actionGeneration = UUID()
		actionMenu?.close()
		actionMenu = nil
		onBranch = nil
		canBranch = nil
		timestampLabel.removeFromSuperview()
		source = nil
		onToggleBookmark = nil
		isHidden = true
		for button in [copyButton, editButton, feedbackButton, readButton, moreButton]
		{
			button.isEnabled = false
			button.target = nil
			button.action = nil
		}
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		if window == nil
		{
			actionMenu?.close()
		}
	}

	override func viewDidHide()
	{
		super.viewDidHide()
		actionMenu?.close()
	}

	private func configureIcon(
		_ button: DesktopStyledButton,
		icon: DesktopIcon,
		label: String
	)
	{
		button.image = DesktopIcons.image(
			icon,
			size: LayoutTokens.Transcript.replyIconSize,
			accessibilityDescription: label
		)
		button.toolTip = label
		button.setAccessibilityLabel(label)
	}

	@objc private func showMore()
	{
		let onBranch = canBranch?() == false ? nil : self.onBranch
		guard onBranch != nil || onToggleBookmark != nil
		else
		{
			return
		}
		let menu = NSMenu()
		if let onBranch
		{
			addMenuAction(
				to: menu,
				title: "Branch in new chat",
				image: DesktopIcons.image(.branch),
				action: onBranch
			)
		}
		if let onToggleBookmark
		{
			let title = bookmarked ? "Remove turn bookmark" : "Bookmark turn"
			addMenuAction(
				to: menu,
				title: title,
				image: DesktopIcons.image(bookmarked ? .savedFilledXs : .savedXs),
				action: onToggleBookmark
			)
		}
		actionMenu?.close()
		actionMenu = DesktopActionMenu(
			menu: menu,
			alignment: .leading,
			opensBelowAnchor: false,
			accessibilityLabel: "Response actions"
		)
		actionMenu?.show(from: moreButton)
	}

	private func addMenuAction(
		to menu: NSMenu,
		title: String,
		image: NSImage,
		action: @escaping () -> Void
	)
	{
		let item = NSMenuItem(
			title: title,
			action: #selector(invokeMenuAction(_:)),
			keyEquivalent: ""
		)
		let generation = actionGeneration
		let captured: () -> Void =
		{
			[weak self] in
			guard self?.actionGeneration == generation
			else
			{
				return
			}
			action()
		}
		item.representedObject = captured
		item.target = self
		item.image = image
		menu.addItem(item)
	}

	@objc private func invokeMenuAction(_ sender: NSMenuItem)
	{
		(sender.representedObject as? (() -> Void))?()
	}

	func writeResponse(to pasteboard: NSPasteboard)
	{
		guard let source
		else
		{
			return
		}
		pasteboard.clearContents()
		pasteboard.setString(
			source,
			forType: .string
		)
	}

	@objc private func copyResponse()
	{
		writeResponse(to: .general)
	}

}
