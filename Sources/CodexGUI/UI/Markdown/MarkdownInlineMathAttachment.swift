import AppKit

/// A formula occupies its natural inline width and places its TeX baseline on the text baseline.
@MainActor
final class MarkdownInlineMathAttachment: NSTextAttachment
{
	let source: String
	let estimatedRichImageBytes: Int
	var rendersNativeImage: Bool
	{
		estimatedRichImageBytes > 0
	}

	init(
		latex: String,
		source: String,
		font: NSFont,
		budget: inout MarkdownRichBlockBudget
	)
	{
		self.source = source
		let images = MarkdownRichBlockRenderer.mathImages(
			latex: latex,
			budget: &budget,
			fontSize: font.pointSize,
			inline: true
		)
		estimatedRichImageBytes = images?.byteCount ?? 0
		super.init(
			data: nil,
			ofType: nil
		)
		allowsTextAttachmentView = false
		attachmentCell = MarkdownInlineMathAttachmentCell(
			images: images,
			source: source,
			font: font
		)
	}

	required init?(coder: NSCoder)
	{
		return nil
	}
}

@MainActor
private final class MarkdownInlineMathAttachmentCell: NSTextAttachmentCell
{
	private let lightImage: NSImage?
	private let darkImage: NSImage?
	private let fallback: NSAttributedString
	nonisolated private let naturalSize: NSSize
	nonisolated private let descent: CGFloat

	init(
		images: MarkdownRichBlockImageCache.Images?,
		source: String,
		font: NSFont
	)
	{
		lightImage = images?.light
		darkImage = images?.dark
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byCharWrapping
		fallback = NSAttributedString(
			string: source,
			attributes: [
				.font: font,
				.foregroundColor: NSColor.labelColor,
				.paragraphStyle: paragraph,
			]
		)
		naturalSize = images?.lightSize ?? fallback.boundingRect(
			with: NSSize(
				width: 520,
				height: CGFloat.greatestFiniteMagnitude
			),
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		).size
		descent = images?.baselineDescent ?? -font.descender
		super.init(textCell: "")
	}

	required init(coder: NSCoder)
	{
		fatalError("Inline math attachments are prepared from Markdown source")
	}

	nonisolated override func cellSize() -> NSSize
	{
		naturalSize
	}

	nonisolated override func cellBaselineOffset() -> NSPoint
	{
		NSPoint(
			x: 0,
			y: -descent
		)
	}

	nonisolated override func cellFrame(
		for textContainer: NSTextContainer,
		proposedLineFragment lineFragment: NSRect,
		glyphPosition position: NSPoint,
		characterIndex: Int
	) -> NSRect
	{
		precondition(Thread.isMainThread)
		return MainActor.assumeIsolated
		{
			let width = max(
				1,
				min(
					naturalSize.width,
					lineFragment.width
				)
			)
			if lightImage != nil
			{
				let scale = width / max(
					1,
					naturalSize.width
				)
				return NSRect(
					x: 0,
					y: -descent * scale,
					width: width,
					height: naturalSize.height * scale
				)
			}
			let size = fallback.boundingRect(
				with: NSSize(
					width: width,
					height: CGFloat.greatestFiniteMagnitude
				),
				options: [.usesLineFragmentOrigin, .usesFontLeading]
			).size
			return NSRect(
				x: 0,
				y: -descent,
				width: width,
				height: ceil(size.height)
			)
		}
	}

	override func draw(
		withFrame cellFrame: NSRect,
		in controlView: NSView?
	)
	{
		drawContent(
			frame: cellFrame,
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
			frame: cellFrame,
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
			frame: cellFrame,
			in: controlView
		)
	}

	private func drawContent(
		frame: NSRect,
		in controlView: NSView?
	)
	{
		let appearance = controlView?.effectiveAppearance ?? NSAppearance.currentDrawing()
		let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		if let image = dark ? darkImage : lightImage
		{
			image.draw(
				in: frame,
				from: .zero,
				operation: .sourceOver,
				fraction: 1,
				respectFlipped: true,
				hints: nil
			)
		}
		else
		{
			fallback.draw(in: frame)
		}
	}
}
