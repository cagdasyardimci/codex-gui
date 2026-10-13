import AppKit

/// Native actions for the latest terminal reply, using the exact source and current bookmark state.
@MainActor
final class ConversationReplyActionsView: NSStackView
{
	static let height: CGFloat = 20
	private let copyButton = NSButton()
	private let bookmarkButton = NSButton()
	private var source: String?
	private var onToggleBookmark: (() -> Void)?

	init()
	{
		super.init(frame: .zero)
		orientation = .horizontal
		alignment = .centerY
		spacing = 6
		translatesAutoresizingMaskIntoConstraints = false
		heightAnchor.constraint(equalToConstant: Self.height).isActive = true
		for button in [copyButton, bookmarkButton]
		{
			AppKitControlStyling.styleButton(button)
			button.imagePosition = .imageOnly
			button.translatesAutoresizingMaskIntoConstraints = false
			button.widthAnchor.constraint(equalToConstant: Self.height).isActive = true
			button.heightAnchor.constraint(equalToConstant: Self.height).isActive = true
			addArrangedSubview(button)
		}
		copyButton.image = DesktopIcons.image(
			.copy,
			size: 13,
			accessibilityDescription: "Copy response"
		)
		copyButton.toolTip = "Copy response"
		copyButton.setAccessibilityLabel("Copy response")
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
		onToggleBookmark: (() -> Void)?
	)
	{
		self.source = source
		self.onToggleBookmark = onToggleBookmark
		isHidden = false
		copyButton.isEnabled = true
		copyButton.target = self
		copyButton.action = #selector(copyResponse)
		bookmarkButton.isHidden = onToggleBookmark == nil
		bookmarkButton.isEnabled = onToggleBookmark != nil
		bookmarkButton.target = onToggleBookmark == nil ? nil : self
		bookmarkButton.action = onToggleBookmark == nil ? nil : #selector(toggleBookmark)
		setBookmarked(bookmarked)
	}

	func setBookmarked(_ bookmarked: Bool)
	{
		let label = bookmarked ? "Remove turn bookmark" : "Bookmark turn"
		bookmarkButton.image = NSImage(
			systemSymbolName: bookmarked ? "bookmark.fill" : "bookmark",
			accessibilityDescription: label
		)
		bookmarkButton.toolTip = label
		bookmarkButton.setAccessibilityLabel(label)
	}

	func reset()
	{
		source = nil
		onToggleBookmark = nil
		isHidden = true
		for button in [copyButton, bookmarkButton]
		{
			button.isEnabled = false
			button.target = nil
			button.action = nil
		}
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

	@objc private func toggleBookmark()
	{
		onToggleBookmark?()
	}

	/// Earlier replies keep their existing height; only the newest terminal turn adds a row.
	static func replyEntryID(
		in entries: [ConversationEntry],
		timings: [ConversationTurnTiming]
	) -> String?
	{
		guard let latest = entries.last(where:
			{
				$0.kind != .notice
			}),
			let identity = ConversationEntryIdentity(latest.id)
		else
		{
			return nil
		}
		let turnID = identity.turnID
		guard timings.contains(where:
			{
				$0.turnID == turnID
					&& ["completed", "failed", "interrupted", "stopped", "cancelled"]
					.contains($0.status)
			})
		else
		{
			return nil
		}
		return entries.last(where:
			{
				$0.kind == .agent && $0.id.hasPrefix(turnID + ":")
					&& !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			})?.id
	}
}
