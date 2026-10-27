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

	private static let skillMentionArtwork: NSImage =
	{
		// ChatGPT Desktop's fallback skill-mention artwork, in its original 20-point view box.
		let svg = """
		<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">
		  <path fill="#000" d="
		    M 9.79 18.5102 C 9.48333 18.6969 9.15333 18.7869 8.8 18.7802 C 8.45333 18.7736 8.13
		    18.6669 7.83 18.4602 L 4.35 16.0802 C 4.07666 15.8936 3.86333 15.6569 3.71 15.3702 C
		    3.55666 15.0836 3.48 14.7802 3.48 14.4602 V 6.53024 C 3.48 6.20358 3.55333 5.90691 3.7
		    5.64024 C 3.85333 5.37358 4.07333 5.15358 4.36 4.98024 L 10.08 1.46024 C 10.4067
		    1.26024 10.76 1.16358 11.14 1.17024 C 11.52 1.17024 11.87 1.27691 12.19 1.49024 L
		    15.71 3.89024 C 15.97 4.07691 16.17 4.30024 16.31 4.56024 C 16.45 4.81358 16.52
		    5.09358 16.52 5.40024 V 13.2902 C 16.52 13.6236 16.4367 13.9402 16.27 14.2402 C
		    16.1033 14.5402 15.8733 14.7769 15.58 14.9502 L 9.79 18.5102 Z  M 14.38 4.66024 L
		    11.42 2.64024 C 11.3267 2.57358 11.2233 2.54024 11.11 2.54024 C 11.0033 2.53358
		    10.9033 2.56024 10.81 2.62024 L 5.5 5.89024 L 8.77 8.11024 L 14.38 4.66024 Z  M 8.14
		    9.33025 L 4.86 7.11024 V 10.2102 L 8.14 12.4502 V 9.33025 Z  M 8.14 14.0402 L 4.86
		    11.8002 V 14.4602 C 4.86 14.5602 4.88 14.6536 4.92 14.7402 C 4.96 14.8202 5.02333
		    14.8902 5.11 14.9502 L 8.14 17.0202 V 14.0402 Z  M 15.14 8.89024 V 5.81024 L 9.52
		    9.26025 V 12.3502 L 15.14 8.89024 Z  M 14.86 13.7902 C 14.9533 13.7302 15.0233 13.6602
		    15.07 13.5802 C 15.1167 13.4936 15.14 13.3969 15.14 13.2902 V 10.4802 L 9.52 13.9402 V
		    17.0702 L 14.86 13.7902 Z
		  "/>
		</svg>
		"""
		guard let image = NSImage(data: Data(svg.utf8))
		else
		{
			preconditionFailure("Invalid skill mention artwork")
		}
		return image
	}()

	static func skillMentionImage() -> NSImage
	{
		let image = skillMentionArtwork.copy() as! NSImage
		image.size = NSSize(
			width: 16,
			height: 16
		)
		return image
	}

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

	static func draw(
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
