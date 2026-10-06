import AppKit
import QuartzCore

@MainActor
final class TurnSummaryPreview: NSView
{
	static let cardWidth: CGFloat = 320
	private static let inset: CGFloat = 10
	private static let headerHeight: CGFloat = 18
	private static let contentSpacing: CGFloat = 6
	private static let minimumReplyHeight: CGFloat = 18
	private static let maximumReplyHeight: CGFloat = 58
	private static let loadingCardHeight: CGFloat = 100
	var onEnter: (() -> Void)?
	var onExit: (() -> Void)?
	var onBookmark: (() -> Void)?
	private let bookmark = NSButton()
	private let title = NSTextField(labelWithString: "")
	private let reply = NSTextField(wrappingLabelWithString: "")
	private var replyHeight: NSLayoutConstraint!
	private let skeleton = CALayer()
	private(set) var isLoading = false
	private(set) var cardHeight: CGFloat = 0

	init(
		summary: ConversationTurnSummary,
		bookmarked: Bool
	)
	{
		super.init(frame: NSRect(
			x: 0,
			y: 0,
			width: Self.cardWidth,
			height: Self.loadingCardHeight
		))
		wantsLayer = true
		layer?.addSublayer(skeleton)
		for _ in 0 ..< 4
		{
			let bar = CALayer()
			bar.cornerRadius = 3
			skeleton.addSublayer(bar)
		}
		refreshSkeletonColors()
		title.font = .systemFont(
			ofSize: 13,
			weight: .regular
		)
		title.lineBreakMode = .byTruncatingTail
		title.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		bookmark.isBordered = false
		bookmark.target = self
		bookmark.action = #selector(toggleBookmark)
		setBookmarked(bookmarked)
		bookmark.widthAnchor.constraint(equalToConstant: 18).isActive = true
		bookmark.heightAnchor.constraint(equalToConstant: 18).isActive = true
		let header = AppKitLayout.horizontalStack(
			[title, bookmark],
			spacing: Self.contentSpacing
		)
		reply.font = .systemFont(ofSize: 13)
		reply.textColor = .secondaryLabelColor
		reply.maximumNumberOfLines = 3
		reply.lineBreakMode = .byWordWrapping
		reply.cell?.wraps = true
		reply.cell?.isScrollable = false
		replyHeight = reply.heightAnchor.constraint(equalToConstant: Self.minimumReplyHeight)
		replyHeight.isActive = true
		let stack = AppKitLayout.verticalStack(
			[header, reply],
			spacing: Self.contentSpacing
		)
		AppKitLayout.pin(
			stack,
			to: self,
			inset: Self.inset
		)
		header.heightAnchor.constraint(equalToConstant: Self.headerHeight).isActive = true
		header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		reply.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		render(summary)
	}

	@available(
		*,
		unavailable
	)
	required init?(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshSkeletonColors()
		needsDisplay = true
	}

	private func refreshSkeletonColors()
	{
		let color = DesktopTheme.resolvedCGColor(
			.secondaryLabelColor,
			for: self,
			alpha: 0.2
		)
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		for bar in skeleton.sublayers ?? []
		{
			bar.backgroundColor = color
		}
		CATransaction.commit()
	}

