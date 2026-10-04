import AppKit
import OpenAIStyle

typealias DesktopIcon = OAIIconName

@MainActor
enum DesktopIcons
{
	private static let cache = NSCache<NSString, NSImage>()
	private static let filledBoltArtwork: NSImage =
	{
		// OpenAIStyle's Bolt.svg outer contour, with its inner cutout filled.
		// This preserves the package icon's silhouette and dimensions.
		let svg = """
		<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
		  <path fill="#000000" d="
		    M15.24 3.486v.002l-1.056 4.517h5.823
		    c1.726 0 2.596 2.021 1.518 3.3l-.002.003-9.308 10.965-.002.002
		    c-1.397 1.656-3.922.223-3.454-1.76v-.003l1.057-4.517H3.993
		    c-1.726 0-2.596-2.021-1.519-3.3l.003-.003 9.308-10.965.002-.002
		    c1.397-1.656 3.922-.223 3.454 1.76Z"/>
		</svg>
		"""
		guard let image = NSImage(data: Data(svg.utf8))
		else
		{
			preconditionFailure("Invalid filled Bolt artwork")
		}
		return image
	}()

	static func image(
		_ icon: DesktopIcon,
		size: CGFloat = 16,
		accessibilityDescription: String? = nil
	) -> NSImage
	{
		// Copy cached artwork before applying per-control sizing and template state.
		let image = sourceImage(icon).copy() as! NSImage
		image.size = NSSize(
			width: size,
			height: size
		)
		image.isTemplate = true
		image.accessibilityDescription = accessibilityDescription
		return image
	}

	static func filledBoltImage(size: CGFloat = 16) -> NSImage
	{
		let image = filledBoltArtwork.copy() as! NSImage
		image.size = NSSize(
			width: size,
			height: size
		)
		image.isTemplate = true
		return image
	}

	private static func sourceImage(_ icon: DesktopIcon) -> NSImage
	{
		guard Bundle.main.bundleURL.pathExtension == "app"
		else
		{
			return OAIIcon.image(icon)
		}
		if let image = cache.object(forKey: icon.rawValue as NSString)
		{
			return image
		}
		// SwiftPM's accessor looks at the .app root, which macOS code signing disallows.
		// Packaged launches load the same dependency resources from Contents/Resources.
		guard let bundleURL = Bundle.main.resourceURL?
			.appendingPathComponent("OpenAIStyle_OpenAIStyle.bundle"),
			let bundle = Bundle(url: bundleURL),
			let url = bundle.url(
				forResource: icon.rawValue,
				withExtension: "svg"
			),
			let image = NSImage(contentsOf: url)
		else
		{
			preconditionFailure("Missing bundled interface icon: \(icon.rawValue)")
		}
		cache.setObject(
			image,
			forKey: icon.rawValue as NSString
		)
		return image
	}

	static func draw(
		_ icon: DesktopIcon,
		in rect: NSRect,
		tint: NSColor
	)
	{
		draw(
			image(
				icon,
				size: max(
					rect.width,
					rect.height
				)
			),
			in: rect,
			tint: tint
		)
	}

	static func drawFilledBolt(
		in rect: NSRect,
		tint: NSColor
	)
	{
		draw(
			filledBoltImage(size: max(
				rect.width,
				rect.height
			)),
			in: rect,
			tint: tint
		)
	}

	private static func draw(
		_ source: NSImage,
		in rect: NSRect,
		tint: NSColor
	)
	{
		let tinted = NSImage(size: rect.size)
		tinted.lockFocus()
		let bounds = NSRect(
			origin: .zero,
			size: rect.size
		)
		source.draw(in: bounds)
		tint.setFill()
		bounds.fill(using: .sourceIn)
		tinted.unlockFocus()
		tinted.draw(
			in: rect,
			from: .zero,
			operation: .sourceOver,
			fraction: 1,
			respectFlipped: true,
			hints: nil
		)
	}
}
