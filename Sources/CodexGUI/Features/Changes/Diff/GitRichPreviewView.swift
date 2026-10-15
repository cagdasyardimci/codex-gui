import AppKit
import PDFKit

enum GitRichPreviewKind
{
	case markdown, image, pdf

	init?(path: String)
	{
		switch URL(fileURLWithPath: path).pathExtension.lowercased()
		{
		case "md", "markdown": self = .markdown
		case "png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp", "heic", "webp", "svg":
			self = .image
		case "pdf": self = .pdf
		default: return nil
		}
	}
}

/// Inline read-only content. Markdown expands inside the comparison's outer scroll view.
@MainActor
final class GitRichPreviewView: NSView
{
	private var task: Task<Void, Never>?
	private var content: NSView?
	private var markdownRuns: [ConversationTextRun]?
	private lazy var contentHeight = heightAnchor.constraint(equalToConstant: 80)

	init(
		kind: GitRichPreviewKind,
		loadContent: @escaping @Sendable () async throws -> Data
	)
	{
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
				let runs: [ConversationTextRun]?
				if case .markdown = kind
				{
					guard let source = String(
						data: data,
						encoding: .utf8
					)
					else
					{
						throw GitComparisonFailure.unsupportedTextEncoding
					}
					runs = await Task.detached
					{
						ConversationContentParser.parse(
							source,
							markdown: true
						).runs
					}.value
				}
				else
				{
					runs = nil
				}
				guard !Task.isCancelled
				else
				{
					return
				}
				self?.display(
					data,
					kind: kind,
					runs: runs
				)
			}
			catch
			{
				guard !Task.isCancelled
				else
				{
					return
				}
				self?.showMessage("Rich preview unavailable. Refresh the comparison and retry.")
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
		install(NSTextField(wrappingLabelWithString: message))
	}

	private func display(
		_ data: Data,
		kind: GitRichPreviewKind,
		runs: [ConversationTextRun]?
	)
	{
		switch kind
		{
		case .markdown:
			let storage = NSTextStorage()
			let layout = ConversationMarkdownLayoutManager()
			let container = NSTextContainer(containerSize: NSSize(
				width: 1,
				height: CGFloat.greatestFiniteMagnitude
			))
			container.widthTracksTextView = false
			layout.addTextContainer(container)
			storage.addLayoutManager(layout)
			let text = ConversationMarkdownTextView(
				frame: .zero,
				textContainer: container
			)
			text.isEditable = false
			text.isVerticallyResizable = false
			text.drawsBackground = false
			text.textContainerInset = NSSize(
				width: 20,
				height: 20
			)
			markdownRuns = runs
			install(text)
			refreshMarkdownAppearance()
		case .image:
			guard let image = NSImage(data: data)
			else
			{
				showMessage("This image cannot be rendered as a rich preview."); return
			}
			let view = NSImageView(image: image)
			view.imageScaling = .scaleProportionallyUpOrDown
			install(view)
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

	override func layout()
	{
		super.layout()
		guard let content
		else
		{
			return
		}
		if let text = content as? ConversationMarkdownTextView,
			let container = text.textContainer, let layout = text.layoutManager
		{
			container.containerSize = NSSize(
				width: max(
					1,
					bounds.width - 40
				),
				height: CGFloat.greatestFiniteMagnitude
			)
			layout.ensureLayout(for: container)
			let height = ceil(layout.usedRect(for: container).maxY) + 40
			if contentHeight.constant != height
			{
				contentHeight.constant = height
			}
			text.frame = NSRect(
				x: 0,
				y: 0,
				width: bounds.width,
				height: height
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
			content.frame = content is PDFView ? bounds : bounds.insetBy(
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
		guard let text = content as? ConversationMarkdownTextView, let markdownRuns
		else
		{
			return
		}
		let selection = text.selectedRange()
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			text.textStorage?.setAttributedString(
				ConversationAttributedStringRenderer.render(markdownRuns)
			)
		}
		text.setSelectedRange(selection)
		text.updateSourceAccessibilityHelp()
		needsLayout = true
	}
}
