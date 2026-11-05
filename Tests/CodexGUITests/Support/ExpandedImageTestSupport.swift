import AppKit
import Testing

@MainActor
enum ExpandedImageTestSupport
{
	/// Inspect only child windows owned by the fixture's parent.
	static func preview(in parent: NSWindow) throws -> NSView
	{
		let previews = (parent.childWindows ?? []).compactMap
		{
			$0.contentView.flatMap(findPreview)
		}
		#expect(previews.count == 1)
		return try #require(previews.first)
	}

	private static func findPreview(in view: NSView) -> NSView?
	{
		if view.accessibilityIdentifier() == "expanded-image-preview"
		{
			return view
		}
		return view.subviews.lazy.compactMap
		{
			findPreview(in: $0)
		}.first
	}
}
