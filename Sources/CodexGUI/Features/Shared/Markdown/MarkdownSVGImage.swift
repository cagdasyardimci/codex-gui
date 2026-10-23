import AppKit

/// Retains SVG source and a vector display representation. WebKit supplies PDF for Mermaid's
/// CSS and text positioning, which AppKit's direct SVG decoder does not fully support.
final class MarkdownSVGImage: NSImage, @unchecked Sendable
{
	let svgData: Data
	let pdfData: Data?
	var retainedByteCount: Int
	{
		svgData.count + (pdfData?.count ?? 0)
	}

	init?(data: Data, size: NSSize, pdfData: Data? = nil)
	{
		guard data.count <= 1_048_576,
				size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
				let markup = String(
				data: data,
				encoding: .utf8
				), markup.hasPrefix("<svg"),
				((pdfData?.count ?? 0) <= 4_194_304),
				let decoded = NSImage(data: pdfData ?? data), !decoded.representations.isEmpty,
				decoded.representations.allSatisfy(
				{
					!($0 is NSBitmapImageRep)
				}
				)
		else
		{
			return nil
		}
		svgData = data
		self.pdfData = pdfData
		super.init(size: size)
		addRepresentations(decoded.representations)
		// Draw from the vector representation again at each requested scale.
		cacheMode = .never
	}

	override init(size: NSSize)
	{
		svgData = Data()
		pdfData = nil
		super.init(size: size)
	}

	required init(coder: NSCoder)
	{
		svgData = Data()
		pdfData = nil
		super.init(coder: coder)
	}

	required convenience init?(
		pasteboardPropertyList propertyList: Any,
		ofType type: NSPasteboard.PasteboardType
	)
	{
		return nil
	}

	override func copy(with zone: NSZone? = nil) -> Any
	{
		MarkdownSVGImage(
			data: svgData,
			size: size,
			pdfData: pdfData
		) ?? super.copy(with: zone)
	}
}
