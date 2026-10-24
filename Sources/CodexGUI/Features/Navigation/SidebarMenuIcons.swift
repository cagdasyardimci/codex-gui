import AppKit

@MainActor
enum SidebarMenuIcons
{
	/// The sidebar sort glyph places the downward arrow on the left.
	static let sort: NSImage =
	{
		let svg = """
		<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
		<g fill="none" stroke="#000" stroke-width="1.05" stroke-linecap="round"
		stroke-linejoin="round">
		<path d="M4.667 3.667V12.6M1.999 10.193l2.668 2.727 2.667-2.727"/>
		<path d="M11.333 12.333V3.5M8.667 5.89l2.666-2.727L14 5.89"/>
		</g></svg>
		"""
		guard let image = NSImage(data: Data(svg.utf8))
		else
		{
			preconditionFailure("Invalid sidebar sort artwork")
		}
		image.isTemplate = true
		return image
	}()
}
