import AppKit

@MainActor
final class RemoteConnectionsArtwork: NSView
{
	private let artwork: NSImage

	private let artworkSize: NSSize

	init(
		name: String = "Devices",
		size: NSSize = NSSize(
			width: 61 * 24 / 23,
			height: 24
		)
	)
	{
		artwork = Self.image(named: name)
		artworkSize = size
		super.init(frame: .zero)
		setAccessibilityElement(false)
	}

	static func image(named name: String) -> NSImage
	{
		let base = Bundle.main.resourceURL?.appendingPathComponent("CodexGUI_CodexGUI.bundle")
		let bundle = base.flatMap(Bundle.init(url:)) ?? Bundle.module
		guard let url = bundle.url(
			forResource: name,
			withExtension: "svg",
			subdirectory: "RemoteAccess"
		), let image = NSImage(contentsOf: url)
		else
		{
			preconditionFailure("Missing connection artwork: \(name)")
		}
		return image
	}

	required init?(coder: NSCoder)
	{
		nil
	}
	override var intrinsicContentSize: NSSize
	{
		artworkSize
	}
	override func draw(_ dirtyRect: NSRect)
	{
		DesktopIcons.draw(
			artwork,
			in: bounds,
			tint: AppKitColorTokens.settingsPrimaryText
		)
	}
	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}
}
