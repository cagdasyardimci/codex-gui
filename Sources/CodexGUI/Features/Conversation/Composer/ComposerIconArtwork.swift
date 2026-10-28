import AppKit

@MainActor
enum ComposerIconArtwork
{
	static func image(
		viewBox: Int,
		path: String,
		usesEvenOddFill: Bool = false
	) -> NSImage
	{
		let svg = """
		<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"
		viewBox="0 0 \(viewBox) \(viewBox)">
		<path fill="#000000" fill-rule="\(usesEvenOddFill ? "evenodd" : "nonzero")"
		d="\(path)"/></svg>
		"""
		guard let image = NSImage(data: Data(svg.utf8))
		else
		{
			preconditionFailure("Invalid composer artwork")
		}
		image.isTemplate = true
		return image
	}
}
