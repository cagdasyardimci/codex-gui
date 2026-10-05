import AppKit

@MainActor
final class UserMessageImageAttachmentsView: NSView
{
	static let thumbnailSize: CGFloat = 80
	static let spacing: CGFloat = 8
	private var buttons: [UserMessageImageButton] = []
	private var references: [UserMessageReference] = []
	private var imageTasks: [Task<Void, Never>] = []
	private var generation = 0
	private let inlinePreview = UserMessageInlineImagePreview()

	deinit
	{
		for task in imageTasks
		{
			task.cancel()
		}
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if newWindow == nil
		{
			inlinePreview.dismiss()
		}
		super.viewWillMove(toWindow: newWindow)
	}

	override var isFlipped: Bool
	{
		true
	}

	static func height(
		count: Int,
		width: CGFloat
	) -> CGFloat
	{
		guard count > 0
		else
		{
			return 0
		}
		let columns = columns(width: width)
		let rows = (count + columns - 1) / columns
		return CGFloat(rows) * thumbnailEdge(width: width)
			+ CGFloat(rows - 1) * spacing
	}

	private static func thumbnailEdge(width: CGFloat) -> CGFloat
	{
		min(
			thumbnailSize,
			max(
				1,
				width
			)
		)
	}

	private static func columns(width: CGFloat) -> Int
	{
		max(
			1,
			Int((max(
				1,
				width
			) + spacing) / (thumbnailSize + spacing))
		)
	}

	func configure(_ references: [UserMessageReference])
	{
		guard self.references != references
		else
		{
			return
		}
		generation += 1
		let generation = generation
		inlinePreview.dismiss()
		imageTasks.forEach
		{
			$0.cancel()
		}
		imageTasks.removeAll()
		for button in buttons
		{
			button.target = nil
			button.action = nil
			button.removeFromSuperview()
		}
		buttons.removeAll()
		self.references = references
		isHidden = references.isEmpty
		for (index, reference) in references.enumerated()
		{
			let button = UserMessageImageButton(
				title: "",
				target: self,
				action: #selector(openImage(_:))
			)
			button.isBordered = false
			button.tag = index
			button.toolTip = reference.name
			button.setAccessibilityLabel("Loading attached image: \(reference.name)")
			button.isEnabled = false
			button.beginLoading()
			button.setAccessibilityHelp(InlineImageData.isDataURL(reference.path)
				? "Inline image" : reference.path)
			addSubview(button)
			buttons.append(button)
			let task = Task
			{
				[weak self, weak button] in
				let thumbnail = await SourceThumbnailLoader.image(
					path: reference.path,
					maximumPixelSize: 320
				)
				guard !Task.isCancelled, let self, self.generation == generation, let button
				else
				{
					return
				}
				guard let thumbnail
				else
				{
					button.unavailable = true
					button.isEnabled = false
					button.setAccessibilityLabel("Image unavailable: \(reference.name)")
					return
				}
				let image = NSImage(
					cgImage: thumbnail.image,
					size: NSSize(
						width: thumbnail.image.width,
						height: thumbnail.image.height
					)
				)
				button.preview = image
				button.isEnabled = true
				button.setAccessibilityLabel("Open attached image: \(reference.name)")
			}
			imageTasks.append(task)
		}
		needsLayout = true
	}

	func waitForImages() async
	{
		for task in imageTasks
		{
			await task.value
		}
	}

	func waitForInlinePreview() async
	{
		await inlinePreview.waitForPresentation()
	}

	override func layout()
	{
		super.layout()
		let columns = Self.columns(width: bounds.width)
		let edge = Self.thumbnailEdge(width: bounds.width)
		for (index, button) in buttons.enumerated()
		{
			let row = index / columns
			let column = index % columns
			let imagesInRow = min(
				columns,
				buttons.count - row * columns
			)
			let rowWidth = CGFloat(imagesInRow) * edge + CGFloat(imagesInRow - 1) * Self.spacing
			button.frame = NSRect(
				x: bounds.width - rowWidth + CGFloat(column) * (edge + Self.spacing),
				y: CGFloat(row) * (edge + Self.spacing),
				width: edge,
				height: edge
			)
		}
	}

	@objc private func openImage(_ sender: NSButton)
	{
		guard buttons.indices.contains(sender.tag), buttons[sender.tag] === sender,
				references.indices.contains(sender.tag)
		else
		{
			return
		}
		let reference = references[sender.tag]
		if InlineImageData.isDataURL(reference.path)
		{
			guard let window, sender.isEnabled
			else
			{
				return
			}
			inlinePreview.present(
				reference,
				in: window
			)
			return
		}
		guard let url = LocalAttachmentURL.resolve(reference.path),
				FileManager.default.isReadableFile(atPath: url.path)
		else
		{
			return
		}
		NSWorkspace.shared.open(url)
	}
}

@MainActor
private final class UserMessageImageButton: NSButton
{
	private static let progressSize: CGFloat = 16
	private let progress = NSProgressIndicator()

	func beginLoading()
	{
		progress.style = .spinning
		progress.controlSize = .small
		progress.isIndeterminate = true
		progress.setAccessibilityElement(false)
		addSubview(progress)
		progress.startAnimation(nil)
	}

	override func layout()
	{
		super.layout()
		progress.frame = NSRect(
			x: bounds.midX - Self.progressSize / 2,
			y: bounds.midY - Self.progressSize / 2,
			width: Self.progressSize,
			height: Self.progressSize
		)
	}

	private func endLoading()
	{
		progress.stopAnimation(nil)
		progress.removeFromSuperview()
	}

	var preview: NSImage?
	{
		didSet
		{
			endLoading()
			needsDisplay = true
		}
	}
	var unavailable = false
	{
		didSet
		{
			endLoading()
			needsDisplay = true
		}
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		NSGraphicsContext.saveGraphicsState()
		let outline = NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: 0.5,
				dy: 0.5
			),
			xRadius: 10,
			yRadius: 10
		)
		outline.addClip()
		DesktopTheme.canvas.setFill()
		outline.fill()
		if let preview
		{
			let scale = max(
				bounds.width / preview.size.width,
				bounds.height / preview.size.height
			)
			let size = NSSize(
				width: preview.size.width * scale,
				height: preview.size.height * scale
			)
			preview.draw(
				in: NSRect(
					x: bounds.midX - size.width / 2,
					y: bounds.midY - size.height / 2,
					width: size.width,
					height: size.height
				),
				from: .zero,
				operation: .sourceOver,
				fraction: 1,
				respectFlipped: true,
				hints: nil
			)
		}
		else if unavailable
		{
			let label = "Image unavailable"
			let paragraph = NSMutableParagraphStyle()
			paragraph.alignment = .center
			(label as NSString).draw(
				in: bounds.insetBy(
					dx: 5,
					dy: 24
				),
				withAttributes: [
					.font: NSFont.systemFont(ofSize: 10),
					.foregroundColor: NSColor.secondaryLabelColor,
					.paragraphStyle: paragraph,
				]
			)
		}
		DesktopTheme.border.setStroke()
		outline.lineWidth = 1
		outline.stroke()
		NSGraphicsContext.restoreGraphicsState()
	}
}
