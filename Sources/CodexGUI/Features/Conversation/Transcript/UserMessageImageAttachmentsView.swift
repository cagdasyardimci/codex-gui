import AppKit
import ImageIO

@MainActor
final class UserMessageImageAttachmentsView: NSView
{
	static let thumbnailSize: CGFloat = 80
	static let spacing: CGFloat = 8
	private var buttons: [UserMessageImageButton] = []
	private var references: [UserMessageReference] = []
	private var imageTasks: [Task<Void, Never>] = []
	private var generation = 0
	private static let imageCache = NSCache<NSString, NSImage>()

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
		return CGFloat(rows) * min(
			thumbnailSize,
			max(
				1,
				width
			)
		)
			+ CGFloat(rows - 1) * spacing
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
			button.setAccessibilityLabel("Open attached image: \(reference.name)")
			button.setAccessibilityHelp(reference.path)
			addSubview(button)
			buttons.append(button)
			if let cached = Self.imageCache.object(forKey: reference.path as NSString)
			{
				button.preview = cached
				continue
			}
			let task = Task
			{
				[weak self, weak button] in
				let thumbnail = await UserMessageImageThumbnailLoader.shared
					.load(path: reference.path)
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
					size: .zero
				)
				Self.imageCache.countLimit = 64
				Self.imageCache.setObject(
					image,
					forKey: reference.path as NSString
				)
				button.preview = image
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

	override func layout()
	{
		super.layout()
		let columns = Self.columns(width: bounds.width)
		let edge = min(
			Self.thumbnailSize,
			max(
				1,
				bounds.width
			)
		)
		for (index, button) in buttons.enumerated()
		{
			let row = index / columns
			let column = index % columns
			let count = min(
				columns,
				buttons.count - row * columns
			)
			let rowWidth = CGFloat(count) * edge + CGFloat(count - 1) * Self.spacing
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
		NSWorkspace.shared.open(URL(fileURLWithPath: references[sender.tag].path))
	}
}

@MainActor
private final class UserMessageImageButton: NSButton
{
	var preview: NSImage?
	{
		didSet
		{
			needsDisplay = true
		}
	}
	var unavailable = false
	{
		didSet
		{
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
		else
		{
			let label = unavailable ? "Image unavailable" : "Loading…"
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

private final class UserMessageImageThumbnail: @unchecked Sendable
{
	let image: CGImage

	init(image: CGImage)
	{
		self.image = image
	}

	static func load(path: String) -> Self?
	{
		guard !Task.isCancelled, NSString(string: path).isAbsolutePath
		else
		{
			return nil
		}
		let url = URL(fileURLWithPath: path)
		guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
				values.isRegularFile == true, let size = values.fileSize, size <= 32 * 1024 * 1024,
				let source = CGImageSourceCreateWithURL(
				url as CFURL,
				[kCGImageSourceShouldCache: false] as CFDictionary
				),
				let image = CGImageSourceCreateThumbnailAtIndex(
				source,
				0,
				[
					kCGImageSourceCreateThumbnailFromImageAlways: true,
					kCGImageSourceThumbnailMaxPixelSize: 320,
					kCGImageSourceCreateThumbnailWithTransform: true,
					kCGImageSourceShouldCacheImmediately: false,
				] as CFDictionary
				)
		else
		{
			return nil
		}
		return Self(image: image)
	}
}

/// Serial image decoding keeps histories with many attachments off the main actor.
private actor UserMessageImageThumbnailLoader
{
	static let shared = UserMessageImageThumbnailLoader()
	private let cache = NSCache<NSString, UserMessageImageThumbnail>()

	func load(path: String) -> UserMessageImageThumbnail?
	{
		guard !Task.isCancelled
		else
		{
			return nil
		}
		if let cached = cache.object(forKey: path as NSString)
		{
			return cached
		}
		guard let thumbnail = UserMessageImageThumbnail.load(path: path)
		else
		{
			return nil
		}
		cache.countLimit = 64
		cache.setObject(
			thumbnail,
			forKey: path as NSString
		)
		return thumbnail
	}
}
