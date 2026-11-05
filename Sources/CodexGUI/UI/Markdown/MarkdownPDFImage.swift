import AppKit

/// Keeps prepared HTML math as vector artwork without retaining its web view.
final class MarkdownPDFImage: NSImage, @unchecked Sendable
{
	let pdfData: Data

	init?(data: Data, size: NSSize)
	{
		guard data.count <= 4_194_304,
				size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
				let representation = NSPDFImageRep(data: data)
		else
		{
			return nil
		}
		pdfData = data
		super.init(size: size)
		addRepresentation(representation)
		cacheMode = .never
	}

	override init(size: NSSize)
	{
		pdfData = Data()
		super.init(size: size)
	}

	required init(coder: NSCoder)
	{
		pdfData = Data()
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
		MarkdownPDFImage(
			data: pdfData,
			size: size
		) ?? super.copy(with: zone)
	}
}
