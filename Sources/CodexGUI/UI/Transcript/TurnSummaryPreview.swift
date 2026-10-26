import AppKit
import QuartzCore

@MainActor
final class TurnSummaryPreview: DesktopHoverPreviewSurface
{
	static let cardWidth = DesktopHoverPreviewSurface.preferredWidth
	private static let inset = DesktopHoverPreviewSurface.contentInset
	private static let minimumHeaderHeight: CGFloat = 18
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
	private var currentSummary: ConversationTurnSummary?
	private var headerHeight: NSLayoutConstraint!
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
		title.maximumNumberOfLines = 2
		title.lineBreakMode = .byCharWrapping
		title.cell?.wraps = true
		title.cell?.isScrollable = false
		title.isSelectable = true
		title.allowsEditingTextAttributes = true
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
		header.alignment = .top
		reply.font = .systemFont(ofSize: 13)
		reply.textColor = .secondaryLabelColor
		reply.isSelectable = true
		reply.allowsEditingTextAttributes = true
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
		installContent(stack)
		headerHeight = header.heightAnchor.constraint(equalToConstant: Self.minimumHeaderHeight)
		headerHeight.isActive = true
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
		if let currentSummary
		{
			render(currentSummary)
		}
		needsDisplay = true
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		loadWebLinkFavicons()
	}

	private func loadWebLinkFavicons()
	{
		WebLinkFaviconAttachment.load(
			in: title.attributedStringValue,
			invalidate: title
		)
		WebLinkFaviconAttachment.load(
			in: reply.attributedStringValue,
			invalidate: reply
		)
	}

	private func refreshSkeletonColors()
	{
		let color = AppKitColorResolution.resolvedCGColor(
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
		currentSummary = summary
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
		let titleFont = title.font ?? NSFont.systemFont(ofSize: 13)
		let titleParagraph = NSMutableParagraphStyle()
		titleParagraph.lineBreakMode = .byCharWrapping
		let titleAttributes: [NSAttributedString.Key: Any] = [
			.font: titleFont,
			.foregroundColor: NSColor.labelColor,
			.paragraphStyle: titleParagraph,
		]
		title.attributedStringValue = TurnSummaryLinkPresentation.styledTitle(
			summary.title,
			attributes: titleAttributes
		)
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineSpacing = 4
		paragraph.lineBreakMode = .byWordWrapping
		let attributes: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: 13),
			.foregroundColor: NSColor.secondaryLabelColor,
			.paragraphStyle: paragraph,
		]
		let width = Self.cardWidth - 2 * Self.inset
		let titleWidth = width - 18 - Self.contentSpacing
		let titleLineHeight = ceil(NSLayoutManager().defaultLineHeight(for: titleFont))
		let measuredTitleHeight = ceil(title.attributedStringValue.boundingRect(
			with: NSSize(
				width: titleWidth,
				height: 10000
			),
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		).height)
		headerHeight.constant = max(
			Self.minimumHeaderHeight,
			min(
				measuredTitleHeight,
				2 * titleLineHeight
			)
		)
		let styledReply = TurnSummaryLinkPresentation.styled(
			summary.reply,
			source: summary.replySource,
			attributes: attributes
		)
		let compactReply = TurnSummaryLinkPresentation.compactLines(styledReply)
		let text: NSAttributedString = summary.previewError.map
		{
			NSAttributedString(
				string: $0,
				attributes: attributes
			)
		} ?? (compactReply.length == 0
			? NSAttributedString(
				string: "Waiting for a reply…",
				attributes: attributes
			)
			: compactReply)
		func measuredHeight(_ value: NSAttributedString) -> CGFloat
		{
			value.boundingRect(
				with: NSSize(
					width: width,
					height: 10000
				),
				options: [.usesLineFragmentOrigin, .usesFontLeading]
			).height
		}
		let display = truncatedReply(
			text,
			attributes: attributes,
			measuredHeight: measuredHeight
		)
		let height = max(
			Self.minimumReplyHeight,
			ceil(measuredHeight(display))
		)
		reply.attributedStringValue = display
		loadWebLinkFavicons()
		replyHeight.constant = height
		cardHeight = 2 * Self.inset + headerHeight.constant + Self.contentSpacing + height
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
		_ text: NSAttributedString,
		attributes: [NSAttributedString.Key: Any],
		measuredHeight: (NSAttributedString) -> CGFloat
	) -> NSAttributedString
	{
		var display = text
		if measuredHeight(display) > Self.maximumReplyHeight
		{
			let characters = Array(text.string)
			var lower = 0
			var upper = characters.count
			func candidate(_ count: Int) -> NSAttributedString
			{
				let prefix = String(characters.prefix(count))
					.trimmingCharacters(in: .whitespacesAndNewlines)
				let result = NSMutableAttributedString(attributedString: text.attributedSubstring(
					from: NSRange(
						location: 0,
						length: prefix.utf16.count
					)
				))
				result.append(NSAttributedString(
					string: "…",
					attributes: attributes
				))
				return result
			}
			while lower < upper
			{
				let middle = (lower + upper + 1) / 2
				if measuredHeight(candidate(middle)) <= Self.maximumReplyHeight
				{
					lower = middle
				}
				else
				{
					upper = middle - 1
				}
			}
			display = candidate(lower)
		}
		return display
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
		_ = DesktopHoverTracking.replace(
			in: self,
			previous: nil,
			options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
		)
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
