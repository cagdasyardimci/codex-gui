import AppKit
import PDFKit

private enum RichFilePreviewFailure: Error
{
	case unsupportedTextEncoding
}

typealias RichFileMarkdownImageLoader = @Sendable (
	String,
	Int
) async -> SourceThumbnailLoader.Thumbnail?

enum RichFilePreviewKind
{
	case markdown, image, pdf

	init?(path: String)
	{
		switch FileContentCapabilities(path: path)
		{
		case .markdown: self = .markdown
		case .rasterImage, .svg: self = .image
		case .pdf: self = .pdf
		case .source: return nil
		}
	}
}

/// Read-only native content that measures its height inside an owning outer scroll view.
@MainActor
class RichFilePreviewView: NSView, NSTextViewDelegate
{
	private var task: Task<Void, Never>?
	private var content: NSView?
	private var markdownRuns: [MarkdownTextRun]?
	private var metadataPanel: MarkdownFileMetadataView?
	private var diagramImages: [Data: MarkdownRichBlockImageCache.Images] = [:]
	private let onMetadata: (([MarkdownFileMetadata.Entry]) -> Void)?
	private let matchesFileMarkdownStyling: Bool
	private var imageThumbnails: [String: SourceThumbnailLoader.Thumbnail] = [:]
	private let loadingFailureMessage: String
	private let imageBaseDirectory: URL?
	private let onOpenLink: ((URL) -> Bool)?
	private lazy var contentHeight = heightAnchor.constraint(equalToConstant: 80)
	private static let maximumImagePixelEdge = 2048
	private static let maximumSVGBytes = 32 * 1024 * 1024

