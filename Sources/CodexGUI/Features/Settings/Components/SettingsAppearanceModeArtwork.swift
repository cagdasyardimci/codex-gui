import AppKit

/// Fixed neutral plates identify the modes independently of custom theme profiles. Their accent
/// marks use the shared template-image path and semantic ink. Prepared vector PDF plates retain
/// the source SVG's filter and shadow composition without a runtime web renderer.
@MainActor
enum SettingsAppearanceModeArtwork
{
	private struct Plate
	{
		let background: NSImage
		let accent: NSImage
	}

	private static let light = load("Light")
	private static let dark = load("Dark")

	static func draw(
		dark: Bool,
		accent: NSColor,
		in bounds: NSRect
	)
	{
		let plate = dark ? Self.dark : light
		plate.background.draw(
			in: bounds,
			from: .zero,
			operation: .sourceOver,
			fraction: 1,
			respectFlipped: true,
			hints: nil
		)
		DesktopIcons.draw(
			plate.accent,
			in: bounds,
			tint: accent
		)
	}

	private static func load(_ name: String) -> Plate
	{
		func image(
			_ name: String,
			extension fileExtension: String
		) -> NSImage
		{
			guard let url = Bundle.module.url(
				forResource: name,
				withExtension: fileExtension,
				subdirectory: "AppearanceModes"
			), let image = NSImage(contentsOf: url)
			else
			{
				preconditionFailure("Missing appearance mode artwork")
			}
			image.cacheMode = .never
			return image
		}
		return Plate(
			background: image(
				name,
				extension: "pdf"
			),
			accent: image(
				name + "Accent",
				extension: "svg"
			)
		)
	}
}
