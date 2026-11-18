import AppKit
import OpenAIStyle

typealias DesktopIcon = OAIIconName

@MainActor
enum DesktopIcons
{
	private static let cache = NSCache<NSString, NSImage>()

	/// Question action artwork uses the same rounded speech bubble in the card and transcript.
	static func questionBubble() -> NSImage
	{
		let svg = """
		<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" \
		fill="none" stroke="black" stroke-width="1.7" \
		stroke-linecap="round" stroke-linejoin="round">
		<path d="M21 11.5a9 9 0 0 1-13.4 7.85L3 21l1.65-4.6A9 9 0 1 1 21 11.5Z"/>
		<path d="M9.7 8.9a2.4 2.4 0 0 1 4.65.85c0 1.6-2.35 1.8-2.35 3.35"/>
		<circle cx="12" cy="16" r="0.5" fill="black" stroke="none"/>
		</svg>
		"""
		guard let image = NSImage(data: Data(svg.utf8))
		else
		{
			preconditionFailure("Invalid question bubble artwork")
		}
		image.size = NSSize(
			width: 16,
			height: 16
		)
		image.isTemplate = true
		return image
	}
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

	private static let imageCommentArtwork: NSImage =
	{
		let svg = """
		<svg height="16" viewBox="0 0 16 16" width="16" xmlns="http://www.w3.org/2000/svg">
		<path fill-rule="evenodd" clip-rule="evenodd" d="
		M7.86597 9.31152C7.57239 8.40984 8.43816 7.5611 9.33374 7.87305L14.3601
		9.62402C15.3387 9.96511 15.3983 11.3261 14.4539 11.752L12.6257 12.5752C12.6057
		12.5842 12.5889 12.6005 12.5789 12.6201L11.6287 14.5205C11.1702 15.4375 9.83031
		15.3378 9.51245 14.3633L7.86597 9.31152ZM8.98804 8.86426C8.91281 8.83833
		8.84077 8.90962 8.86499 8.98535L10.5105 14.0381C10.5195 14.0655 10.5317 14.0785
		10.5417 14.0859C10.5542 14.0952 10.573 14.1028 10.5955 14.1045C10.6178 14.1061
		10.6375 14.101 10.6511 14.0938C10.6621 14.0878 10.6764 14.0764 10.6892
		14.0508L11.6394 12.1504C11.7576 11.9145 11.9535 11.7255 12.1941 11.6172L14.0232
		10.7949C14.0496 10.7828 14.061 10.7685 14.0671 10.7578C14.0747 10.7444 14.0808
		10.7247 14.0798 10.7021C14.0787 10.6797 14.071 10.661 14.0623 10.6484C14.0551
		10.6383 14.0429 10.6249 14.0154 10.6152L8.98804 8.86426Z
		" fill="#000">
		</path>
		<path d="
		M2.66675 9.47461C2.9567 9.47461 3.19214 9.71005 3.19214 10V11.4668C3.19221
		12.2076 3.79223 12.8083 4.53296 12.8086H5.99976C6.2896 12.8086 6.52497 13.0432
		6.52515 13.333C6.52515 13.623 6.28971 13.8584 5.99976 13.8584H4.53296C3.21233
		13.8582 2.14143 12.7875 2.14136 11.4668V10C2.14136 9.71005 2.3768 9.47461
		2.66675 9.47461Z
		" fill="#000">
		</path>
		<path d="
		M11.4666 2.1416C12.7872 2.14167 13.8579 3.21258 13.8582 4.5332V6C13.8582
		6.28995 13.6227 6.52539 13.3328 6.52539C13.0431 6.52508 12.8083 6.28976 12.8083
		6V4.5332C12.8081 3.79247 12.2073 3.19245 11.4666 3.19238H9.99976C9.70992
		3.19225 9.47437 2.95686 9.47437 2.66699C9.47437 2.37712 9.70992 2.14173 9.99976
		2.1416H11.4666Z
		" fill="#000">
		</path>
		<path d="
		M5.99976 3.19238H4.53296C3.79234 3.19263 3.19238 3.79258 3.19214
		4.5332V6H2.14136V4.5332C2.1416 3.21268 3.21244 2.14185 4.53296
		2.1416H5.99976V3.19238Z
		" fill="#000">
		</path>
		</svg>
		"""
		guard let image = NSImage(data: Data(svg.utf8))
		else
		{
			preconditionFailure("Invalid image annotation artwork")
		}
		return image
	}()

	static func imageCommentAnnotation() -> NSImage
	{
		let image = imageCommentArtwork.copy() as! NSImage
		image.isTemplate = true
		return image
	}

	/// Six-dot template artwork for the floating annotation toolbar's drag target.
	static func imageCommentGrip() -> NSImage
	{
		let image = NSImage(
			size: NSSize(
				width: 16,
				height: 16
			),
			flipped: false
		)
		{
			_ in
			NSColor.black.setFill()
			for x in [5.0, 11.0]
			{
				for y in [3.0, 8.0, 13.0]
				{
					NSBezierPath(ovalIn: NSRect(
						x: x - 1,
						y: y - 1,
						width: 2,
						height: 2
					)).fill()
				}
			}
			return true
		}
		image.isTemplate = true
		return image
	}

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

	/// Template artwork keeps the local-device outline consistent in controls and menus.
	static func localComputerImage() -> NSImage
	{
		let key = "local-computer-outline" as NSString
		if let cached = cache.object(forKey: key)
		{
			return cached.copy() as! NSImage
		}
		// The fixed view box and black stroke describe a template mask, not a theme palette.
		let svg = """
		<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
		<g fill="none" stroke="black" stroke-width="1.5" stroke-linejoin="round">
		<path d="M4 17V6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v11"/>
		<rect x="2" y="17" width="20" height="3" rx="1"/>
		</g></svg>
		"""
		guard let image = NSImage(data: Data(svg.utf8))
		else
		{
			preconditionFailure("Invalid computer artwork")
		}
		image.size = NSSize(
			width: 16,
			height: 16
		)
		image.isTemplate = true
		cache.setObject(
			image,
			forKey: key
		)
		return image.copy() as! NSImage
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

	static func ultrafastBoltImage() -> NSImage
	{
		ultrafastBoltArtwork.copy() as! NSImage
	}

	private static let ultrafastBoltArtwork: NSImage =
	{
		// Two offset strokes distinguish Ultrafast at the same size as the standard bolt mask.
		let svg = """
		<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24">
		  <path fill="black" d="M13.2 2 2 13.3h7.1L7.6 22l11-12.3h-7.1z"/>
		  <path fill="none" stroke="black" stroke-width="1.7" stroke-linecap="round"
		        stroke-linejoin="round" d="m17 3-1.1 4.3H22L11.7 21"/>
		</svg>
		"""
		guard let image = NSImage(data: Data(svg.utf8))
		else
		{
			preconditionFailure("Invalid Ultrafast bolt artwork")
		}
		image.isTemplate = true
		return image
	}()

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
