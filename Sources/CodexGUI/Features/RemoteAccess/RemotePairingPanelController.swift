import AppKit
import CoreImage

@MainActor
final class RemotePairingQRView: NSView
{
	var pairingCode = ""
	{
		didSet
		{
			needsDisplay = true
		}
	}
	var showsLogo = true

	static func pairingURL(code: String) -> URL?
	{
		var url = URLComponents(string: "https://chatgpt.com/codex/pair")
		url?.queryItems = [URLQueryItem(
			name: "pairing_code",
			value: code
		)]
		return url?.url
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		guard let url = Self.pairingURL(code: pairingCode),
				let filter = CIFilter(name: "CIQRCodeGenerator")
		else
		{
			return
		}
		filter.setValue(
			Data(url.absoluteString.utf8),
			forKey: "inputMessage"
		)
		filter.setValue(
			"H",
			forKey: "inputCorrectionLevel"
		)
		guard let output = filter.outputImage,
				let image = CIContext().createCGImage(
				output,
				from: output.extent
				),
				let data = image.dataProvider?.data,
				let bytes = CFDataGetBytePtr(data)
		else
		{
			return
		}
		let background = showsLogo ? AppKitColorTokens.pairingQR
			: AppKitColorTokens.fullscreenQR
		let ink = AppKitColorTokens.pairingQRInk
		background.setFill()
		NSBezierPath(
			roundedRect: bounds,
			xRadius: showsLogo ? ShapeTokens.Connections.pairingFrameRadius
				: ShapeTokens.Connections.fullscreenRadius,
			yRadius: showsLogo ? ShapeTokens.Connections.pairingFrameRadius
				: ShapeTokens.Connections.fullscreenRadius
		).fill()
		// Core Image includes a one-module quiet border; data coordinates start inside it.
		let count = image.width - 2
		let cell = bounds.width / CGFloat(count + 8)
		ink.setFill()
		func moduleRect(
			_ x: Int,
			_ y: Int,
			_ size: Int = 1
		) -> NSRect
		{
			NSRect(
				x: CGFloat(x + 4) * cell,
				y: CGFloat(count - y + 4 - size) * cell,
				width: CGFloat(size) * cell,
				height: CGFloat(size) * cell
			)
		}
		for y in 0 ..< count
		{
			for x in 0 ..< count
			{
				let finder = (x < 7 && y < 7) || (x >= count - 7 && y < 7)
					|| (x < 7 && y >= count - 7)
				if !finder &&
					bytes[(y + 1) * image.bytesPerRow + (x + 1) * (image.bitsPerPixel / 8)] < 128
				{
					NSBezierPath(ovalIn: moduleRect(
						x,
						y
					).insetBy(
						dx: cell * 0.06,
						dy: cell * 0.06
					))
					.fill()
				}
			}
		}
		for (x, y) in [(0, 0), (count - 7, 0), (0, count - 7)]
		{
			ink.setFill()
			NSBezierPath(
				roundedRect: moduleRect(
					x,
					y,
					7
				),
				xRadius: cell * 1.5,
				yRadius: cell * 1.5
			)
			.fill()
			background.setFill()
			NSBezierPath(
				roundedRect: moduleRect(
					x + 1,
					y + 1,
					5
				),
				xRadius: cell,
				yRadius: cell
			)
			.fill()
			ink.setFill()
			NSBezierPath(
				roundedRect: moduleRect(
					x + 2,
					y + 2,
					3
				),
				xRadius: cell * 0.75,
				yRadius: cell * 0.75
			).fill()
		}

		if showsLogo, let logo = Self.resourceImage("Logo")
		{
			let size = bounds.width * 0.18
			let rect = NSRect(
				x: bounds.midX - size / 2,
				y: bounds.midY - size / 2,
				width: size,
				height: size
			)
			background.setFill()
			rect.insetBy(
				dx: -cell,
				dy: -cell
			).fill()
			logo.draw(in: rect)
		}
	}

	static func resourceImage(_ name: String) -> NSImage?
	{
		let base = Bundle.main.resourceURL?.appendingPathComponent("CodexGUI_CodexGUI.bundle")
		let bundle = base.flatMap(Bundle.init(url:)) ?? Bundle.module
		return bundle.url(
			forResource: name,
			withExtension: "png",
			subdirectory: "RemoteAccess"
		)
		.flatMap(NSImage.init(contentsOf:))
	}
}
