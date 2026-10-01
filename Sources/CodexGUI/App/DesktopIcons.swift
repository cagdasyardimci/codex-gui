import AppKit
import OpenAIStyle

typealias DesktopIcon = OAIIconName

@MainActor
enum DesktopIcons
{
	private static let cache = NSCache<NSString, NSImage>()

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
		let source = image(
			icon,
			size: max(
				rect.width,
				rect.height
			)
		)
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