	func render(_ summary: ConversationTurnSummary)
	{
		let wasLoading = isLoading
		isLoading = !summary.isContentLoaded && !summary.isPreviewLoaded && summary
			.previewError == nil
		title.isHidden = isLoading
		reply.isHidden = isLoading
		bookmark.isHidden = isLoading
		skeleton.isHidden = !isLoading
		if isLoading
		{
			renderLoadingPreview()
			return
		}
		skeleton.removeAllAnimations()
		setAccessibilityLabel(summary.previewError ?? "Turn preview")
		if wasLoading && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		{
			alphaValue = 0
			NSAnimationContext.runAnimationGroup
			{
				context in
				context.duration = 0.15
				animator().alphaValue = 1
			}
		}
		title.stringValue = summary.title
		let compactReply = summary.reply.components(separatedBy: .newlines).filter
		{
			!$0.trimmingCharacters(in: .whitespaces).isEmpty
		}.joined(separator: "\n")
		let text = summary
			.previewError ?? (compactReply.isEmpty ? "Waiting for a reply…" : compactReply)
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineSpacing = 4
		paragraph.lineBreakMode = .byWordWrapping
		let attributes: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: 13),
			.foregroundColor: NSColor.secondaryLabelColor,
			.paragraphStyle: paragraph,
		]
		let width = Self.cardWidth - 2 * Self.inset
		func measuredHeight(_ value: String) -> CGFloat
		{
			NSAttributedString(
				string: value,
				attributes: attributes
			).boundingRect(
				with: NSSize(
					width: width,
					height: 10000
				),
				options: [.usesLineFragmentOrigin, .usesFontLeading]
			).height
		}
		let display = truncatedReply(
			text,
			measuredHeight: measuredHeight
		)
		let height = max(
			Self.minimumReplyHeight,
			ceil(measuredHeight(display))
		)
		reply.attributedStringValue = NSAttributedString(
			string: display,
			attributes: attributes
		)
		replyHeight.constant = height
		cardHeight = 2 * Self.inset + Self.headerHeight + Self.contentSpacing + height
		setFrameSize(NSSize(
			width: Self.cardWidth,
			height: cardHeight
		))
	}

	private func renderLoadingPreview()
	{
		cardHeight = Self.loadingCardHeight
		setFrameSize(NSSize(
			width: Self.cardWidth,
			height: cardHeight
		))
		skeleton.frame = bounds
		for (index, bar) in (skeleton.sublayers ?? []).enumerated()
		{
			bar.frame = NSRect(
				x: Self.inset,
				y: cardHeight - 24 - CGFloat(index) * 20,
				width: (Self.cardWidth - 2 * Self.inset) *
					[0.6, 1, 0.92, 0.8][index],
				height: 10
			)
		}
		if skeleton.animation(forKey: "loading") == nil,
			!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		{
			let pulse = CABasicAnimation(keyPath: "opacity")
			pulse.fromValue = 0.45
			pulse.toValue = 1
			pulse.duration = 0.7
			pulse.autoreverses = true
			pulse.repeatCount = .infinity
			skeleton.add(
				pulse,
				forKey: "loading"
			)
		}
		setAccessibilityLabel("Loading turn preview")
	}

	private func truncatedReply(
		_ text: String,
		measuredHeight: (String) -> CGFloat
	) -> String
	{
		var display = text
		if measuredHeight(display) > Self.maximumReplyHeight
		{
			let characters = Array(text)
			var lower = 0
			var upper = characters.count
			while lower < upper
			{
				let middle = (lower + upper + 1) / 2
				let candidate = String(characters.prefix(middle))
					.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
				if measuredHeight(candidate) <= Self.maximumReplyHeight
				{
					lower = middle
				}
				else
				{
					upper = middle - 1
				}
			}
			display = String(characters.prefix(lower))
				.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
		}
		return display
	}

	override func draw(_ dirtyRect: NSRect)
	{
		let shape = NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: 0.5,
				dy: 0.5
			),
			xRadius: 10,
			yRadius: 10
		)
		NSColor.controlBackgroundColor.setFill()
		shape.fill()
		NSColor.separatorColor.setStroke()
		shape.lineWidth = 0.5
		shape.stroke()
	}

	func setBookmarked(_ selected: Bool)
	{
		bookmark.image = NSImage(
			systemSymbolName: selected ? "bookmark.fill" : "bookmark",
			accessibilityDescription: selected ? "Remove turn bookmark" :
				"Bookmark turn"
		)
		bookmark.setAccessibilityLabel(selected ? "Remove turn bookmark" : "Bookmark turn")
	}

	@objc private func toggleBookmark()
	{
		onBookmark?()
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		trackingAreas.forEach(removeTrackingArea)
		addTrackingArea(NSTrackingArea(
			rect: .zero,
			options: [
				.mouseEnteredAndExited,
				.activeAlways,
				.inVisibleRect
			],
			owner: self,
			userInfo: nil
		))
	}

	override func mouseEntered(with event: NSEvent)
	{
		onEnter?()
	}
	override func mouseExited(with event: NSEvent)
	{
		onExit?()
	}
}
