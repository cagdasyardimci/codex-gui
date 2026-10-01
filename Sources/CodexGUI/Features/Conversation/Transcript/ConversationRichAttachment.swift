import AppKit

/// One source-backed glyph whose native drawing adapts to width and current appearance.
@MainActor
final class ConversationRichAttachment: NSTextAttachment
{
	let source: String
	let estimatedRichImageBytes: Int
	var rendersNativeImage: Bool
	{
		estimatedRichImageBytes > 0
	}

	init(
		source: String,
		lightImage: NSImage?,
		darkImage: NSImage?
	)
	{
		self.source = source
		let hasBothImages = lightImage != nil && darkImage != nil
		let acceptedLightImage = hasBothImages ? lightImage : nil
		let acceptedDarkImage = hasBothImages ? darkImage : nil
		estimatedRichImageBytes = [acceptedLightImage, acceptedDarkImage].compactMap
		{
			$0
		}
		.reduce(0)
		{
			total, image in
			total + ConversationRichBlockBudget.estimatedPixels(for: image.size) * 4
		}
		super.init(
			data: nil,
			ofType: nil
		)
		allowsTextAttachmentView = false
		// A fixed attachment.image bypasses native cell sizing and clips narrow paragraphs.
		attachmentCell = ConversationRichAttachmentCell(
			source: source,
			lightImage: acceptedLightImage,
			darkImage: acceptedDarkImage
		)
		lightImage?.accessibilityDescription = source
		darkImage?.accessibilityDescription = source
	}

	required init?(coder: NSCoder)
	{
		return nil
	}
}

@MainActor
private final class ConversationRichAttachmentCell: NSTextAttachmentCell
{
	private static let verticalPadding: CGFloat = 8
	private let lightImage: NSImage?
	private let darkImage: NSImage?
	private let fallback: NSAttributedString
	nonisolated private let naturalSize: NSSize

	init(
		source: String,
		lightImage: NSImage?,
		darkImage: NSImage?
	)
	{
		self.lightImage = lightImage
		self.darkImage = darkImage
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byCharWrapping
		paragraph.lineSpacing = 2
		fallback = NSAttributedString(
			string: source,
			attributes: [
				.font: NSFont.monospacedSystemFont(
					ofSize: 13,
					weight: .regular
				),
				.foregroundColor: NSColor.labelColor,
				.paragraphStyle: paragraph,
			]
		)
		let imageSize = lightImage?.size ?? darkImage?.size
		if let imageSize
		{
			naturalSize = NSSize(
				width: imageSize.width,
				height: imageSize.height + Self.verticalPadding * 2
			)
		}
		else
		{
			let size = fallback.boundingRect(
				with: NSSize(
					width: 520,
					height: CGFloat.greatestFiniteMagnitude
				),
				options: [.usesLineFragmentOrigin, .usesFontLeading]
			).size
			naturalSize = NSSize(
				width: 520,
				height: ceil(size.height) + Self.verticalPadding * 2
			)
		}
		super.init(textCell: "")
	}

	required init(coder: NSCoder)
	{
		fatalError("Conversation rich attachments are prepared from Markdown source")
	}

	nonisolated override func cellSize() -> NSSize
	{
		naturalSize
	}

	nonisolated override func cellFrame(
		for textContainer: NSTextContainer,
		proposedLineFragment lineFragment: NSRect,
		glyphPosition position: NSPoint,
		characterIndex: Int
	) -> NSRect
	{
		// The transcript creates, measures and displays its TextKit layout on the main actor.
		precondition(Thread.isMainThread)
		let containerWidth = textContainer.size.width - textContainer.lineFragmentPadding * 2
		let storage = textContainer.layoutManager?.textStorage
		let paragraph = storage.flatMap
		{
			storage in
			characterIndex < storage.length
				? storage.attribute(
					.paragraphStyle,
					at: characterIndex,
					effectiveRange: nil
				)
				as? NSParagraphStyle : nil
		}
		let tailIndent = paragraph?.tailIndent ?? 0
		let contentEnd = tailIndent <= 0
			? lineFragment.maxX + tailIndent
			: min(
				lineFragment.maxX,
				lineFragment.minX + tailIndent
			)
		let remainingWidth = contentEnd - position.x
		let width = max(
			1,
			min(
				containerWidth,
				remainingWidth
			)
		)
		return MainActor.assumeIsolated
		{
			NSRect(
				origin: .zero,
				size: fittedSize(width: width)
			)
		}
	}

	private func fittedSize(width: CGFloat) -> NSSize
	{
		let height: CGFloat
		if let size = lightImage?.size ?? darkImage?.size
		{
			let scale = min(
				1,
				width / size.width
			)
			height = ceil(size.height * scale) + Self.verticalPadding * 2
		}
		else
		{
			height = ceil(fallback.boundingRect(
				with: NSSize(
					width: width,
					height: CGFloat.greatestFiniteMagnitude
				),
				options: [.usesLineFragmentOrigin, .usesFontLeading]
			).height) + Self.verticalPadding * 2
		}
		return NSSize(
			width: width,
			height: height
		)
	}

	override func draw(
		withFrame cellFrame: NSRect,
		in controlView: NSView?
	)
	{
		drawContent(
			withFrame: cellFrame,
			in: controlView
		)
	}

	override func draw(
		withFrame cellFrame: NSRect,
		in controlView: NSView?,
		characterIndex: Int
	)
	{
		drawContent(
			withFrame: cellFrame,
			in: controlView
		)
	}

	override func draw(
		withFrame cellFrame: NSRect,
		in controlView: NSView?,
		characterIndex: Int,
		layoutManager: NSLayoutManager
	)
	{
		drawContent(
			withFrame: cellFrame,
			in: controlView
		)
	}

	private func drawContent(
		withFrame cellFrame: NSRect,
		in controlView: NSView?
	)
	{
		let appearance = controlView?.effectiveAppearance ?? NSAppearance.currentDrawing()
		let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		let image = dark ? darkImage : lightImage
		guard let image
		else
		{
			fallback.draw(in: cellFrame.insetBy(
				dx: 0,
				dy: Self.verticalPadding
			))
			return
		}
		let scale = min(
			1,
			cellFrame.width / image.size.width
		)
		let size = NSSize(
			width: image.size.width * scale,
			height: image.size.height * scale
		)
		let frame = NSRect(
			x: cellFrame.midX - size.width / 2,
			y: cellFrame.midY - size.height / 2,
			width: size.width,
			height: size.height
		)
		image.draw(
			in: frame,
			from: .zero,
			operation: .sourceOver,
			fraction: 1,
			respectFlipped: true,
			hints: nil
		)
	}
}
