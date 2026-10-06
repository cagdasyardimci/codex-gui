import AppKit
import Testing

/// Renders an already-laid-out AppKit view for optional integration-test evidence.
@MainActor
enum AppTestPNGWriter
{
	static func write(
		_ view: NSView,
		to url: URL
	) throws
	{
		let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
		view.cacheDisplay(
			in: view.bounds,
			to: bitmap
		)
		let data = try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
		try data.write(to: url)
	}
}
