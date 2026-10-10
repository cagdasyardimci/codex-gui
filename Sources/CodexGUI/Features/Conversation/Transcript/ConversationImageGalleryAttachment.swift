import AppKit

/// One Markdown image paragraph, or consecutive image-only paragraphs, in the answer body.
@MainActor
final class ConversationImageGalleryAttachment: NSTextAttachment
{
	let paths: [String]
	let estimatedRichImageBytes: Int

	static func make(
		paths: [String],
		source: String,
		thumbnails: [String: SourceThumbnailLoader.Thumbnail],
		budget: inout ConversationRichBlockBudget
	) -> NSTextAttachment
	{
		let pixels = paths.reduce(0)
		{
			$0 + (thumbnails[$1].map
			{
				$0.image.width * $0.image.height
			} ?? 0)
		}
		guard !paths.isEmpty, paths.count <= 32, paths.allSatisfy(
			{
				thumbnails[$0] != nil
			}
		), budget.beginBlock(), budget.reservePixels(pixels)
		else
		{
			return ConversationRichAttachment(
				source: source,
				lightImage: nil,
				darkImage: nil
			)
		}
		let images = paths.compactMap
		{
			path in
			thumbnails[path].map
			{
				NSImage(
					cgImage: $0.image,
					size: NSSize(
						width: $0.image.width,
						height: $0.image.height
					)
				)
			}
		}
		return ConversationImageGalleryAttachment(
			paths: paths,
			images: images,
			originalSizes: paths.compactMap
			{
				thumbnails[$0]?.originalPixelSize
			},
			pixelCount: pixels
		)
	}

	private init(
		paths: [String],
		images: [NSImage],
		originalSizes: [CGSize],
		pixelCount: Int
	)
	{
		self.paths = paths
		estimatedRichImageBytes = pixelCount * 4
		super.init(
			data: nil,
			ofType: nil
		)
		allowsTextAttachmentView = false
		attachmentCell = ConversationImageGalleryCell(
			images: images,
			originalSizes: originalSizes
		)
	}

	func path(
		at point: NSPoint,
		in cellFrame: NSRect
	) -> String?
	{
		(attachmentCell as? ConversationImageGalleryCell)?.imageIndex(
			at: point,
			in: cellFrame
		).flatMap
		{
			paths.indices.contains($0) ? paths[$0] : nil
		}
	}

	required init?(coder: NSCoder)
	{
		return nil
	}
}

@MainActor
private final class ConversationImageGalleryCell: NSTextAttachmentCell
{
	private static let maximumImageWidth: CGFloat = 425
	private static let maximumImageHeight: CGFloat = 160
	private static let gap: CGFloat = 12
	private static let verticalPadding: CGFloat = 4
	private let images: [NSImage]
	private let originalSizes: [CGSize]

	init(
		images: [NSImage],
		originalSizes: [CGSize]
	)
	{
		self.images = images
		self.originalSizes = originalSizes
		super.init(textCell: "")
	}

	required init(coder: NSCoder)
	{
		fatalError("Conversation image galleries are prepared from Markdown source")
	}

	nonisolated override func cellSize() -> NSSize
	{
		NSSize(
			width: 1454,
			height: 640
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
		let availableWidth = max(
			1,
			min(
				textContainer.size.width - textContainer.lineFragmentPadding * 2,
				lineFragment.maxX - position.x
			)
		)
		return MainActor.assumeIsolated
		{
			NSRect(
				origin: .zero,
				size: fittedSize(width: availableWidth)
			)
		}
	}

	private func fittedSize(width: CGFloat) -> NSSize
	{
		let frames = imageFrames(width: width)
		return NSSize(
			width: width,
			height: ceil((frames.map(\.maxY).max() ?? 0) + Self.verticalPadding * 2)
		)
	}

	private func imageFrames(width: CGFloat) -> [NSRect]
	{
		var frames: [NSRect] = []
		var rowTop: CGFloat = 0
		var rowWidth: CGFloat = 0
		var rowHeight: CGFloat = 0
		for originalSize in originalSizes
		{
			let scale = min(
				1,
				Self.maximumImageWidth / max(
					1,
					originalSize.width
				),
				Self.maximumImageHeight / max(
					1,
					originalSize.height
				),
				width / max(
					1,
					originalSize.width
				)
			)
			let size = NSSize(
				width: max(
					1,
					originalSize.width * scale
				),
				height: max(
					1,
					originalSize.height * scale
				)
			)
			if rowWidth > 0 && rowWidth + Self.gap + size.width > width
			{
				rowTop += rowHeight + Self.gap
				rowWidth = 0
				rowHeight = 0
			}
			let originX = rowWidth > 0 ? rowWidth + Self.gap : 0
			frames.append(NSRect(
				x: originX,
				y: rowTop,
				width: size.width,
				height: size.height
			))
			rowWidth = originX + size.width
			rowHeight = max(
				rowHeight,
				size.height
			)
		}
		return frames
	}

	func imageIndex(
		at point: NSPoint,
		in cellFrame: NSRect
	) -> Int?
	{
		imageFrames(width: cellFrame.width).firstIndex
		{
			frame in
			NSRect(
				x: cellFrame.minX + frame.minX,
				y: cellFrame.minY + Self.verticalPadding + frame.minY,
				width: frame.width,
				height: frame.height
			).contains(point)
		}
	}

	override func draw(
		withFrame cellFrame: NSRect,
		in controlView: NSView?
	)
	{
		drawImages(in: cellFrame)
	}

	override func draw(
		withFrame cellFrame: NSRect,
		in controlView: NSView?,
		characterIndex: Int
	)
	{
		drawImages(in: cellFrame)
	}

	override func draw(
		withFrame cellFrame: NSRect,
		in controlView: NSView?,
		characterIndex: Int,
		layoutManager: NSLayoutManager
	)
	{
		drawImages(in: cellFrame)
	}

	private func drawImages(in cellFrame: NSRect)
	{
		let frames = imageFrames(width: cellFrame.width)
		for (image, frame) in zip(
			images,
			frames
		)
		{
			let destination = NSRect(
				x: cellFrame.minX + frame.minX,
				y: cellFrame.minY + Self.verticalPadding + frame.minY,
				width: frame.width,
				height: frame.height
			)
			NSGraphicsContext.saveGraphicsState()
			let outline = NSBezierPath(
				roundedRect: destination,
				xRadius: 8,
				yRadius: 8
			)
			outline.addClip()
			image.draw(in: destination)
			NSGraphicsContext.restoreGraphicsState()
			NSColor.separatorColor.setStroke()
			outline.lineWidth = 0.5
			outline.stroke()
		}
	}
}