	init(
		kind: RichFilePreviewKind,
		loadingFailureMessage: String = "Preview unavailable. Retry.",
		imageBaseDirectory: URL? = nil,
		markdownImageLoader: RichFileMarkdownImageLoader? = nil,
		onOpenLink: ((URL) -> Bool)? = nil,
		onMetadata: (([MarkdownFileMetadata.Entry]) -> Void)? = nil,
		matchesFileMarkdownStyling: Bool = false,
		loadContent: @escaping @Sendable () async throws -> Data
	)
	{
		self.loadingFailureMessage = loadingFailureMessage
		self.imageBaseDirectory = imageBaseDirectory
		self.onOpenLink = onOpenLink
		self.onMetadata = onMetadata
		self.matchesFileMarkdownStyling = matchesFileMarkdownStyling
		super.init(frame: .zero)
		// The mutable height follows measured Markdown or the image's aspect ratio.
		contentHeight.isActive = true
		showMessage("Loading preview…")
		task = Task
		{
			[weak self] in
			do
			{
				let data = try await loadContent()
				guard !Task.isCancelled
				else
				{
					return
				}
				let runs: [MarkdownTextRun]?
				let thumbnail: SourceThumbnailLoader.Thumbnail?
				var imageThumbnails: [String: SourceThumbnailLoader.Thumbnail] = [:]
				var metadata: MarkdownFileMetadata?
				var diagramImages: [Data: MarkdownRichBlockImageCache.Images] = [:]
				if case .markdown = kind
				{
					guard let source = String(
						data: data,
						encoding: .utf8
					)
					else
					{
						throw RichFilePreviewFailure.unsupportedTextEncoding
					}
					let prepared = await Task.detached
					{
						let metadata = MarkdownFileMetadata.parse(source)
						let parsed = MarkdownContentParser.parse(
							metadata?.body ?? source,
							markdown: true,
							preserveSoftBreaks: matchesFileMarkdownStyling,
							imageBaseDirectory: imageBaseDirectory
						)
						return (parsed, metadata)
					}.value
					runs = prepared.0.runs
					metadata = prepared.1
					diagramImages = await MarkdownMermaidRenderer.prepare(parsed: prepared.0)
					if let runs, let markdownImageLoader
					{
						let plan = MarkdownImagePreparation.preloadPlan(in: runs)
						for path in plan.paths
						{
							guard !Task.isCancelled
							else
							{
								return
							}
							imageThumbnails[path] = await markdownImageLoader(
								path,
								plan.maximumPixelSize
							)
						}
					}
					thumbnail = nil
				}
				else if case .image = kind
				{
					thumbnail = await SourceThumbnailLoader.image(
						data: data,
						maximumPixelSize: RichFilePreviewView.maximumImagePixelEdge
					)
					if thumbnail == nil
					{
						guard !Task.isCancelled
						else
						{
							return
						}
						if let image = self?.boundedSVGImage(data), !Task.isCancelled
						{
							self?.installImage(image)
							return
						}
						self?.showMessage("This image cannot be rendered as a rich preview.")
						return
					}
					runs = nil
				}
				else
				{
					runs = nil
					thumbnail = nil
				}
				guard !Task.isCancelled
				else
				{
					return
				}
				self?.display(
					data,
					kind: kind,
					runs: runs,
					thumbnail: thumbnail,
					imageThumbnails: imageThumbnails,
					metadata: metadata,
					diagramImages: diagramImages
				)
			}
			catch
			{
				guard !Task.isCancelled
				else
				{
					return
				}
				if let self
				{
					self.showMessage(self.loadingFailureMessage)
				}
			}
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	deinit
	{
		task?.cancel()
	}

	func cancelLoading()
	{
		task?.cancel()
		task = nil
	}

	func waitForLoading() async
	{
		await task?.value
	}

	private func install(_ view: NSView)
	{
		content?.removeFromSuperview()
		content = view
		addSubview(view)
		needsLayout = true
	}

	private func showMessage(_ message: String)
	{
		contentHeight.constant = 80
		install(ViewerStatusView(message: message))
	}

	private func display(
		_ data: Data,
		kind: RichFilePreviewKind,
		runs: [MarkdownTextRun]?,
		thumbnail: SourceThumbnailLoader.Thumbnail?,
		imageThumbnails: [String: SourceThumbnailLoader.Thumbnail],
		metadata: MarkdownFileMetadata?,
		diagramImages: [Data: MarkdownRichBlockImageCache.Images]
	)
	{
		switch kind
		{
		case .markdown:
			let storage = NSTextStorage()
			let layout = MarkdownLayoutManager()
			let container = NSTextContainer(containerSize: NSSize(
				width: 1,
				height: CGFloat.greatestFiniteMagnitude
			))
			container.widthTracksTextView = false
			layout.addTextContainer(container)
			storage.addLayoutManager(layout)
			let text = MarkdownTextView(
				frame: .zero,
				textContainer: container
			)
			text.isEditable = false
			if onOpenLink != nil
			{
				text.delegate = self
			}
			text.isVerticallyResizable = false
			text.drawsBackground = false
			if matchesFileMarkdownStyling
			{
				container.lineFragmentPadding = 0
			}
			text.textContainerInset = NSSize(
				width: onMetadata == nil ? 20 : 16,
				height: onMetadata == nil ? 20 : 0
			)
			markdownRuns = runs
			self.imageThumbnails = imageThumbnails
			self.diagramImages = diagramImages
			install(text)
			if let onMetadata
			{
				onMetadata(metadata?.entries ?? [])
			}
			else if let metadata
			{
				let panel = MarkdownFileMetadataView(entries: metadata.entries)
				metadataPanel = panel
				addSubview(panel)
			}
			refreshMarkdownAppearance()
		case .image:
			guard let thumbnail
			else
			{
				showMessage("This image cannot be rendered as a rich preview."); return
			}
			let image = NSImage(
				cgImage: thumbnail.image,
				size: thumbnail.originalPixelSize
			)
			installImage(image)
		case .pdf:
			guard let document = PDFDocument(data: data)
			else
			{
				showMessage("This PDF cannot be rendered as a rich preview."); return
			}
			let view = PDFView()
			view.document = document
			view.autoScales = true
			contentHeight.constant = 560
			install(view)
		}
	}

	private func installImage(_ image: NSImage)
	{
		let view = NSImageView(image: image)
		view.imageScaling = .scaleProportionallyUpOrDown
		install(view)
	}

	/// ImageIO does not rasterize SVG on macOS; AppKit can draw it into a fixed bitmap.
	private func boundedSVGImage(_ data: Data) -> NSImage?
	{
		guard !Task.isCancelled, !data.isEmpty, data.count <= Self.maximumSVGBytes
		else
		{
			return nil
		}
		let prefix = String(
			decoding: data.prefix(4096),
			as: UTF8.self
		)
		guard prefix.range(
			of: #"<svg(?:\s|/|>)"#,
			options: [.regularExpression, .caseInsensitive]
		) != nil, let source = NSImage(data: data)
		else
		{
			return nil
		}
		let originalSize = source.size
		guard originalSize.width.isFinite, originalSize.height.isFinite,
				originalSize.width > 0, originalSize.height > 0,
				originalSize.width <= 1_000_000, originalSize.height <= 1_000_000
		else
		{
			return nil
		}
		let scale = min(
			1,
			CGFloat(Self.maximumImagePixelEdge) / max(
				originalSize.width,
				originalSize.height
			)
		)
		let width = max(
			1,
			Int(floor(originalSize.width * scale))
		)
		let height = max(
			1,
			Int(floor(originalSize.height * scale))
		)
		guard !Task.isCancelled, let bitmap = NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: width,
			pixelsHigh: height,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		), let context = NSGraphicsContext(bitmapImageRep: bitmap)
		else
		{
			return nil
		}
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = context
		context.imageInterpolation = .high
		source.draw(in: NSRect(
			x: 0,
			y: 0,
			width: width,
			height: height
		))
		NSGraphicsContext.restoreGraphicsState()
		guard !Task.isCancelled, let pixels = bitmap.cgImage
		else
		{
			return nil
		}
		return NSImage(
			cgImage: pixels,
			size: originalSize
		)
	}

	func textView(
		_ textView: NSTextView,
		clickedOnLink link: Any,
		at charIndex: Int
	) -> Bool
	{
		guard let onOpenLink, textView === content,
				let url = link as? URL ?? (link as? String).flatMap(URL.init(string:))
		else
		{
			return false
		}
		if url.scheme == nil, let imageBaseDirectory,
			let resolved = URL(
			string: url.relativeString,
			relativeTo: imageBaseDirectory
			)?.absoluteURL
		{
			return onOpenLink(resolved)
		}
		return onOpenLink(url)
	}

	override func layout()
	{
		super.layout()
		guard let content
		else
		{
			return
		}
		if let text = content as? MarkdownTextView,
			let container = text.textContainer, let layout = text.layoutManager
		{
			let inset = text.textContainerInset
			let panelHeight = metadataPanel.map
			{
				$0.height(forWidth: max(
					1,
					bounds.width - 32
				)) + 32
			} ?? 0
			container.containerSize = NSSize(
				width: max(
					1,
					bounds.width - inset.width * 2
				),
				height: CGFloat.greatestFiniteMagnitude
			)
			layout.ensureLayout(for: container)
			let textHeight = ceil(layout.usedRect(for: container).maxY) + inset.height * 2
			let height = textHeight + panelHeight
			if contentHeight.constant != height
			{
				contentHeight.constant = height
			}
			text.frame = NSRect(
				x: 0,
				y: isFlipped ? panelHeight : 0,
				width: bounds.width,
				height: textHeight
			)
			metadataPanel?.frame = NSRect(
				x: 16,
				y: isFlipped ? 16 : textHeight + 16,
				width: max(
					1,
					bounds.width - 32
				),
				height: max(
					0,
					panelHeight - 32
				)
			)
		}
		else if let image = (content as? NSImageView)?.image
		{
			let height = min(
				600,
				max(
					100,
					(bounds.width - 40) * image.size.height
						/ max(
							1,
							image.size.width
						) + 40
				)
			)
			if contentHeight.constant != height
			{
				contentHeight.constant = height
			}
			content.frame = NSRect(
				x: 20,
				y: 20,
				width: max(
					1,
					bounds.width - 40
				),
				height: max(
					1,
					height - 40
				)
			)
		}
		else
		{
			content.frame = (content is PDFView || content is ViewerStatusView) ? bounds : bounds
				.insetBy(
					dx: 20,
					dy: 20
				)
		}
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshMarkdownAppearance()
	}

	private func refreshMarkdownAppearance()
	{
		guard let text = content as? MarkdownTextView, let markdownRuns
		else
		{
			return
		}
		let selection = text.selectedRange()
		let mathFontSize: ((MarkdownTextStyle, Bool) -> CGFloat)?
		if matchesFileMarkdownStyling
		{
			mathFontSize =
			{
				style, inline in
				FileMarkdownStyling.mathFontSize(
					style: style,
					inline: inline
				)
			}
		}
		else
		{
			mathFontSize = nil
		}
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			let rendered = MarkdownAttributedStringRenderer.render(
				markdownRuns,
				imageThumbnails: imageThumbnails,
				preparedDiagramImages: diagramImages,
				richBlockMaximumPixels: MarkdownMermaidRenderer.maximumPreparedPixels,
				mathFontSize: mathFontSize
			)
			text.installContent(matchesFileMarkdownStyling ?
				FileMarkdownStyling.apply(to: rendered) : rendered)
		}
		text.setSelectedRange(selection)
		needsLayout = true
	}
}
