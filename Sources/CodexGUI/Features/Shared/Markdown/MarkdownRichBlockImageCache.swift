import AppKit

/// Retains immutable image pairs independently of each message's source and attachment cells.
@MainActor
final class MarkdownRichBlockImageCache
{
	struct Key: Hashable
	{
		enum Kind: Hashable
		{
			case math, diagram
		}

		let kind: Kind
		let payload: Data
		let parameters: [CGFloat]
	}

	struct Images
	{
		let light: NSImage
		let dark: NSImage
		let lightSize: NSSize
		let darkSize: NSSize
		var baselineDescent: CGFloat = 0
		let pixelCount: Int
		let byteCount: Int

		init(
			light: CGImage,
			dark: CGImage,
			lightSize: NSSize,
			darkSize: NSSize,
			baselineDescent: CGFloat = 0
		)
		{
			self.light = NSImage(
				cgImage: light,
				size: lightSize
			)
			self.dark = NSImage(
				cgImage: dark,
				size: darkSize
			)
			self.lightSize = lightSize
			self.darkSize = darkSize
			self.baselineDescent = baselineDescent
			pixelCount = light.width * light.height + dark.width * dark.height
			byteCount = light.bytesPerRow * light.height + dark.bytesPerRow * dark.height
		}

		init(
			light: MarkdownSVGImage,
			dark: MarkdownSVGImage
		)
		{
			self.light = light
			self.dark = dark
			lightSize = light.size
			darkSize = dark.size
			pixelCount = 0
			byteCount = light.retainedByteCount + dark.retainedByteCount
		}

		/// Charge retained SVG/PDF bytes or raster bytes (including row padding) in RGBA units.
		var budgetPixelCost: Int
		{
			(byteCount + 3) / 4
		}

		@MainActor
		func attachment(
			source: String,
			isDiagram: Bool = false
		) -> MarkdownRichAttachment
		{
			// NSImage accessibility metadata and cell geometry belong to one displayed occurrence.
			MarkdownRichAttachment(
				source: source,
				lightImage: light.copy() as? NSImage,
				darkImage: dark.copy() as? NSImage,
				imageByteCount: byteCount,
				isDiagram: isDiagram
			)
		}
	}

	private struct Entry
	{
		let images: Images
		let byteCount: Int
		var lastUse: Int
	}

	private let capacity: Int
	private let byteCapacity: Int
	private var entries: [Key: Entry] = [:]
	private var storedBytes = 0
	private var clock = 0

	init(
		capacity: Int = 32,
		byteCapacity: Int = 6 * 1_024 * 1_024
	)
	{
		self.capacity = max(
			0,
			capacity
		)
		self.byteCapacity = max(
			0,
			byteCapacity
		)
	}

	func images(for key: Key) -> Images?
	{
		guard var entry = entries[key]
		else
		{
			return nil
		}
		clock += 1
		entry.lastUse = clock
		entries[key] = entry
		return entry.images
	}

	func insert(
		_ images: Images,
		for key: Key
	)
	{
		let byteCount = images.byteCount + key.payload.count + key.parameters.count * 8 + 128
		guard capacity > 0, byteCount <= byteCapacity
		else
		{
			return
		}
		if let replaced = entries.removeValue(forKey: key)
		{
			storedBytes -= replaced.byteCount
		}
		while entries.count >= capacity || byteCount > byteCapacity - storedBytes
		{
			guard let oldest = entries.min(by:
				{
					$0.value.lastUse < $1.value.lastUse
				})
			else
			{
				return
			}
			storedBytes -= oldest.value.byteCount
			entries.removeValue(forKey: oldest.key)
		}
		clock += 1
		entries[key] = Entry(
			images: images,
			byteCount: byteCount,
			lastUse: clock
		)
		storedBytes += byteCount
	}
}
